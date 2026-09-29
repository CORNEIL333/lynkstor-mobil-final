import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';
import '../../shared/widgets/permission_gate.dart';
import '../../core/permissions/permissions.dart';

class SaleReturnScreen extends ConsumerStatefulWidget {
  const SaleReturnScreen({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<SaleReturnScreen> createState() => _SaleReturnScreenState();
}

class _SaleReturnScreenState extends ConsumerState<SaleReturnScreen> {
  Sale? _sale;
  List<SaleItem> _items = [];
  final Map<String, double> _qty = {};
  final _reasonCtrl = TextEditingController();
  String _refundMethod = 'refund';
  bool _restock = true;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sale = await ref.read(saleServiceProvider).byId(widget.saleId);
    final items = sale != null
        ? await ref.read(saleServiceProvider).items(sale.id)
        : <SaleItem>[];
    setState(() {
      _sale = sale;
      _items = items;
      for (final i in items) {
        _qty[i.id] = 0;
      }
      _loading = false;
    });
  }

  Future<void> _submit() async {
    final sale = _sale;
    if (sale == null) return;
    final session = ref.read(sessionProvider);
    final lines =
        <
          ({
            String? productId,
            String productName,
            double qty,
            double unitPrice,
          })
        >[];
    for (final item in _items) {
      final q = _qty[item.id] ?? 0;
      if (q <= 0) continue;
      if (q > item.quantity) {
        setState(
          () => _error =
              'Quantité de retour trop élevée pour ${item.productName}.',
        );
        return;
      }
      lines.add((
        productId: item.productId,
        productName: item.productName,
        qty: q,
        unitPrice: item.unitPrice,
      ));
    }
    if (lines.isEmpty) {
      setState(
        () => _error = 'Sélectionnez au moins un article et une quantité.',
      );
      return;
    }
    if (_reasonCtrl.text.trim().isEmpty) {
      setState(
        () =>
            _error = 'Indiquez le motif du retour (obligatoire pour l’audit).',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final ret = await ref
          .read(saleServiceProvider)
          .createReturn(
            businessId: session.business!.id,
            saleId: sale.id,
            lines: lines,
            reason: _reasonCtrl.text.trim(),
            refundMethod: _refundMethod,
            restock: _restock,
            userId: session.user?.id,
            authorizedBy: session.user?.id,
            userRole: session.role,
          );
      if (!mounted) return;
      showLkToast(
        context,
        'Retour ${ret.reference} enregistré — stock et audit mis à jour.',
        tone: LkToastTone.success,
        icon: Icons.check_circle_outline,
      );
      context.go('/sales');
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
    return PermissionGate(
      permission: AppPermission.salesReturn,
      module: 'pos',
      child: Scaffold(
        backgroundColor: AppColors.pageBg,
        appBar: AppBar(title: Text(S.returnSale)),
        body: _loading
            ? const KumbaLoading()
            : _sale == null
            ? KumbaErrorState(
                message: S.tr('Vente introuvable', 'Sale not found'),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Vente ${_sale!.reference}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    S.tr(
                      'Une vente validée n’est jamais supprimée silencieusement. '
                          'Ce retour crée un mouvement d’audit et peut remettre en stock.',
                      'A completed sale is never silently deleted. This return '
                          'creates an audit entry and can restore stock.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  ..._items.map((item) {
                    final selected = _qty[item.id] ?? 0;
                    return Card(
                      child: ListTile(
                        title: Text(item.productName),
                        subtitle: Text(
                          '${S.tr('Vendu', 'Sold')} : '
                          '${item.quantity.toStringAsFixed(0)} · '
                          '${MoneyFormat.format(item.unitPrice)}',
                        ),
                        trailing: SizedBox(
                          width: 110,
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: selected <= 0
                                    ? null
                                    : () => setState(
                                        () => _qty[item.id] = selected - 1,
                                      ),
                              ),
                              Text(selected.toStringAsFixed(0)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: selected >= item.quantity
                                    ? null
                                    : () => setState(
                                        () => _qty[item.id] = selected + 1,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  KumbaTextField(
                    controller: _reasonCtrl,
                    label: S.tr('Motif (obligatoire)', 'Reason (required)'),
                    hint: S.tr(
                      'Ex. produit défectueux, erreur de caisse…',
                      'E.g. defective product, checkout error…',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    S.tr('Type de compensation', 'Compensation type'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(S.tr('Remboursement', 'Refund')),
                        selected: _refundMethod == 'refund',
                        onSelected: (_) =>
                            setState(() => _refundMethod = 'refund'),
                      ),
                      ChoiceChip(
                        label: Text(S.tr('Avoir', 'Credit note')),
                        selected: _refundMethod == 'credit_note',
                        onSelected: (_) =>
                            setState(() => _refundMethod = 'credit_note'),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(S.tr('Remettre en stock', 'Restore stock')),
                    value: _restock,
                    onChanged: (v) => setState(() => _restock = v),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  const SizedBox(height: 16),
                  KumbaButton(
                    label: S.tr('Valider le retour', 'Confirm return'),
                    icon: Icons.undo_rounded,
                    isLoading: _submitting,
                    variant: KumbaButtonVariant.destructive,
                    onPressed: _submitting ? null : _submit,
                  ),
                ],
              ),
      ),
    );
  }
}
