import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/permissions/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/davex_alert.dart';
import '../../design_system/components/davex_area_chart.dart';
import '../../design_system/components/davex_button.dart';
import '../../design_system/components/davex_donut_chart.dart';
import '../../design_system/components/davex_metric_card.dart';
import '../../design_system/components/davex_pressable.dart';
import '../../design_system/components/davex_sheet.dart';
import '../../design_system/components/davex_states.dart';
import '../../design_system/components/davex_status_badge.dart';
import '../../design_system/components/davex_sync_indicator.dart';
import '../../design_system/components/davex_tone.dart';
import '../../design_system/components/sync_indicator.dart'
    show LkSyncTransport;
import '../../l10n/app_strings.dart';
import '../../shared/services/report_service.dart';

// ─── Données réelles (Drift) — agrégat unique de l'Accueil ───────────────────

class _PaymentSlice {
  const _PaymentSlice(this.mode, this.amount, this.count, this.color);
  final String mode;
  final double amount;
  final int count;
  final Color color;
}

class _CategorySlice {
  const _CategorySlice(this.name, this.amount, this.itemsCount);
  final String name;
  final double amount;
  final int itemsCount;
}

class _AccueilData {
  const _AccueilData({
    required this.report,
    required this.stock,
    required this.salesToday,
    required this.itemsBySale,
    required this.alertProducts,
    required this.debtOutstanding,
    required this.expensesToday,
    required this.hourly,
    required this.weekly,
    required this.monthly,
    required this.payments,
    required this.categories,
    required this.marginPct,
    required this.peak,
  });

  final DailyReport report;
  final Map<String, double> stock;
  final List<Sale> salesToday;
  final Map<String, String> itemsBySale;
  final List<Product> alertProducts;
  final double debtOutstanding;
  final double expensesToday;
  final List<DavexChartPoint> hourly;
  final List<DavexChartPoint> weekly;
  final List<DavexChartPoint> monthly;
  final List<_PaymentSlice> payments;
  final List<_CategorySlice> categories;

  /// Marge brute du jour (0..1) ou null si coût de revient inconnu.
  final double? marginPct;
  final DavexChartPoint? peak;

  bool get hasAnySalesToday => salesToday.isNotEmpty;
}

