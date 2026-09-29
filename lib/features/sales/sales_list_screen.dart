import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_ios.dart';
import '../../design_system/components/kumba_states.dart';
import '../../l10n/app_strings.dart';

final _salesProvider = FutureProvider.autoDispose<List<Sale>>((ref) async {
  final business = ref.watch(sessionProvider.select((s) => s.business));
  if (business == null) return [];
  return ref.watch(saleServiceProvider).list(business.id);
});

final _returnsProvider = FutureProvider.autoDispose<List<SaleReturn>>((ref) async {
  final business = ref.watch(sessionProvider.select((s) => s.business));
  if (business == null) return [];
  return ref.watch(saleServiceProvider).listReturns(business.id);
});

/// Historique ventes et retours — large title iOS + liste inset + onglets.
class SalesListScreen extends ConsumerStatefulWidget {
  const SalesListScreen({super.key});

  @override
  ConsumerState<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends ConsumerState<SalesListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.tr('Historique', 'History'),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          S.tr('Ventes & Avoirs', 'Sales & Returns'),
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                  KumbaChromeButton(
                    icon: Icons.add_rounded,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.go('/vente');
                    },
                    tooltip: S.tr('Nouvelle vente', 'New sale'),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.onSurfaceVariant,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Ventes'),
                Tab(text: 'Avoirs'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _SalesTab(),
                  _ReturnsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_salesProvider);
    final perf = ref.watch(sessionProvider.select((s) => s.performanceMode));
    final reduce = (MediaQuery.maybeOf(context)?.disableAnimations ?? false) || perf;
    
    return async.when(
      loading: () => const KumbaSkeletonList(),
      error: (e, _) => KumbaErrorState(
        message: e.toString(),
        onRetry: () => ref.invalidate(_salesProvider),
      ),
      data: (sales) {
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(_salesProvider),
          child: sales.isEmpty
              ? CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      child: KumbaEmptyState(
                        title: 'Aucune vente pour l’instant',
                        subtitle: 'Lancez votre première vente depuis le bouton central.',
                        icon: Icons.point_of_sale_outlined,
                        actionLabel: 'Nouvelle vente',
                        onAction: () => context.go('/vente'),
                      ),
                    ),
                  ],
                )
              : CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  slivers: _groupSales(context, sales, reduce, 28.0),
                ),
        );
      },
    );
  }

  List<Widget> _groupSales(BuildContext context, List<Sale> sales, bool reduce, double bottom) {
    final now = DateTime.now();
    final today = <Sale>[];
    final earlier = <Sale>[];
    for (final s in sales) {
      final d = s.soldAt;
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        today.add(s);
      } else {
        earlier.add(s);
      }
    }

    final slivers = <Widget>[];
    void addGroup(String header, List<Sale> list) {
      if (list.isEmpty) return;
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: KumbaInsetGroup(
              header: header,
              children: [
                for (var i = 0; i < list.length; i++)
                  _saleRow(context, list[i], i, reduce),
              ],
            ),
          ),
        ),
      );
    }

    addGroup(S.tr("Aujourd'hui", 'Today'), today);
    addGroup(S.tr('Précédentes', 'Earlier'), earlier);
    slivers.add(SliverToBoxAdapter(child: SizedBox(height: bottom)));
    return slivers;
  }

  Widget _saleRow(BuildContext context, Sale s, int i, bool reduce) {
    final due = s.amountDue > 0;
    final row = KumbaInsetRow(
      icon: due ? Icons.schedule_rounded : Icons.check_circle_rounded,
      iconColor: due ? AppColors.kpiDebt : AppColors.kpiSales,
      title: s.reference,
      subtitle: '${DateFormat('dd/MM HH:mm').format(s.soldAt)}'
          '${s.customerName != null ? ' · ${s.customerName}' : ''}',
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            MoneyFormat.format(s.total),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            due ? 'Dû ${MoneyFormat.format(s.amountDue)}' : (s.status == 'completed' ? 'Payé' : s.status),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: due ? AppColors.kpiDebt : AppColors.kpiSales,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/sale/receipt/${s.id}');
      },
    );

    if (reduce) return row;
    return row.animate().fadeIn(delay: (24 * (i % 10)).ms, duration: 240.ms).slideX(begin: 0.02, end: 0, delay: (24 * (i % 10)).ms);
  }
}

class _ReturnsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_returnsProvider);
    final perf = ref.watch(sessionProvider.select((s) => s.performanceMode));
    final reduce = (MediaQuery.maybeOf(context)?.disableAnimations ?? false) || perf;
    
    return async.when(
      loading: () => const KumbaSkeletonList(),
      error: (e, _) => KumbaErrorState(
        message: e.toString(),
        onRetry: () => ref.invalidate(_returnsProvider),
      ),
      data: (returns) {
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(_returnsProvider),
          child: returns.isEmpty
              ? CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      child: KumbaEmptyState(
                        title: 'Aucun avoir/retour',
                        subtitle: 'Les retours enregistrés apparaîtront ici.',
                        icon: Icons.undo_rounded,
                      ),
                    ),
                  ],
                )
              : CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  slivers: _groupReturns(context, returns, reduce, 28.0),
                ),
        );
      },
    );
  }

  List<Widget> _groupReturns(BuildContext context, List<SaleReturn> returns, bool reduce, double bottom) {
    final now = DateTime.now();
    final today = <SaleReturn>[];
    final earlier = <SaleReturn>[];
    for (final r in returns) {
      final d = r.createdAt;
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        today.add(r);
      } else {
        earlier.add(r);
      }
    }

    final slivers = <Widget>[];
    void addGroup(String header, List<SaleReturn> list) {
      if (list.isEmpty) return;
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: KumbaInsetGroup(
              header: header,
              children: [
                for (var i = 0; i < list.length; i++)
                  _returnRow(context, list[i], i, reduce),
              ],
            ),
          ),
        ),
      );
    }

    addGroup(S.tr("Aujourd'hui", 'Today'), today);
    addGroup(S.tr('Précédents', 'Earlier'), earlier);
    slivers.add(SliverToBoxAdapter(child: SizedBox(height: bottom)));
    return slivers;
  }

  Widget _returnRow(BuildContext context, SaleReturn r, int i, bool reduce) {
    final row = KumbaInsetRow(
      icon: Icons.undo_rounded,
      iconColor: AppColors.kpiDebt,
      title: r.reference,
      subtitle: '${DateFormat('dd/MM HH:mm').format(r.createdAt)} · ${r.refundMethod == 'refund' ? 'Remboursement' : 'Avoir'}',
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            MoneyFormat.format(r.total),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/sale/return/receipt/${r.id}');
      },
    );

    if (reduce) return row;
    return row.animate().fadeIn(delay: (24 * (i % 10)).ms, duration: 240.ms).slideX(begin: 0.02, end: 0, delay: (24 * (i % 10)).ms);
  }
}
