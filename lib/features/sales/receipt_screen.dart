import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/billing/billing_engine.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/database/app_database.dart';
import '../../core/permissions/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_format.dart';
import '../../core/utils/esc_pos_printer_service.dart';
import '../../core/utils/thermal_receipt_service.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';

class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  Sale? _sale;
  List<SaleItem> _items = [];
  InvoiceComputation? _invoice;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sale = await ref.read(saleServiceProvider).byId(widget.saleId);
    final items = sale != null
        ? await ref.read(saleServiceProvider).items(sale.id)
        : <SaleItem>[];

    InvoiceComputation? invoice;
    if (sale != null) {
      final billingJson = await ref.read(saleServiceProvider).billingJson(sale.id);
      Map<String, dynamic>? stored;
      try {
        if (billingJson.isNotEmpty) stored = jsonDecode(billingJson);
      } catch (_) {}
      
      invoice = BillingEngine.hydrate(
        stored: stored,
        fallbackLines: items.map((i) => BillingLineInput(
          productId: i.productId,
          productName: i.productName,
          unit: i.unit,
          quantity: i.quantity,
          unitPrice: i.unitPrice,
          discount: i.discount,
          costPrice: i.costPrice,
        )).toList(),
        globalDiscount: sale.discount,
        amountPaid: sale.amountPaid,
      );
    }

    setState(() {
      _sale = sale;
      _items = items;
      _invoice = invoice;
      _loading = false;
    });
  }

  String _receiptText() {
    final s = _sale!;
    final business = ref.read(sessionProvider).business;
    return ReceiptLayout.plainText(
      businessName: business?.name ?? 'KUMBA Business',
      reference: s.reference,
      soldAt: s.soldAt,
      invoice: _invoice!,
      customerName: s.customerName,
      paymentSummary: s.amountDue > 0 ? 'Crédit / Dette' : 'Espèces',
    );
  }

  @override
  Widget build(BuildContext context) {
    final perf = ref.watch(sessionProvider.select((s) => s.performanceMode));
    final canReturn = ref.watch(
      sessionProvider.select((s) => s.can(AppPermission.salesReturn)),
    );
    final reduce =
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false) || perf;

    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.pageBg,
        body: KumbaLoading(),
      );
    }
    final s = _sale;
    if (s == null) {
      return Scaffold(
        backgroundColor: AppColors.pageBg,
        appBar: AppBar(),
        body: const KumbaErrorState(message: 'Vente introuvable.'),
      );
    }
    final business = ref.watch(sessionProvider.select((s) => s.business));

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.tr('Reçu', 'Receipt'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          8,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        children: [
          // Success hero
          KumbaCard(
                child: Column(
                  children: [
                    Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.forestSoft,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.emerald.withValues(
                                  alpha: 0.25,
                                ),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.emerald,
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
                      'Vente enregistrée',
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
                      DateFormat('dd MMM yyyy · HH:mm', 'fr').format(s.soldAt),
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
          // Ticket body
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
                            color: AppColors.primaryFixed.withValues(
                              alpha: 0.65,
                            ),
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
                    ..._invoice!.lines.asMap().entries.map((e) {
                      final i = e.value;
                      final idx = e.key;
                      return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${i.productName}\n${i.quantity.toStringAsFixed(i.quantity % 1 == 0 ? 0 : 2)} × ${MoneyFormat.format(i.unitPriceTtc)}'
                                    '${i.discount > 0 ? '\nRemise ligne : -${MoneyFormat.format(i.discount)}' : ''}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                                Text(
                                  MoneyFormat.format(i.lineTtc),
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
                    _line(context, 'Sous-total HT', MoneyFormat.format(_invoice!.subtotalHt)),
                    if (_invoice!.globalDiscount > 0)
                      _line(context, 'Remise', '-${MoneyFormat.format(_invoice!.globalDiscount)}'),
                    if (_invoice!.taxTotal > 0)
                      ..._invoice!.taxBuckets.where((b) => b.taxAmount > 0).map(
                        (b) => _line(context, 'TVA ${(b.rate * 100).toStringAsFixed(b.rate * 100 % 1 == 0 ? 0 : 2)} %', MoneyFormat.format(b.taxAmount))
                      )
                    else
                      _line(context, 'TVA', '${MoneyFormat.format(0)} (exonéré)'),
                    const SizedBox(height: 8),
                    _line(
                      context,
                      'Total TTC',
                      MoneyFormat.format(_invoice!.totalTtc),
                      bold: true,
                    ),
                    _line(context, 'Payé', MoneyFormat.format(_invoice!.amountPaid)),
                    if (_invoice!.amountDue > 0)
                      _line(
                        context,
                        'Reste à payer',
                        MoneyFormat.format(_invoice!.amountDue),
                        color: AppColors.debt,
                      ),
                    if (_invoice!.changeGiven > 0)
                      _line(
                        context,
                        'Monnaie à rendre',
                        MoneyFormat.format(_invoice!.changeGiven),
                        color: AppColors.forest,
                      ),
                    if (s.customerName != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 16,
                            color: AppColors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Client : ${s.customerName}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              )
              .animate(target: reduce ? 0 : 1)
              .fadeIn(delay: 80.ms, duration: 320.ms)
              .slideY(begin: 0.03, end: 0),
          const SizedBox(height: 24),
          KumbaButton(
            label: 'Imprimer / PDF',
            icon: Icons.print_outlined,
            onPressed: () async {
              HapticFeedback.lightImpact();
              final bName = business?.name ?? AppConfig.appName;
              try {
                await ThermalReceiptService.printReceipt(
                  businessName: bName,
                  saleId: s.reference,
                  items: _items
                      .map(
                        (i) => {
                          'name': i.productName,
                          'qty': i.quantity,
                          'price': i.unitPrice,
                        },
                      )
                      .toList(),
                  totalAmount: s.total,
                  paymentMethod: s.amountDue > 0 ? 'Crédit / Dette' : 'Espèces',
                  date: s.soldAt,
                );
              } catch (e) {
                if (!context.mounted) return;
                showLkToast(
                  context,
                  '${S.tr('Impression impossible', 'Unable to print')} : $e',
                  tone: LkToastTone.danger,
                  icon: Icons.print_disabled,
                );
              }
            },
          ).animate(target: reduce ? 0 : 1).fadeIn(delay: 140.ms, duration: 280.ms),
          const SizedBox(height: 10),
          KumbaButton(
                label: 'Imprimer en Bluetooth ESC/POS',
                icon: Icons.bluetooth_connected,
                variant: KumbaButtonVariant.secondary,
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  try {
                    final devices = await EscPosPrinterService.pairedDevices();
                    if (!context.mounted) return;
                    if (devices.isEmpty) {
                      throw StateError(
                        'Aucune imprimante appairée dans Android.',
                      );
                    }
                    final selected = await showDialog<BluetoothPrinterDevice>(
                      context: context,
                      builder: (dialogContext) => SimpleDialog(
                        title: const Text('Choisir une imprimante appairée'),
                        children: devices
                            .map(
                              (device) => SimpleDialogOption(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, device),
                                child: ListTile(
                                  leading: const Icon(Icons.print),
                                  title: Text(device.name),
                                  subtitle: Text(device.address),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    );
                    if (selected == null) return;
                    final bytes = EscPosPrinterService.buildRawReceipt(
                      businessName: business?.name ?? AppConfig.appName,
                      saleId: s.reference,
                      items: _items
                          .map(
                            (i) => {
                              'name': i.productName,
                              'qty': i.quantity,
                              'price': i.unitPrice,
                            },
                          )
                          .toList(),
                      totalAmount: s.total,
                      paymentMethod: s.amountDue > 0
                          ? 'Crédit / Dette'
                          : 'Espèces',
                      date: s.soldAt,
                    );
                    await EscPosPrinterService.printToDevice(
                      device: selected,
                      bytes: bytes,
                    );
                    if (!context.mounted) return;
                    showLkToast(
                      context,
                      'Ticket envoyé à ${selected.name}.',
                      tone: LkToastTone.success,
                      icon: Icons.print_rounded,
                    );
                  } catch (error) {
                    if (!context.mounted) return;
                    showLkToast(
                      context,
                      'Impression Bluetooth impossible : $error',
                      tone: LkToastTone.danger,
                      icon: Icons.print_disabled,
                    );
                  }
                },
              )
              .animate(target: reduce ? 0 : 1)
              .fadeIn(delay: 170.ms, duration: 280.ms),
          const SizedBox(height: 10),
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
            label: 'Copier',
            variant: KumbaButtonVariant.outline,
            icon: Icons.copy_outlined,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _receiptText()));
              HapticFeedback.lightImpact();
              showLkToast(
                context,
                S.tr('Reçu copié', 'Receipt copied'),
                tone: LkToastTone.info,
                icon: Icons.copy_all_rounded,
              );
            },
          ),
          const SizedBox(height: 10),
          KumbaButton(
            label: 'Nouvelle vente',
            variant: KumbaButtonVariant.secondary,
            icon: Icons.add_shopping_cart_rounded,
            onPressed: () => context.go('/vente'),
          ),
          const SizedBox(height: 10),
          if (canReturn)
            KumbaButton(
              label: 'Retour / annulation',
              variant: KumbaButtonVariant.outline,
              icon: Icons.undo_rounded,
              onPressed: () => context.push('/sale/return/${s.id}'),
            ),
          if (canReturn) const SizedBox(height: 10),
          KumbaButton(
            label: 'Retour à l’accueil',
            variant: KumbaButtonVariant.ghost,
            onPressed: () => context.go('/home'),
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
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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
                      color: color ?? (bold ? AppColors.primary : null),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
          ),
        ],
      ),
    );
  }
}