final _accueilProvider = FutureProvider.autoDispose<_AccueilData?>((
  ref,
) async {
  final session = ref.watch(sessionProvider);
  final business = session.business;
  if (business == null) return null;
  final db = ref.watch(databaseProvider);
  final reports = ref.watch(reportServiceProvider);
  final bid = business.id;

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = todayStart.add(const Duration(days: 1));
  final monthStart = todayStart.subtract(const Duration(days: 27));

  final report = await reports.daily(bid);
  final stock = await reports.stockValue(bid);
  final sales28d = await db.getSales(
    bid,
    from: monthStart,
    to: todayEnd,
    limit: 10000,
  );
  final products = await db.getProducts(bid);
  final debtors = await db.getDebtors(bid);

  final completed = sales28d.where((s) => s.status == 'completed').toList();
  final salesToday = completed
      .where((s) => !s.soldAt.isBefore(todayStart))
      .toList();

  // Articles du jour (marge + catégories + libellés des ventes récentes).
  final itemsToday = <SaleItem>[];
  final itemsBySale = <String, String>{};
  for (final s in salesToday) {
    final its = await db.getSaleItems(s.id);
    itemsToday.addAll(its);
    itemsBySale[s.id] = its
        .map(
          (i) => i.quantity > 1 && i.quantity == i.quantity.roundToDouble()
              ? '${i.productName} × ${i.quantity.toInt()}'
              : i.productName,
        )
        .join(' · ');
  }
  final productById = {for (final p in products) p.id: p};

  // Alertes de stock : rupture d'abord, puis seuil.
  final alertProducts = products
      .where((p) => p.trackStock && p.stockQty <= p.lowStockThreshold)
      .toList()
    ..sort((a, b) => a.stockQty.compareTo(b.stockQty));

  final debtOutstanding = debtors.fold<double>(0, (s, c) => s + c.balance);
  final expensesToday = report.expenses;

  // — Courbes : heures (aujourd'hui), 7 jours, 4 semaines —
  final byHour = <int, ({double amount, int sales})>{};
  for (final s in salesToday) {
    final h = s.soldAt.hour;
    final cur = byHour[h] ?? (amount: 0, sales: 0);
    byHour[h] = (amount: cur.amount + s.total, sales: cur.sales + 1);
  }
  var hours = byHour.keys.toList()..sort();
  if (hours.length > 7) {
    // Garder les 7 heures les plus fortes, réordonnées chronologiquement.
    hours = (hours
        ..sort(
          (a, b) => byHour[b]!.amount.compareTo(byHour[a]!.amount),
        ))
        .take(7)
        .toList()
      ..sort();
  }
  final hourly = [
    for (final h in hours)
      DavexChartPoint(
        label: '${h}h',
        amount: byHour[h]!.amount,
        sales: byHour[h]!.sales,
      ),
  ];

  DavexChartPoint? peak;
  for (final p in hourly) {
    if (peak == null || p.sales > peak.sales) peak = p;
  }

  const frDays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  const enDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final dayNames = S.isEnglish ? enDays : frDays;
  final weekly = <DavexChartPoint>[];
  for (var i = 6; i >= 0; i--) {
    final d = todayStart.subtract(Duration(days: i));
    final daySales = completed.where(
      (s) =>
          !s.soldAt.isBefore(d) && s.soldAt.isBefore(d.add(const Duration(days: 1))),
    );
    weekly.add(
      DavexChartPoint(
        label: dayNames[(d.weekday - 1) % 7],
        amount: daySales.fold<double>(0, (m, s) => m + s.total),
        sales: daySales.length,
      ),
    );
  }

  final monthly = <DavexChartPoint>[];
  for (var w = 3; w >= 0; w--) {
    final from = todayStart.subtract(Duration(days: 7 * w + 6));
    final to = todayStart.subtract(Duration(days: 7 * w)).add(
      const Duration(microseconds: -1),
    );
    final bucket = completed.where(
      (s) => !s.soldAt.isBefore(from) && !s.soldAt.isAfter(to),
    );
    monthly.add(
      DavexChartPoint(
        label: S.tr('Sem ${4 - w}', 'Wk ${4 - w}'),
        amount: bucket.fold<double>(0, (m, s) => m + s.total),
        sales: bucket.length,
      ),
    );
  }
  _markPeaks(weekly);
  _markPeaks(monthly);
  _markPeaks(hourly);

  // — Donut modes de paiement (aujourd'hui) —
  final payTotals = <String, ({double amount, int count})>{};
  for (final s in salesToday) {
    final mode = _classifyPayment(s);
    final cur = payTotals[mode] ?? (amount: 0, count: 0);
    payTotals[mode] = (amount: cur.amount + s.total, count: cur.count + 1);
  }
  final payments = <_PaymentSlice>[
    for (final entry in payTotals.entries)
      if (entry.value.amount > 0)
        _PaymentSlice(
          _paymentLabel(entry.key),
          entry.value.amount,
          entry.value.count,
          _paymentColor(entry.key),
        ),
  ]..sort((a, b) => b.amount.compareTo(a.amount));

  // — Barres par catégorie (aujourd'hui) —
  final catTotals = <String, ({double amount, Set<String> prods})>{};
  double catGrand = 0;
  for (final i in itemsToday) {
    final p = i.productId == null ? null : productById[i.productId];
    final cat = _prettyCategory(p?.categoryId);
    final cur = catTotals[cat] ?? (amount: 0, prods: <String>{});
    catTotals[cat] = (amount: cur.amount + i.lineTotal, prods: {...cur.prods, i.productName});
    catGrand += i.lineTotal;
  }
  final categories = <_CategorySlice>[
    for (final entry in catTotals.entries)
      _CategorySlice(entry.key, entry.value.amount, entry.value.prods.length),
  ]
    ..sort((a, b) => b.amount.compareTo(a.amount));
  if (catGrand > 0) {
    // (le pourcentage est calculé à l'affichage sur catGrand rapporté au CA)
  }

  // — Marge brute du jour —
  double marginSales = 0;
  double marginCost = 0;
  for (final i in itemsToday) {
    marginSales += i.lineTotal;
    marginCost += i.costPrice * i.quantity;
  }
  final marginPct = marginSales > 0
      ? ((marginSales - marginCost) / marginSales).clamp(0.0, 1.0)
      : null;

  return _AccueilData(
    report: report,
    stock: stock,
    salesToday: salesToday,
    itemsBySale: itemsBySale,
    alertProducts: alertProducts,
    debtOutstanding: debtOutstanding,
    expensesToday: expensesToday,
    hourly: hourly,
    weekly: weekly,
    monthly: monthly,
    payments: payments,
    categories: categories,
    marginPct: marginPct,
    peak: peak,
  );
});

void _markPeaks(List<DavexChartPoint> points) {
  if (points.isEmpty) return;
  final max = points.fold<double>(0, (m, p) => p.amount > m ? p.amount : m);
  if (max <= 0) return;
  // Pic = sommet (≥ 90 % du max), comme la maquette.
  for (var i = 0; i < points.length; i++) {
    if (points[i].amount >= max * 0.9) {
      points[i] = DavexChartPoint(
        label: points[i].label,
        amount: points[i].amount,
        sales: points[i].sales,
        isPeak: true,
      );
    }
  }
}

