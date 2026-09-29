import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/permissions/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../shared/services/sale_service.dart';
import '../../l10n/app_strings.dart';
import '../products/barcode_scanner_screen.dart';

class _ScannerRoute extends StatelessWidget {
  const _ScannerRoute();
  @override
  Widget build(BuildContext context) => const BarcodeScannerScreen();
}

class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({super.key, this.embedded = false});

  /// Quand true, l'ecran est affiche dans le shell (onglet Vente) : on masque
  /// son chrome propre (_posHeader) pour eviter un double entete.
  final bool embedded;

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final _searchCtrl = TextEditingController();
  final List<CartLine> _cart = [];
  List<Product> _products = [];
  List<Customer> _customers = [];
  Customer? _customer;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String _query = '';
  final double _discount = 0;

  // Payment
  String _payMethod = 'cash';
  final _payAmountCtrl = TextEditingController();
  final _momoRefCtrl = TextEditingController();
  bool _showPayment = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _payAmountCtrl.dispose();
    _momoRefCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Réinitialise l'état d'erreur au début de chaque tentative.
    if (mounted) setState(() { _loading = true; _error = null; });
    final business = ref.read(sessionProvider).business;
    if (business == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final products =
          await ref.read(productServiceProvider).list(business.id);
      final customers =
          await ref.read(customerServiceProvider).list(business.id);
      // Vérifier mounted après chaque await : l'écran peut être détruit pendant
      // le chargement (retour arrière), ce qui provoquerait une mise à jour sur
      // un State supprimé et un crash potentiel.
      if (!mounted) return;
      setState(() {
        _products = products.where((p) => p.isActive).toList();
        _customers = customers;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Message d'erreur lisible — le panier (_cart) est intentionnellement
        // conservé pour que l'utilisateur ne perde pas ce qu'il avait déjà saisi.
        _error = 'Impossible de charger le catalogue. Vérifiez votre stockage '
            'et réessayez.';
      });
    }
  }

  double get _subtotal => _cart.fold(0, (s, l) => s + l.lineTotal);
  double get _total => (_subtotal - _discount).clamp(0, double.infinity);

  List<Product> get _filtered {
    if (_query.isEmpty) {
      final fav = _products.where((p) => p.isFavorite).toList();
      if (fav.isNotEmpty) {
        return [...fav, ..._products.where((p) => !p.isFavorite)];
      }
      return _products;
    }
    final q = _query.toLowerCase();
    return _products
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              (p.barcode?.contains(_query) ?? false) ||
              (p.sku?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  void _addProduct(Product p) {
    HapticFeedback.selectionClick();
    final idx = _cart.indexWhere((l) => l.productId == p.id);
    if (idx >= 0) {
      setState(() => _cart[idx].quantity += 1);
    } else {
      setState(() {
        _cart.add(
          CartLine(
            productId: p.id,
            productName: p.name,
            unitPrice: p.salePrice,
            quantity: 1,
            unit: p.unit,
            costPrice: p.costPrice,
            trackStock: p.trackStock && !p.isService,
            availableStock: p.stockQty,
          ),
        );
      });
    }
  }

  Future<void> _addAdHocLine() async {
    final name = TextEditingController(text: _query.trim());
    final price = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final unit = TextEditingController(text: S.tr('pièce', 'piece'));
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.tr('Article non répertorié', 'Unlisted item'),
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              S.tr(
                'Vendez-le maintenant, puis complétez sa fiche stock après la vente.',
                'Sell it now, then complete its stock record after the sale.',
              ),
            ),
            const SizedBox(height: 16),
            KumbaTextField(
              controller: name,
              label: S.tr('Nom ou description', 'Name or description'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            KumbaAmountField(
              controller: price,
              label: S.tr('Prix unitaire', 'Unit price'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: KumbaTextField(
                    controller: quantity,
                    label: S.tr('Quantité', 'Quantity'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: KumbaTextField(
                    controller: unit,
                    label: S.tr('Unité', 'Unit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            KumbaButton(
              label: S.tr('Ajouter au panier', 'Add to cart'),
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true &&
        name.text.trim().isNotEmpty &&
        (MoneyFormat.parse(price.text) ?? -1) >= 0 &&
        (MoneyFormat.parse(quantity.text) ?? 0) > 0) {
      setState(() {
        _cart.add(
          CartLine(
            productId: null,
            productName: name.text.trim(),
            unitPrice: MoneyFormat.parse(price.text) ?? 0,
            quantity: MoneyFormat.parse(quantity.text) ?? 1,
            unit: unit.text.trim().isEmpty
                ? S.tr('pièce', 'piece')
                : unit.text.trim(),
            trackStock: false,
          ),
        );
        _query = '';
        _searchCtrl.clear();
      });
    }
    name.dispose();
    price.dispose();
    quantity.dispose();
    unit.dispose();
  }

  Future<void> _complete() async {
    final session = ref.read(sessionProvider);
    final business = session.business;
    if (business == null) return;

    // Blocage abonnement expiré / suspendu (validé cloud Supabase)
    if (!session.canSell) {
      final sub = session.subscription;
      setState(() {
        _error =
            'Abonnement ${sub.statusLabel.toLowerCase()} (forfait ${sub.planName}). '
            'Contactez votre agent commercial Lynkstor pour renouveler.';
        _submitting = false;
      });
      HapticFeedback.heavyImpact();
      return;
    }

    final paidText = _payAmountCtrl.text;
    final paid =
        MoneyFormat.parse(paidText.isEmpty ? '$_total' : paidText) ?? _total;

    List<PaymentPart> payments;
    if (_payMethod == 'credit') {
      payments = [PaymentPart(method: 'credit', amount: 0)];
    } else if (_payMethod == 'mixed') {
      payments = [
        PaymentPart(method: 'cash', amount: paid),
        if (paid < _total) PaymentPart(method: 'credit', amount: 0),
      ];
    } else {
      payments = [
        PaymentPart(
          method: _payMethod,
          amount: paid,
          methodRef: _momoRefCtrl.text.isEmpty ? null : _momoRefCtrl.text,
        ),
      ];
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final adHocLines = _cart
          .where((line) => line.productId == null)
          .toList(growable: false);
      final sale = await ref
          .read(saleServiceProvider)
          .completeSale(
            CompleteSaleInput(
              businessId: business.id,
              lines: List.from(_cart),
              payments: payments,
              customerId: _customer?.id,
              customerName: _customer?.name,
              discount: _discount,
              userId: session.user?.id,
              userRole: session.role,
            ),
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (adHocLines.isNotEmpty && session.can(AppPermission.productsManage)) {
        final configure = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(S.tr('Ajouter au catalogue ?', 'Add to the catalog?')),
            content: Text(
              S.tr(
                '${adHocLines.first.productName} a été vendu. '
                    'Vous pouvez maintenant ajouter sa photo, son stock et son fournisseur.',
                '${adHocLines.first.productName} was sold. '
                    'You can now add its photo, stock and supplier.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(S.tr('Plus tard', 'Later')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(S.tr('Configurer', 'Configure')),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (configure == true) {
          final line = adHocLines.first;
          final uri = Uri(
            path: '/products/new',
            queryParameters: {
              'name': line.productName,
              'price': '${line.unitPrice}',
              'unit': line.unit,
              'saleId': sale.id,
            },
          );
          context.pushReplacement(uri.toString());
          return;
        }
      }
      context.pushReplacement('/sale/receipt/${sale.id}');
    } on AppException catch (e) {
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final performanceMode = ref.watch(
      sessionProvider.select((s) => s.performanceMode),
    );
    final canSell = ref.watch(sessionProvider.select((s) => s.canSell));
    final reduce =
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
        performanceMode;
    final dark = AppColors.isDark(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : AppColors.pageBg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        top: !widget.embedded,
        bottom: false,
        child: _loading
            ? const KumbaLoading(message: 'Chargement du catalogue…')
            : (_error != null && _products.isEmpty)
                // Erreur initiale (catalogue vide) : proposer une nouvelle tentative
                // sans perdre le panier déjà constitué.
                ? KumbaErrorState(
                    message: _error!,
                    onRetry: _load,
                  )
                : Column(
                children: [
                  if (!widget.embedded) _posHeader(dark, scheme),
                  Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                        child: _searchBar(dark),
                      )
                      .animate(target: reduce ? 0 : 1)
                      .fadeIn(duration: 280.ms)
                      .slideY(begin: -0.04, end: 0),
                  if (_customer != null) _customerChip(dark),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: AppMotion.normal,
                      switchInCurve: AppMotion.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: _showPayment
                          ? KeyedSubtree(
                              key: const ValueKey('pay'),
                              child: _paymentPanel(reduce, dark),
                            )
                          : KeyedSubtree(
                              key: const ValueKey('grid'),
                              child: _productGrid(reduce, dark),
                            ),
                    ),
                  ),
                  _cartBar(reduce, canSell, dark),
                ],
              ),
      ),
    );
  }

  Widget _posHeader(bool dark, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
            icon: Icon(Icons.close_rounded, color: scheme.onSurface),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.tr('Caisse', 'Checkout'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  S.tr('Nouvelle vente', 'New sale'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          _posIconBtn(
            icon: Icons.inventory_2_outlined,
            tooltip: S.tr('Produits du secteur', 'Sector products'),
            dark: dark,
            onTap: () async {
              await context.push('/products/catalog');
              if (!mounted) return;
              await _load();
            },
          ),
          _posIconBtn(
            icon: Icons.add_box_outlined,
            tooltip: S.tr('Article libre', 'Unlisted item'),
            onTap: _addAdHocLine,
            dark: dark,
          ),
          _posIconBtn(
            icon: Icons.qr_code_scanner_rounded,
            tooltip: S.tr('Scanner', 'Scan'),
            dark: dark,
            onTap: () async {
              final code = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const _ScannerRoute()),
              );
              if (code == null || !mounted) return;
              final business = ref.read(sessionProvider).business;
              if (business == null) return;
              final byCode = await ref
                  .read(productServiceProvider)
                  .byBarcode(business.id, code);
              if (!mounted) return;
              if (byCode != null) {
                _addProduct(byCode);
              } else {
                showLkToast(
                  context,
                  S.tr(
                    'Aucun produit pour le code $code',
                    'No product found for code $code',
                  ),
                  tone: LkToastTone.warning,
                  icon: Icons.barcode_reader,
                );
              }
            },
          ),
          if (_cart.isNotEmpty)
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _cart.clear();
                  _showPayment = false;
                });
              },
              child: Text(
                S.tr('Vider', 'Clear'),
                style: TextStyle(color: AppColors.rose.withValues(alpha: 0.95)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchBar(bool dark) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.primary.withValues(alpha: 0.12),
        ),
        boxShadow: AppColors.cardShadow(opacity: 0.05, dark: dark),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: S.tr(
            'Rechercher ou scanner un code…',
            'Search or scan a code…',
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
        ),
        onSubmitted: (v) async {
          final business = ref.read(sessionProvider).business;
          if (business == null) return;
          final byCode = await ref
              .read(productServiceProvider)
              .byBarcode(business.id, v.trim());
          if (byCode != null) {
            _addProduct(byCode);
            _searchCtrl.clear();
            setState(() => _query = '');
          }
        },
      ),
    );
  }

  Widget _customerChip(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: KumbaCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: AppColors.turquoiseSoft.withValues(alpha: dark ? 0.18 : 0.55),
        borderColor: AppColors.turquoise.withValues(alpha: 0.28),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.turquoise.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: const Icon(
                Icons.person_outline,
                size: 18,
                color: AppColors.turquoiseDeep,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _customer!.name,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _customer = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posIconBtn({
    required IconData icon,
    required VoidCallback onTap,
    required bool dark,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: AppColors.card(context).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _productGrid(bool reduce, bool dark) {
    final list = _filtered;
    if (list.isEmpty) {
      return KumbaEmptyState(
        title: _query.isEmpty ? 'Aucun produit' : 'Aucun résultat',
        subtitle: _query.isEmpty
            ? S.tr(
                'Activez des produits de votre secteur pour commencer à vendre.',
                'Activate products from your sector to start selling.',
              )
            : null,
        actionLabel: _query.isEmpty
            ? S.tr('Produits du secteur', 'Sector products')
            : null,
        onAction: _query.isEmpty
            ? () async {
                await context.push('/products/catalog');
                if (!mounted) return;
                await _load();
              }
            : null,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.92,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final p = list[i];
        final low = p.trackStock && p.stockQty <= p.lowStockThreshold;
        final inCart = _cart.any((l) => l.productId == p.id);
        final qty = inCart
            ? _cart.firstWhere((l) => l.productId == p.id).quantity
            : 0.0;
        final initial = p.name.isNotEmpty
            ? p.name.substring(0, 1).toUpperCase()
            : '?';

        final block = inCart
            ? AppColors.primary
            : AppColors.catalogBlock(p.name.hashCode);
        final fg = inCart ? Colors.white : AppColors.secondary;
        final card = KumbaCard(
          onTap: () => _addProduct(p),
          padding: const EdgeInsets.all(14),
          color: block,
          borderColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: inCart ? 0.16 : 0.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (p.isFavorite)
                    Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: inCart ? Colors.white : AppColors.primary,
                    ),
                  if (inCart) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusCapsule,
                        ),
                      ),
                      child: Text(
                        '×${qty.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: fg,
                  ),
                ),
              ),
              Text(
                MoneyFormat.format(p.salePrice),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (p.trackStock) ...[
                const SizedBox(height: 2),
                Text(
                  low
                      ? 'Stock ${p.stockQty.toStringAsFixed(0)}'
                      : '${p.stockQty.toStringAsFixed(0)} ${p.unit}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: low
                        ? (inCart ? Colors.white : AppColors.warning)
                        : fg.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ],
          ),
        );

        if (reduce) return card;
        return card
            .animate()
            .fadeIn(delay: (20 * (i % 8)).ms, duration: 260.ms)
            .scale(
              begin: const Offset(0.96, 0.96),
              end: const Offset(1, 1),
              delay: (20 * (i % 8)).ms,
              duration: 280.ms,
              curve: Curves.easeOutCubic,
            );
      },
    );
  }

  Widget _paymentPanel(bool reduce, bool dark) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.fab,
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryContainer.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.tr('Total à encaisser', 'Amount due'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    MoneyFormat.format(_total),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_cart.fold<double>(0, (s, l) => s + l.quantity).toStringAsFixed(0)} article(s)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            )
            .animate(target: reduce ? 0 : 1)
            .fadeIn(duration: 300.ms)
            .scale(begin: const Offset(0.97, 0.97), end: const Offset(1, 1)),
        const SizedBox(height: 18),
        Text(
          S.tr('Mode de paiement', 'Payment method'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _methodChip('cash', 'Espèces', Icons.payments_outlined, dark),
            _methodChip(
              'mtn_momo',
              'MTN · bientôt',
              Icons.phone_android,
              dark,
              enabled: false,
            ),
            _methodChip(
              'orange_money',
              'Orange · bientôt',
              Icons.phone_iphone,
              dark,
              enabled: false,
            ),
            _methodChip('credit', 'Crédit', Icons.handshake_outlined, dark),
            _methodChip('mixed', 'Partiel', Icons.call_split, dark),
            _methodChip(
              'transfer',
              'Virement',
              Icons.account_balance_outlined,
              dark,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_payMethod != 'credit') ...[
          KumbaAmountField(
            controller: _payAmountCtrl,
            label: 'Montant reçu',
            autofocus: true,
          ),
          const SizedBox(height: 8),
          if (_payMethod == 'mtn_momo' || _payMethod == 'orange_money') ...[
            KumbaTextField(
              controller: _momoRefCtrl,
              label: 'Référence Mobile Money',
              hint: 'Saisie manuelle - pas de push USSD opérateur',
            ),
            const SizedBox(height: 6),
            Text(
              'Le client paie sur son téléphone ; vous notez ici la référence reçue.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
        if (_payMethod == 'credit' || _payMethod == 'mixed') ...[
          const SizedBox(height: 12),
          Text(
            'Client (obligatoire pour le crédit)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          ..._customers
              .take(8)
              .map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: KumbaCard(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _customer = c);
                    },
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    borderColor: _customer?.id == c.id
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : null,
                    color: _customer?.id == c.id
                        ? AppColors.primary.withValues(
                            alpha: dark ? 0.16 : 0.08,
                          )
                        : null,
                    child: Row(
                      children: [
                        Icon(
                          _customer?.id == c.id
                              ? Icons.check_circle_rounded
                              : Icons.person_outline,
                          color: _customer?.id == c.id
                              ? AppColors.primary
                              : AppColors.outline,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if ((c.phone ?? c.neighborhood) != null)
                                Text(
                                  c.phone ?? c.neighborhood ?? '',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        Text(
                          MoneyFormat.format(c.balance),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.errorSoft.withValues(alpha: dark ? 0.2 : 1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
            ),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 20),
        KumbaButton(
          label: 'Valider la vente',
          isLoading: _submitting,
          icon: Icons.check_circle_outline,
          onPressed: _submitting ? null : _complete,
        ),
        const SizedBox(height: 8),
        KumbaButton(
          label: 'Retour au panier',
          variant: KumbaButtonVariant.ghost,
          onPressed: () => setState(() => _showPayment = false),
        ),
      ],
    );
  }

  Widget _methodChip(
    String id,
    String label,
    IconData icon,
    bool dark, {
    bool enabled = true,
  }) {
    final selected = _payMethod == id;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                setState(() {
                  _payMethod = id;
                  if (_payAmountCtrl.text.isEmpty) {
                    _payAmountCtrl.text = _total.toStringAsFixed(0);
                  }
                });
              }
            : () {
                showLkToast(
                  context,
                  S.tr(
                    'Mobile Money sera disponible dans une prochaine version.',
                    'Mobile Money will be available in a future version.',
                  ),
                  tone: LkToastTone.info,
                  icon: Icons.smartphone,
                );
              },
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: dark ? 0.22 : 0.12)
                : AppColors.card(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : (dark
                        ? Colors.white.withValues(alpha: 0.08)
                        : AppColors.primary.withValues(alpha: 0.10)),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? AppColors.primary : scheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartBar(bool reduce, bool canSell, bool dark) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final bar = Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
        boxShadow: AppColors.tintedShadow(AppColors.fab, opacity: 0.22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_cart.isNotEmpty && !_showPayment)
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _cart.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final l = _cart[i];
                  return Material(
                    color: AppColors.primary.withValues(
                      alpha: dark ? 0.18 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (l.quantity > 1) {
                            l.quantity -= 1;
                          } else {
                            _cart.removeAt(i);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${l.productName} ×${l.quantity.toStringAsFixed(0)}',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.remove_circle_outline,
                              size: 16,
                              color: AppColors.primary.withValues(alpha: 0.7),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_cart.isNotEmpty && !_showPayment) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_cart.fold<double>(0, (s, l) => s + l.quantity).toStringAsFixed(0)} article(s)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    AnimatedSwitcher(
                      duration: AppMotion.fast,
                      child: Text(
                        MoneyFormat.format(_total),
                        key: ValueKey(_total),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_showPayment)
                SizedBox(
                  width: 168,
                  child: KumbaButton(
                    label: canSell ? 'Encaisser' : 'Bloqué',
                    icon: canSell
                        ? Icons.payments_outlined
                        : Icons.lock_outline,
                    onPressed: _cart.isEmpty || !canSell
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            _payAmountCtrl.text = _total.toStringAsFixed(0);
                            setState(() => _showPayment = true);
                          },
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom > 0 ? bottom + 6 : 12),
      child: reduce
          ? bar
          : bar
                .animate()
                .fadeIn(duration: 320.ms)
                .slideY(
                  begin: 0.12,
                  end: 0,
                  duration: 360.ms,
                  curve: Curves.easeOutCubic,
                ),
    );
  }
}
