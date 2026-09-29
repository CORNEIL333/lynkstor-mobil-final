import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_ios.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/lynk_context_bubble.dart';
import '../ai_assistant/lynk_quick_sheet.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../l10n/app_strings.dart';

final _stockProvider = FutureProvider.autoDispose
    .family<List<Product>, String?>((ref, filter) async {
      final business = ref.watch(sessionProvider.select((s) => s.business));
      if (business == null) return [];
      final all = await ref.watch(productServiceProvider).list(business.id);
      final tracked = all.where((p) => p.trackStock && !p.isService).toList();
      switch (filter) {
        case 'low':
          return tracked
              .where((p) => p.stockQty > 0 && p.stockQty <= p.lowStockThreshold)
              .toList();
        case 'out':
          return tracked.where((p) => p.stockQty <= 0).toList();
        default:
          return tracked;
      }
    });

/// Stock — large title iOS + filtres pill + liste inset.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  String? _filter;
  String _query = '';
  bool _hideLynk = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_stockProvider(_filter));
    final performanceMode = ref.watch(
      sessionProvider.select((s) => s.performanceMode),
    );
    final bottom = 28.0;
    final reduce =
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
        performanceMode;
    final scheme = Theme.of(context).colorScheme;
    final dark = AppColors.isDark(context);

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.tr('Inventaire', 'Inventory'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        Text(
                          'Stock',
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.8,
                                height: 1.05,
                              ),
                        ),
                      ],
                    ),
                  ),
                  KumbaChromeButton(
                    icon: Icons.fact_check_outlined,
                    tooltip: S.tr('Inventaire', 'Inventory'),
                    onTap: () => context.push('/inventory'),
                  ),
                  const SizedBox(width: 8),
                  KumbaChromeButton(
                    icon: Icons.add_rounded,
                    onTap: () => context.push('/products/new'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Container(
              decoration: BoxDecoration(
                color: dark ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.primary.withValues(alpha: 0.10),
                ),
              ),
              child: KumbaTextField(
                hint: 'Rechercher un produit…',
                prefixIcon: Icons.search,
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _chip(null, 'Tous', Icons.apps_rounded, AppColors.fab),
                _chip(
                  'low',
                  'Faible',
                  Icons.warning_amber_rounded,
                  AppColors.kpiDebt,
                ),
                _chip(
                  'out',
                  'Rupture',
                  Icons.remove_circle_outline,
                  AppColors.kpiDeposit,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!_hideLynk)
            async.maybeWhen(
              data: (products) {
                final n = products
                    .where((p) => p.stockQty <= p.lowStockThreshold)
                    .length;
                if (n == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: LynkContextBubble(
                    message: S.tr(
                      '$n article(s) sous le seuil. Je peux te dire quoi réapprovisionner.',
                      '$n item(s) below threshold. I can tell you what to restock.',
                    ),
                    actionLabel: S.tr('Demander à Lynk', 'Ask Lynk'),
                    onAction: () {
                      ref.read(pendingAiPromptProvider.notifier).state = S.tr(
                        'Que dois-je réapprovisionner en priorité ?',
                        'What should I restock first?',
                      );
                      showLynkQuickSheet(context);
                    },
                    onDismiss: () => setState(() => _hideLynk = true),
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
          Expanded(
            child: async.when(
              loading: () => const KumbaSkeletonList(),
              error: (e, _) => KumbaErrorState(message: e.toString()),
              data: (products) {
                final list = _query.isEmpty
                    ? products
                    : products
                          .where((p) => p.name.toLowerCase().contains(_query))
                          .toList();
                if (list.isEmpty) {
                  return KumbaEmptyState(
                    title: 'Aucun produit en stock',
                    actionLabel: 'Ajouter un produit',
                    onAction: () => context.push('/products/new'),
                  );
                }
                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async => ref.invalidate(_stockProvider),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(20, 0, 20, bottom),
                    children: [
                      KumbaInsetGroup(
                        children: [
                          for (var i = 0; i < list.length; i++)
                            _productRow(list[i], i, reduce),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _productRow(Product p, int i, bool reduce) {
    final low = p.stockQty <= p.lowStockThreshold;
    final out = p.stockQty <= 0;
    final statusColor = out
        ? AppColors.kpiDeposit
        : low
        ? AppColors.kpiDebt
        : AppColors.kpiSales;

    final row = KumbaInsetRow(
      icon: out
          ? Icons.inventory_2_outlined
          : low
          ? Icons.inventory_outlined
          : Icons.inventory_2_rounded,
      iconColor: statusColor,
      title: p.name,
      subtitle:
          'Valeur ${MoneyFormat.format(p.stockQty * p.costPrice)} · Seuil ${p.lowStockThreshold.toStringAsFixed(0)}',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
        ),
        child: Text(
          out ? 'Rupture' : '${p.stockQty.toStringAsFixed(0)} ${p.unit}',
          style: TextStyle(
            color: statusColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/products/${p.id}');
      },
    );

    if (reduce) return row;
    return row
        .animate()
        .fadeIn(delay: (22 * (i % 12)).ms, duration: 240.ms)
        .slideY(begin: 0.03, end: 0, delay: (22 * (i % 12)).ms);
  }

  Widget _chip(String? id, String label, IconData icon, Color accent) {
    final selected = _filter == id;
    final dark = AppColors.isDark(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _filter = id);
            ref.invalidate(_stockProvider);
          },
          borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? accent
                  : (dark ? AppColors.darkCard : Colors.white),
              borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
              border: Border.all(
                color: selected
                    ? accent
                    : (dark
                          ? Colors.white.withValues(alpha: 0.08)
                          : accent.withValues(alpha: 0.18)),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: selected ? Colors.white : accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? Colors.white : AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