/// Classification maquette (4 modes) depuis paymentMethodsJson + restant dû :
/// parties multiples ou encaissement partiel → Mixte ; sinon mode unique.
String _classifyPayment(Sale s) {
  List parts = const [];
  try {
    final decoded = jsonDecode(s.paymentMethodsJson);
    if (decoded is List) parts = decoded;
  } catch (_) {
    parts = const [];
  }
  var hasCash = false;
  var hasMomo = false;
  for (final p in parts.whereType<Map>()) {
    final m = '${p['method']}';
    if (m == 'cash') hasCash = true;
    if (m == 'mtn_momo' || m == 'orange_money' || m == 'momo') hasMomo = true;
  }
  final hasCredit = s.amountDue > 0 || parts.any((p) => p is Map && '${p['method']}' == 'credit');
  final paidCount = (hasCash ? 1 : 0) + (hasMomo ? 1 : 0) + (hasCredit ? 1 : 0);
  if (paidCount > 1) return 'mixed';
  if (hasCredit) return 'credit';
  if (hasMomo) return 'momo';
  return 'cash';
}

String _paymentLabel(String key) => switch (key) {
  'cash' => S.tr('Espèces', 'Cash'),
  'momo' => 'Mobile Money',
  'credit' => S.tr('Carnet de Dette', 'Credit Ledger'),
  _ => S.tr('Paiement Mixte', 'Mixed Payment'),
};

Color _paymentColor(String key) => switch (key) {
  'cash' => const Color(0xFF0050FF),
  'momo' => const Color(0xFF12B76A),
  'credit' => const Color(0xFFF79009),
  _ => const Color(0xFF7A5AF8),
};

String _prettyCategory(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return S.tr('Divers', 'Other');
  }
  final words = raw
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
  return words.isEmpty ? S.tr('Divers', 'Other') : words;
}

/// Icône Material par catégorie (jamais d'emoji — charte design system).
IconData _categoryIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('épicer') || n.contains('epicer') || n.contains('grocer')) {
    return Icons.shopping_cart_outlined;
  }
  if (n.contains('boiss') || n.contains('bever') || n.contains('eau')) {
    return Icons.local_drink_outlined;
  }
  if (n.contains('hygiè') || n.contains('hygien') || n.contains('clean')) {
    return Icons.cleaning_services_outlined;
  }
  if (n.contains('conserve') || n.contains('canned')) {
    return Icons.no_meals_outlined;
  }
  if (n.contains('pain') || n.contains('boulang') || n.contains('bakery')) {
    return Icons.bakery_dining_outlined;
  }
  if (n.contains('parfum') || n.contains('fragran')) {
    return Icons.local_florist_outlined;
  }
  return Icons.category_outlined;
}

/// « il y a 8 min » / « 8 min ago » — comme la maquette.
String _timeAgo(DateTime t) {
  final mins = DateTime.now().difference(t).inMinutes;
  if (mins < 1) return S.tr("à l'instant", 'just now');
  if (mins < 60) return S.tr('il y a $mins min', '$mins min ago');
  final hours = mins ~/ 60;
  if (hours < 24) return S.tr('il y a $hours h', '$hours h ago');
  return S.tr('hier', 'yesterday');
}

String _longDate(DateTime d) {
  const frWeekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
  ];
  const enWeekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  const frMonths = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];
  const enMonths = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  if (S.isEnglish) {
    return '${enWeekdays[d.weekday - 1]} ${d.day} ${enMonths[d.month - 1]} ${d.year}';
  }
  return '${frWeekdays[d.weekday - 1]} ${d.day} ${frMonths[d.month - 1]} ${d.year}';
}

// ─── Écran ────────────────────────────────────────────────────────────────────

/// Accueil recréé bloc par bloc depuis `AccueilScreen` de la maquette
/// (App.tsx L2869–3419) — audit docs/UI_AUDIT_MAQUETTE_HIG.md §3.
/// Aucune fusion avec l'ancien DashboardScreen (resté en place, déréférencé).
class DavexAccueilScreen extends ConsumerStatefulWidget {
  const DavexAccueilScreen({super.key});

  @override
  ConsumerState<DavexAccueilScreen> createState() => _DavexAccueilScreenState();
}

class _DavexAccueilScreenState extends ConsumerState<DavexAccueilScreen> {
  String _timeframe = 'weekly';
  int? _selectedPoint;
  bool _alertsOpen = true;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final async = ref.watch(_accueilProvider);
    final online = ref.watch(connectivityOnlineProvider).valueOrNull ?? false;
    final pending = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
    final transport = !online
        ? LkSyncTransport.local
        : pending > 0
        ? LkSyncTransport.wifi
        : LkSyncTransport.cloud;
    final session = ref.watch(sessionProvider);
    final business = session.business;

