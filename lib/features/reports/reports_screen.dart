import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_blocks.dart';
import '../../design_system/components/kumba_pressable.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/motion/lynk_avatar.dart';
import '../../features/ai_assistant/lynk_quick_sheet.dart';
import '../../l10n/app_strings.dart';
import '../../shared/services/report_service.dart';

final _reportProvider =
    FutureProvider.autoDispose<
      ({DailyReport daily, Map<String, double> stock})
    >((ref) async {
      final business = ref.watch(sessionProvider).business!;
      final reports = ref.watch(reportServiceProvider);
      final daily = await reports.daily(business.id);
      final stock = await reports.stockValue(business.id);
      return (daily: daily, stock: stock);
    });

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_reportProvider);
    final bottom = 28.0;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: async.when(
        loading: () => const KumbaLoading(message: 'Calcul des rapports…'),
        error: (e, _) => KumbaErrorState(message: e.toString()),
        data: (data) {
          final r = data.daily;
          final s = data.stock;
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
            children: [
              _ReportsHero(
                onAskLynk: () {
                  ref.read(pendingAiPromptProvider.notifier).state = S.tr(
                    'Résume mes ventes du jour',
                    'Summarize today’s sales',
                  );
                  showLynkQuickSheet(context);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: KumbaTintKpi(
                      label: S.tr('Ventes', 'Sales'),
                      value: MoneyFormat.formatCompact(r.sold),
                      caption:
                          '${r.salesCount} vente${r.salesCount > 1 ? 's' : ''}',
                      bg: AppColors.kpiSalesBg,
                      accent: AppColors.kpiSales,
                      icon: PhosphorIconsFill.chartLineUp,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KumbaTintKpi(
                      label: S.tr('Encaissé', 'Collected'),
                      value: MoneyFormat.formatCompact(r.collected),
                      caption: S.tr('du jour', 'today'),
                      bg: AppColors.kpiCollectBg,
                      accent: AppColors.kpiCollect,
                      icon: PhosphorIconsFill.coins,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: KumbaTintKpi(
                      label: S.tr('Dettes', 'Debts'),
                      value: MoneyFormat.formatCompact(r.credit),
                      caption: S.tr('à recouvrer', 'to collect'),
                      bg: AppColors.kpiDebtBg,
                      accent: AppColors.kpiDebt,
                      icon: PhosphorIconsFill.users,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KumbaTintKpi(
                      label: S.tr('Dépenses', 'Expenses'),
                      value: MoneyFormat.formatCompact(r.expenses),
                      caption: S.tr('du jour', 'today'),
                      bg: AppColors.kpiDepositBg,
                      accent: AppColors.kpiDeposit,
                      icon: PhosphorIconsFill.receipt,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _WhitePanel(
                title: S.tr('Répartition du jour', 'Today’s split'),
                child: SizedBox(
                  height: 188,
                  child: r.sold == 0 && r.expenses == 0
                      ? Center(
                          child: Text(
                            S.tr(
                              'Pas encore de données aujourd’hui',
                              'No data yet today',
                            ),
                            style: const TextStyle(color: AppColors.inkMuted),
                          ),
                        )
                      : BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: _maxY([
                              r.sold,
                              r.collected,
                              r.credit,
                              r.expenses,
                            ]),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, _) {
                                    const labels = [
                                      'Vendu',
                                      'Encaissé',
                                      'Crédit',
                                      'Dépenses',
                                    ];
                                    final i = v.toInt();
                                    if (i < 0 || i >= labels.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        labels[i],
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.inkMuted,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            gridData: const FlGridData(show: false),
                            barGroups: [
                              _bar(0, r.sold, AppColors.kpiSales),
                              _bar(1, r.collected, AppColors.kpiCollect),
                              _bar(2, r.credit, AppColors.kpiDebt),
                              _bar(3, r.expenses, AppColors.kpiDeposit),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              _WhitePanel(
                title: S.tr('Synthèse', 'Summary'),
                child: Column(
                  children: [
                    _row(
                      S.tr('Nombre de ventes', 'Sales count'),
                      '${r.salesCount}',
                    ),
                    _row(
                      S.tr('Bénéfice estimé', 'Estimated profit'),
                      MoneyFormat.format(r.profitEstimate),
                    ),
                    _row(
                      S.tr('Argent attendu', 'Expected cash'),
                      MoneyFormat.format(r.expectedCash),
                    ),
                    if (r.topProduct != null)
                      _row(
                        S.tr('Meilleur produit', 'Top product'),
                        r.topProduct!,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _WhitePanel(
                title: S.tr('Stock', 'Stock'),
                child: Column(
                  children: [
                    _row(
                      S.tr('Valeur au coût', 'Cost value'),
                      MoneyFormat.format(s['cost_value'] ?? 0),
                    ),
                    _row(
                      S.tr('Valeur au prix de vente', 'Sale value'),
                      MoneyFormat.format(s['sale_value'] ?? 0),
                    ),
                    _row(
                      S.tr('Produits en alerte', 'Low-stock items'),
                      '${(s['low_count'] ?? 0).toInt()}',
                    ),
                    _row(
                      S.tr('Ruptures', 'Out of stock'),
                      '${(s['out_count'] ?? 0).toInt()}',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static double _maxY(List<double> values) {
    final m = values.fold<double>(0, (a, b) => a > b ? a : b);
    if (m <= 0) return 1;
    return m * 1.2;
  }

  BarChartGroupData _bar(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y <= 0 ? 0 : y,
          color: color,
          width: 18,
          borderRadius: BorderRadius.circular(8),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: 1,
            color: color.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 14),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsHero extends StatelessWidget {
  const _ReportsHero({required this.onAskLynk});

  final VoidCallback onAskLynk;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.lynkViolet,
        borderRadius: BorderRadius.circular(26),
        boxShadow: AppColors.tintedShadow(AppColors.lynkViolet, opacity: 0.22),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.tr('Rapports', 'Reports'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  S.tr(
                    'Chiffres du jour, calculés sur cet appareil.',
                    'Today’s figures, calculated on this device.',
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                KumbaPressable(
                  onTap: onAskLynk,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      children: [
                        const LynkAvatar(
                          size: 32,
                          mood: LynkMood.greeting,
                          enabled: false,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            S.tr(
                              'Demander un résumé à Lynk',
                              'Ask Lynk for a summary',
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          PhosphorIconsBold.arrowRight,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
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

class _WhitePanel extends StatelessWidget {
  const _WhitePanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.dock.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.dock.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
