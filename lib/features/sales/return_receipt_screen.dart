import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/kumba_states.dart';
import '../../l10n/app_strings.dart';

class ReturnReceiptScreen extends ConsumerStatefulWidget {
  const ReturnReceiptScreen({super.key, required this.returnId});

  final String returnId;

  @override
  ConsumerState<ReturnReceiptScreen> createState() =>
      _ReturnReceiptScreenState();
}

class _ReturnReceiptScreenState extends ConsumerState<ReturnReceiptScreen> {
  SaleReturn? _saleReturn;
  List<SaleReturnItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ret = await ref.read(saleServiceProvider).returnById(widget.returnId);
    final items = ret != null
        ? await ref.read(saleServiceProvider).returnItems(ret.id)
        : <SaleReturnItem>[];
    setState(() {
      _saleReturn = ret;
      _items = items;
      _loading = false;
    });
  }

  String _receiptText() {
    final s = _saleReturn!;
    final business = ref.read(sessionProvider).business;
    final buf = StringBuffer()
      ..writeln(business?.name ?? 'KUMBA Business')
      ..writeln('Reçu de retour ${s.reference}')
      ..writeln(DateFormat('dd/MM/yyyy HH:mm').format(s.createdAt))
      ..writeln("Vente d'origine : ${s.saleId}")
      ..writeln('----------------------------');
    for (final i in _items) {
      buf.writeln('${i.productName} x${i.quantity.toStringAsFixed(0)}');
      buf.writeln('  ${MoneyFormat.format(i.lineTotal)}');
    }
    buf
      ..writeln('----------------------------')
      ..writeln('Total : ${MoneyFormat.format(s.total)}')
      ..writeln('Motif : ${s.reason}')
      ..writeln(
        'Méthode : ${s.refundMethod == 'refund' ? 'Remboursement' : 'Avoir'}',
      )
      ..writeln('Merci pour votre confiance.');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final perf = ref.watch(sessionProvider.select((s) => s.performanceMode));
    final reduce =
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false) || perf;

    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.pageBg,
        body: KumbaLoading(),
      );
    }
    final s = _saleReturn;
    if (s == null) {
      return Scaffold(
        backgroundColor: AppColors.pageBg,
        appBar: AppBar(),
        body: const KumbaErrorState(message: 'Retour introuvable.'),
      );
    }
    final business = ref.watch(sessionProvider.select((s) => s.business));

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.tr('Reçu de retour', 'Return Receipt'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          8,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        children: [
          KumbaCard(
                child: Column(
                  children: [
                    Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.kpiDebt.withValues(alpha: 0.1),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.kpiDebt.withValues(alpha: 0.25),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.undo_rounded,
                            color: AppColors.kpiDebt,
                            size: 40,
                          ),
                        )
                        .animate(target: reduce ? 0 : 1)
                        .scale(
                          begin: const Offset(0.6, 0.6),
                          end: const Offset(1, 1),
                          duration: 480.ms,
                          curve: Curves.easeOutBack,
                        )
                        .fadeIn(duration: 280.ms),
                    const SizedBox(height: 14),
                    Text(
                      'Retour enregistré',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.reference,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat(
                        'dd MMM yyyy · HH:mm',
                        'fr',
                      ).format(s.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                          MoneyFormat.format(s.total),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        )
                        .animate(target: reduce ? 0 : 1)
                        .fadeIn(delay: 120.ms, duration: 320.ms)
                        .slideY(begin: 0.08, end: 0),
                  ],
                ),
              )
              .animate(target: reduce ? 0 : 1)
              .fadeIn(duration: 320.ms)
              .slideY(begin: 0.04, end: 0),
          const SizedBox(height: 16),
          KumbaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primaryFixed.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                business?.name ?? '',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (business?.phone != null)
                                Text(
                                  business!.phone,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(height: 1, color: AppColors.outlineVariant),
                    const SizedBox(height: 14),
                    ..._items.asMap().entries.map((e) {
                      final i = e.value;
                      final idx = e.key;
                      return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${i.productName}\n${i.quantity.toStringAsFixed(0)} × ${MoneyFormat.format(i.unitPrice)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                                Text(
                                  MoneyFormat.format(i.lineTotal),
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                              ],
                            ),
                          )
                          .animate(target: reduce ? 0 : 1)
                          .fadeIn(delay: (40 * idx).ms, duration: 240.ms)
                          .slideX(begin: 0.02, end: 0);
                    }),
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: AppColors.outlineVariant,
                    ),
                    const SizedBox(height: 8),
                    _line(
                      context,
                      'Total',
                      MoneyFormat.format(s.total),
                      bold: true,
                    ),
                    _line(
                      context,
                      'Type',
                      s.refundMethod == 'refund' ? 'Remboursement' : 'Avoir',
                    ),
                    _line(context, 'Motif', s.reason),
                  ],
                ),
              )
              .animate(target: reduce ? 0 : 1)
              .fadeIn(delay: 80.ms, duration: 320.ms)
              .slideY(begin: 0.03, end: 0),
          const SizedBox(height: 24),
          KumbaButton(
                label: 'Partager le reçu',
                icon: Icons.share_outlined,
                variant: KumbaButtonVariant.gold,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Share.share(_receiptText());
                },
              )
              .animate(target: reduce ? 0 : 1)
              .fadeIn(delay: 180.ms, duration: 280.ms),
          const SizedBox(height: 10),
          KumbaButton(
            label: "Retour à l'historique",
            variant: KumbaButtonVariant.ghost,
            onPressed: () => context.pop(),
          ),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: bold ? AppColors.onSurface : AppColors.onSurfaceVariant,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style:
                (bold
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.bodyLarge)
                    ?.copyWith(
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                      color: bold ? AppColors.primary : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
          ),
        ],
      ),
    );
  }
}