    return Scaffold(
      backgroundColor: p.canvas,
      body: RefreshIndicator(
        color: p.action,
        onRefresh: () async {
          ref.invalidate(_accueilProvider);
          ref.invalidate(connectivityOnlineProvider);
          ref.invalidate(pendingSyncCountProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _GreetingBar(
                shopName: business?.name ?? 'Lynkstor',
                city: business?.city,
                transport: transport,
              ),
            ),
            if (async.isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: DavexLoading(),
                ),
              )
            else if (async.hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: DavexStateView(
                    title: S.tr('Chargement impossible', 'Unable to load'),
                    message: S.tr(
                      'Tirez vers le bas pour réessayer.',
                      'Pull down to retry.',
                    ),
                    icon: Icons.error_outline,
                  ),
                ),
              )
            else if (async.valueOrNull == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: DavexStateView(
                    title: S.tr('Aucun commerce', 'No business'),
                    message: S.tr(
                      'Créez votre boutique pour commencer.',
                      'Create your shop to get started.',
                    ),
                    icon: Icons.storefront_outlined,
                    actionLabel: S.tr('Créer la boutique', 'Create shop'),
                    onAction: () => context.go('/onboarding'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                sliver: SliverList.list(
                  children: [
                    _QuickActions(data: async.valueOrNull!, session: session),
                    const SizedBox(height: 16),
                    _Kpis(data: async.valueOrNull!),
                    const SizedBox(height: 16),
                    _RevenueChart(
                      data: async.valueOrNull!,
                      timeframe: _timeframe,
                      selectedIndex: _selectedPoint,
                      onTimeframe: (t) => setState(() {
                        _timeframe = t;
                        _selectedPoint = null;
                      }),
                      onSelected: (i) => setState(() => _selectedPoint = i),
                    ),
                    const SizedBox(height: 16),
                    _PaymentDonut(data: async.valueOrNull!),
                    const SizedBox(height: 16),
                    _CategoryBars(data: async.valueOrNull!),
                    const SizedBox(height: 16),
                    _AiCard(data: async.valueOrNull!),
                    const SizedBox(height: 16),
                    _StockAlerts(
                      data: async.valueOrNull!,
                      open: _alertsOpen,
                      onToggle: () =>
                          setState(() => _alertsOpen = !_alertsOpen),
                    ),
                    const SizedBox(height: 16),
                    _RecentSales(data: async.valueOrNull!),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Bloc 1 : barre de salutation ───────────────────────────────────────────

class _GreetingBar extends ConsumerWidget {
  const _GreetingBar({
    required this.shopName,
    required this.city,
    required this.transport,
  });

  final String shopName;
  final String? city;
  final LkSyncTransport transport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LkPalette.of(context);
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.borderDecorative)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _longDate(now),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: p.textSecondary,
                  ),
                ),
              ),
              DavexSyncIndicator(transport: transport),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$shopName · ${city == null || city!.trim().isEmpty ? S.tr('Ville non renseignée', 'City not set') : city}',
            style: TextStyle(fontSize: 12, color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Bloc 2 : actions rapides ────────────────────────────────────────────────

class _QuickAction {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bg,
    required this.border,
    required this.tile,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color bg;
  final Color border;
  final Color tile;
  final Color accent;
  final VoidCallback onTap;
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.data, required this.session});

  final _AccueilData data;
  final SessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = <_QuickAction>[
      if (session.can(AppPermission.expensesView))
        _QuickAction(
          icon: Icons.trending_down,
          title: S.tr('Dépenses & OPEX', 'Expenses & OPEX'),
          subtitle: data.expensesToday > 0
              ? S.tr(
                  '${MoneyFormat.format(data.expensesToday, showCurrency: false)} F engagés',
                  '${MoneyFormat.format(data.expensesToday, showCurrency: false)} F spent',
                )
              : S.tr('Saisie & Caisse', 'Entry & Cash'),
          bg: const Color(0xFFFFF1F2),
          border: const Color(0xFFFECDD3),
          tile: const Color(0xFFE11D48),
          accent: const Color(0xFFBE123C),
          onTap: () => context.push('/expenses'),
        ),
      if (session.can(AppPermission.reportsView))
        _QuickAction(
          icon: Icons.pie_chart_outline,
          title: S.tr('Rapports & Marges', 'Reports & Margins'),
          subtitle: S.tr('Analyse du CA & PDF', 'Revenue analysis & PDF'),
          bg: const Color(0xFFEFF6FF),
          border: const Color(0xFFBFDBFE),
          tile: const Color(0xFF2563EB),
          accent: const Color(0xFF1D4ED8),
          onTap: () => context.push('/reports'),
        ),
      if (session.can(AppPermission.salesView))
        _QuickAction(
          icon: Icons.lock_outline,
          title: S.tr('Clôture Caisse (Z)', 'Cash Closure (Z)'),
          subtitle: S.tr('Comptage & Écarts', 'Counting & Variances'),
          bg: const Color(0xFFECFDF5),
          border: const Color(0xFFA7F3D0),
          tile: const Color(0xFF059669),
          accent: const Color(0xFF047857),
          onTap: () => _openCashClosure(context, ref, data),
        ),
      if (session.can(AppPermission.debtsView))
        _QuickAction(
          icon: Icons.person_add_alt,
          title: S.tr('Carnet de Dette', 'Credit Ledger'),
          subtitle: S.tr(
            '${MoneyFormat.format(data.debtOutstanding, showCurrency: false)} F dûs',
            '${MoneyFormat.format(data.debtOutstanding, showCurrency: false)} F owed',
          ),
          bg: const Color(0xFFFFFBEB),
          border: const Color(0xFFFDE68A),
          tile: const Color(0xFFD97706),
          accent: const Color(0xFFB45309),
          onTap: () => context.push('/debts'),
        ),
      if (session.can(AppPermission.customersManage))
        _QuickAction(
          icon: Icons.group_outlined,
          title: S.tr('Clients', 'Customers'),
          subtitle: S.tr('Fiches & soldes', 'Profiles & balances'),
          bg: const Color(0xFFFAF5FF),
          border: const Color(0xFFE9D5FF),
          tile: const Color(0xFF9333EA),
          accent: const Color(0xFF7E22CE),
          onTap: () => context.push('/customers'),
        ),
      if (session.can(AppPermission.salesView))
        _QuickAction(
          icon: Icons.receipt_long,
          title: S.tr('Historique ventes', 'Sales history'),
          subtitle: S.tr('Tickets & remboursements', 'Receipts & refunds'),
          bg: const Color(0xFFEEF2FF),
          border: const Color(0xFFC7D2FE),
          tile: const Color(0xFF4F46E5),
          accent: const Color(0xFF4338CA),
          onTap: () => context.push('/sales'),
        ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    // Grille 2 colonnes comme la maquette.
    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i += 2) {
      final a = actions[i];
      final b = i + 1 < actions.length ? actions[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          // IntrinsicHeight : indispensable pour des cartes jumelles de
          // hauteur égale dans un sliver (hauteur non bornée → stretch
          // direct = "BoxConstraints forces an infinite height").
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _QuickActionCard(action: a)),
                const SizedBox(width: 8),
                Expanded(
                  child: b == null
                      ? const SizedBox.shrink()
                      : _QuickActionCard(action: b),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

/// Clôture Z réelle (table `cash_closes`, `recordCashClose`) — aucune donnée
/// inventée : écart calculé depuis les encaissements espèces du jour.
Future<void> _openCashClosure(
  BuildContext context,
  WidgetRef ref,
  _AccueilData data,
) async {
  final session = ref.read(sessionProvider);
  final business = session.business;
  if (business == null) return;
  final p = LkPalette.of(context);
  final controller = TextEditingController(
    text: MoneyFormat.format(data.report.expectedCash, showCurrency: false),
  );
  final saved = await showDavexSheet<bool>(
    context,
    title: S.tr('Clôture de caisse (Z)', 'Cash closure (Z)'),
    initialChildSize: 0.5,
    builder: (context, scrollController) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            S.tr(
              'Comptez les billets et pièces en caisse, puis validez : '
              'l\'écart sera enregistré avec la recette théorique du jour.',
              'Count the cash in the drawer, then confirm: the variance '
              'will be recorded against today\'s theoretical takings.',
            ),
            style: TextStyle(fontSize: 13, color: p.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(
            S.tr(
              'Recette théorique : ${MoneyFormat.format(data.report.collected)}',
              'Theoretical takings: ${MoneyFormat.format(data.report.collected)}',
            ),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: p.text,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
            ),
            style: TextStyle(fontSize: 16, color: p.text),
            decoration: InputDecoration(
              labelText: S.tr('Montant compté', 'Counted amount'),
              suffixText: 'FCFA',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DavexButton(
            label: S.tr('Enregistrer la clôture', 'Record closure'),
            icon: Icons.lock_outline,
            onPressed: () async {
              final counted =
                  MoneyFormat.parse(controller.text) ?? 0;
              await ref.read(databaseProvider).recordCashClose(
                businessId: business.id,
                day: DateTime.now(),
                counted: counted,
                userId: session.user?.id,
              );
              if (context.mounted) Navigator.of(context).pop(true);
            },
          ),
        ],
      ),
    ),
  );
  if (saved == true && context.mounted) {
    davexNotify(
      context,
      title: S.tr('Clôture enregistrée', 'Closure recorded'),
      body: S.tr(
        'Le rapport de caisse du jour a été scellé.',
        'Today\'s cash report has been sealed.',
      ),
    );
    ref.invalidate(_accueilProvider);
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    return DavexPressable(
      onTap: action.onTap,
      semanticLabel: action.title,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: action.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: action.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: action.tile,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(action.icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    action.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: action.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bloc 3 : KPIs ───────────────────────────────────────────────────────────

class _Kpis extends StatelessWidget {
  const _Kpis({required this.data});

  final _AccueilData data;

  @override
  Widget build(BuildContext context) {
    final count = data.stock['product_count']?.toInt() ?? 0;
    final low = data.stock['low_count']?.toInt() ?? 0;
    final out = data.stock['out_count']?.toInt() ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DavexMetricCard(
            compact: true,
            label: S.tr('Total articles', 'Total items'),
            value: '$count',
            trend: S.tr('Catalogue actif', 'Active catalogue'),
            icon: Icons.inventory_2_outlined,
            tone: DavexTone.info,
            onTap: () => context.push('/stock'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DavexMetricCard(
            compact: true,
            label: S.tr('Stock faible', 'Low stock'),
            value: '$low',
            trend: S.tr('À réapprovisionner', 'To restock'),
            icon: Icons.warning_amber_rounded,
            tone: DavexTone.warning,
            onTap: () => context.push('/stock'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DavexMetricCard(
            compact: true,
            label: S.tr('Rupture critique', 'Critical stock-out'),
            value: '$out',
            trend: S.tr('Action requise', 'Action required'),
            icon: Icons.trending_down,
            tone: DavexTone.danger,
            onTap: () => context.push('/stock'),
          ),
        ),
      ],
    );
  }
}

// ─── Carte générique ─────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.borderDecorative),
        boxShadow: [p.shadowCard],
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.overline, required this.title, this.trailing});

  final String overline;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                overline,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: p.text,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ─── Bloc 4 : courbe CA ──────────────────────────────────────────────────────

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({
    required this.data,
    required this.timeframe,
    required this.selectedIndex,
    required this.onTimeframe,
    required this.onSelected,
  });

  final _AccueilData data;
  final String timeframe;
  final int? selectedIndex;
  final ValueChanged<String> onTimeframe;
  final ValueChanged<int?> onSelected;

  List<DavexChartPoint> get points => switch (timeframe) {
    'hourly' => data.hourly,
    'monthly' => data.monthly,
    _ => data.weekly,
  };

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final current = points;
    final selected = selectedIndex != null && selectedIndex! < current.length
        ? current[selectedIndex!]
        : null;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            overline: S.tr('Statistiques de vente', 'Sales statistics'),
            title: S.tr(
              "Évolution du Chiffre d'Affaires",
              'Revenue Trend',
            ),
            trailing: _TimeframePills(timeframe: timeframe, onTimeframe: onTimeframe),
          ),
          const SizedBox(height: 12),
          // Tooltip readout (maquette : bg-indigo-50/60 border-indigo-100).
          Container(
            constraints: const BoxConstraints(minHeight: 28),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x99EEF2FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E7FF)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: selected == null
                      ? Row(
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              size: 15,
                              color: p.textSecondary,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                S.tr(
                                  'Touchez un point de la courbe pour voir le détail',
                                  'Tap a point on the curve for details',
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: p.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF312E81),
                            ),
                            children: [
                              TextSpan(text: '${selected.label} : '),
                              TextSpan(
                                text:
                                    '${MoneyFormat.format(selected.amount, showCurrency: false)} FCFA',
                                style: const TextStyle(
                                  color: Color(0xFF4F46E5),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                if (selected != null)
                  Text(
                    S.tr(
                      '${selected.sales} vente${selected.sales > 1 ? 's' : ''}',
                      '${selected.sales} sale${selected.sales > 1 ? 's' : ''}',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4338CA),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (current.every((e) => e.amount == 0))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                S.tr(
                  'Aucune vente enregistrée sur cette période.',
                  'No sales recorded for this period.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            )
          else
            DavexAreaChart(
              points: current,
              selectedIndex: selectedIndex,
              onSelected: onSelected,
            ),
        ],
      ),
    );
  }
}

class _TimeframePills extends StatelessWidget {
  const _TimeframePills({required this.timeframe, required this.onTimeframe});

  final String timeframe;
  final ValueChanged<String> onTimeframe;

  @override
  Widget build(BuildContext context) {
    final keys = [
      ('hourly', S.tr('Heures', 'Hours')),
      ('weekly', S.tr('Semaine', 'Week')),
      ('monthly', S.tr('Mois', 'Month')),
    ];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (key, label) in keys)
            DavexPressable(
              onTap: () => onTimeframe(key),
              scale: 0.96,
              minTouchTarget: 32,
              semanticLabel: label,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: timeframe == key ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: timeframe == key
                      ? const [
                          BoxShadow(
                            color: Color(0x0F0F172A),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        timeframe == key ? FontWeight.w800 : FontWeight.w700,
                    color: timeframe == key
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Bloc 5 : donut modes de paiement ───────────────────────────────────────

class _PaymentDonut extends StatelessWidget {
  const _PaymentDonut({required this.data});

  final _AccueilData data;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final total = data.payments.fold<double>(0, (m, e) => m + e.amount);
    final dominant = data.payments.firstOrNull;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            overline: S.tr('Répartition Caisse', 'Cash breakdown'),
            title: S.tr('Modes de Paiement du Jour', "Today's Payment Modes"),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                MoneyFormat.format(data.report.sold),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF047857),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (total <= 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                S.tr(
                  'Aucune vente encaissée aujourd\'hui.',
                  'No payment collected today.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 130,
                  child: DavexDonutChart(
                    size: 112,
                    segments: [
                      for (final e in data.payments)
                        DavexDonutSegment(value: e.amount, color: e.color),
                    ],
                    center: dominant == null
                        ? null
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(dominant.amount / total * 100).round()}%',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                dominant.mode.split(' ').first,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      for (final e in data.payments)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: e.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  e.mode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${(e.amount / total * 100).round()}%',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    '${MoneyFormat.format(e.amount, showCurrency: false)} F',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─── Bloc 6 : ventes par catégorie ──────────────────────────────────────────

const _categoryGradients = [
  [Color(0xFF4F46E5), Color(0xFF2563EB)],
  [Color(0xFF10B981), Color(0xFF0D9488)],
  [Color(0xFF9333EA), Color(0xFF4F46E5)],
  [Color(0xFFF59E0B), Color(0xFFEA580C)],
];

class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.data});

  final _AccueilData data;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final cats = data.categories.take(4).toList();
    final total = cats.fold<double>(0, (m, e) => m + e.amount);
    final top = cats.firstOrNull;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            overline: S.tr('Analyse Catalogue', 'Catalogue analysis'),
            title: S.tr('Ventes par Catégorie', 'Sales by Category'),
            trailing: top == null
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      S.tr('Top : ${top.name}', 'Top: ${top.name}'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          if (cats.isEmpty || total <= 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                S.tr(
                  'Aucune vente aujourd\'hui pour classer par catégorie.',
                  'No sales today to rank by category.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            )
          else
            for (var i = 0; i < cats.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _categoryIcon(cats[i].name),
                          size: 17,
                          color: p.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: cats[i].name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                              children: [
                                TextSpan(
                                  text: S.tr(
                                    ' (${cats[i].itemsCount} art.)',
                                    ' (${cats[i].itemsCount} items)',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w400,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          MoneyFormat.format(cats[i].amount, showCurrency: false),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${(cats[i].amount / total * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: cats[i].amount / total,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: AlwaysStoppedAnimation(
                          _categoryGradients[
                            i % _categoryGradients.length
                          ].first,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ─── Bloc 7 : carte IA (décor fixe maquette, chiffres réels) ────────────────

class _AiCard extends StatelessWidget {
  const _AiCard({required this.data});

  final _AccueilData data;

  @override
  Widget build(BuildContext context) {
    final report = data.report;
    final margin = data.marginPct;
    final peak = data.peak;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF2E1065)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x80312E81)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0x809333EA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x4DC084FC)),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Color(0xFFD8B4FE),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.tr(
                        'ANALYSE IA DÉCISIONNELLE',
                        'DECISION AI ANALYSIS',
                      ).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Color(0xFFD8B4FE),
                      ),
                    ),
                    Text(
                      S.tr(
                        'Rentabilité & Heures de Pointe',
                        'Profitability & Peak Hours',
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x3310B981),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x4D10B981)),
                ),
                child: Text(
                  S.tr(
                    'Marge : ${margin == null ? '—' : '${(margin * 100).toStringAsFixed(1)} %'}',
                    'Margin: ${margin == null ? '—' : '${(margin * 100).toStringAsFixed(1)}%'}',
                  ),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6EE7B7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // IntrinsicHeight obligatoire : stretch d'un Row dans un sliver.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _AiTile(
                    label: S.tr(
                      'Bénéfice estimé jour',
                      'Estimated daily profit',
                    ),
                    value:
                        '+${MoneyFormat.format(report.profitEstimate, showCurrency: false)} FCFA',
                    valueColor: const Color(0xFF34D399),
                    valueSize: 16,
                    sub: S.tr(
                      'Sur ${MoneyFormat.format(report.sold, showCurrency: false)} F de CA',
                      'On ${MoneyFormat.format(report.sold, showCurrency: false)} F revenue',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AiTile(
                    label: S.tr('Pic d\'affluence caisse', 'Checkout peak'),
                    value: peak == null
                        ? S.tr('—', '—')
                        : '${peak.label}00 – _',
                    valueColor: const Color(0xFFA5B4FC),
                    valueSize: 14,
                    sub: peak == null
                        ? S.tr('Aucune vente aujourd\'hui', 'No sales today')
                        : S.tr(
                            '${peak.sales} vente${peak.sales > 1 ? 's' : ''} / heure',
                            '${peak.sales} sales / hour',
                          ),
                    peak: peak,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiTile extends StatelessWidget {
  const _AiTile({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.valueSize,
    required this.sub,
    this.peak,
  });

  final String label;
  final String value;
  final Color valueColor;
  final double valueSize;
  final String sub;
  final DavexChartPoint? peak;

  @override
  Widget build(BuildContext context) {
    // Valeur du pic : « 18h00 – 19h00 » recalculée depuis libellé « 18h ».
    var display = value;
    if (peak != null) {
      final hour = int.tryParse(
        peak!.label.replaceAll('h', ''),
      );
      if (hour != null) {
        display = '${hour}h00 – ${hour + 1}h00';
      } else {
        display = peak!.label;
      }
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Color(0xFFCBD5E1),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: valueSize,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bloc 8 : alertes stock ─────────────────────────────────────────────────

class _StockAlerts extends StatelessWidget {
  const _StockAlerts({
    required this.data,
    required this.open,
    required this.onToggle,
  });

  final _AccueilData data;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final alerts = data.alertProducts;
    final hasCritical = alerts.any((e) => e.stockQty <= 0);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.borderDecorative),
        boxShadow: [p.shadowCard],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          DavexPressable(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: open ? p.borderDecorative : Colors.transparent,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      size: 13,
                      color: Color(0xFFF79009),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.tr('Alertes de stock', 'Stock alerts'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                  ),
                  if (alerts.isNotEmpty)
                    DavexStatusBadge.text(
                      '${alerts.length}',
                      tone: hasCritical ? DavexTone.danger : DavexTone.warning,
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: const Color(0xFF98A2B3),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            if (alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    S.tr(
                      'Aucune alerte de stock active.',
                      'No active stock alerts.',
                    ),
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  ),
                ),
              )
            else
              for (final alert in alerts)
                DavexPressable(
                  onTap: () => context.push('/stock'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 3),
                          decoration: BoxDecoration(
                            color: alert.stockQty <= 0
                                ? const Color(0xFFFF3B4D)
                                : const Color(0xFFFF9800),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alert.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: p.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                alert.stockQty <= 0
                                    ? S.tr(
                                        'Stock critique : ${_qty(alert.stockQty)} unité${alert.stockQty > 1 ? 's' : ''} restante${alert.stockQty > 1 ? 's' : ''}',
                                        'Critical stock: ${_qty(alert.stockQty)} left',
                                      )
                                    : S.tr(
                                        'Stock faible : ${_qty(alert.stockQty)} unité${alert.stockQty > 1 ? 's' : ''} — prévoir le réassort',
                                        'Low stock: ${_qty(alert.stockQty)} — plan a restock',
                                      ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 15,
                          color: Color(0xFFD0D5DD),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);
}

// ─── Bloc 9 : ventes récentes ───────────────────────────────────────────────

class _RecentSales extends StatelessWidget {
  const _RecentSales({required this.data});

  final _AccueilData data;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final sales = data.salesToday.take(5).toList();
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.borderDecorative),
        boxShadow: [p.shadowCard],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    S.tr('Ventes récentes', 'Recent sales'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                ),
                DavexPressable(
                  onTap: () => context.push('/sales'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: Text(
                      S.tr('Voir tout', 'View all'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF0050FF),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.borderDecorative),
          if (sales.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  S.tr(
                    'Aucune vente aujourd\'hui — lancez la caisse.',
                    'No sales today — open the register.',
                  ),
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
              ),
            )
          else
            for (var i = 0; i < sales.length; i++) ...[
              if (i > 0) Divider(height: 1, color: p.borderDecorative.withValues(alpha: 0.5)),
              DavexPressable(
                onTap: () => context.push('/sales'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.shopping_bag_outlined,
                          size: 16,
                          color: Color(0xFF0050FF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    sales[i].reference,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF4B5563),
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    '·',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFFD1D5DB),
                                    ),
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    _paymentLabel(
                                      _classifyPayment(sales[i]),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data.itemsBySale[sales[i].id] ??
                              sales[i].customerName ??
                              '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: p.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _timeAgo(sales[i].soldAt),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text.rich(
                        TextSpan(
                          text: MoneyFormat.format(
                            sales[i].total,
                            showCurrency: false,
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                          children: const [
                            TextSpan(
                              text: ' FCFA',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}
