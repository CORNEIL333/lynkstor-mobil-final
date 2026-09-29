import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';

final _purchasesProvider = FutureProvider.autoDispose<List<Purchase>>((
  ref,
) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  return ref.watch(databaseProvider).getPurchases(business.id);
});

class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  Future<void> _addSimple(BuildContext context, WidgetRef ref) async {
    final products = await ref
        .read(productServiceProvider)
        .list(ref.read(sessionProvider).business!.id);
    if (!context.mounted) return;
    if (products.isEmpty) {
      showLkToast(
        context,
        S.tr('Créez d’abord des produits.', 'Create products first.'),
        tone: LkToastTone.warning,
        icon: Icons.info_outline,
      );
      return;
    }
    Product? selected = products.first;
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController(
      text: products.first.costPrice.toStringAsFixed(0),
    );

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Réception d’achat',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Le stock n’augmente qu’à la réception.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Product>(
                initialValue: selected,
                items: products
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                    .toList(),
                onChanged: (p) => setModal(() {
                  selected = p;
                  costCtrl.text = p?.costPrice.toStringAsFixed(0) ?? '0';
                }),
                decoration: InputDecoration(
                  labelText: S.tr('Produit', 'Product'),
                ),
              ),
              const SizedBox(height: 12),
              KumbaTextField(
                controller: qtyCtrl,
                label: 'Quantité reçue',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              KumbaAmountField(
                controller: costCtrl,
                label: 'Prix d’achat unitaire',
              ),
              const SizedBox(height: 16),
              KumbaButton(
                label: 'Réceptionner et mettre en stock',
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true || selected == null) return;
    final qty = MoneyFormat.parse(qtyCtrl.text) ?? 0;
    final cost = MoneyFormat.parse(costCtrl.text) ?? 0;
    if (qty <= 0) return;

    final session = ref.read(sessionProvider);
    final business = session.business!;
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final purchaseId = IdGenerator.uuid();
    final total = qty * cost;

    await db.transaction(() async {
      await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: purchaseId,
              businessId: business.id,
              reference: IdGenerator.businessRef('ACH'),
              status: const Value('received'),
              subtotal: Value(total),
              total: Value(total),
              amountPaid: Value(total),
              userId: Value(session.user?.id),
              purchasedAt: now,
              receivedAt: Value(now),
              createdAt: now,
              idempotencyKey: IdGenerator.uuid(),
            ),
          );
      await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              id: IdGenerator.uuid(),
              purchaseId: purchaseId,
              productId: Value(selected!.id),
              productName: selected!.name,
              quantityOrdered: qty,
              quantityReceived: Value(qty),
              unitCost: cost,
              lineTotal: total,
            ),
          );
    });

    await ref
        .read(productServiceProvider)
        .adjustStock(
          businessId: business.id,
          productId: selected!.id,
          newQty: selected!.stockQty + qty,
          reason: 'Réception achat',
          userId: session.user?.id,
          type: 'purchase',
          userRole: session.role,
        );

    final purchase = await (db.select(
      db.purchases,
    )..where((row) => row.id.equals(purchaseId))).getSingle();
    final purchaseItems = await (db.select(
      db.purchaseItems,
    )..where((row) => row.purchaseId.equals(purchaseId))).get();
    await ref
        .read(syncEngineProvider)
        .enqueue(
          businessId: business.id,
          entityType: 'purchase',
          entityId: purchaseId,
          operation: 'create',
          payload: {
            'purchase': purchase.toJson(),
            'items': purchaseItems.map((row) => row.toJson()).toList(),
          },
          userId: session.user?.id,
        );

    ref.invalidate(_purchasesProvider);
    if (context.mounted) {
      showLkToast(
        context,
        S.tr(
          'Achat réceptionné — stock mis à jour.',
          'Purchase received — stock updated.',
        ),
        tone: LkToastTone.success,
        icon: Icons.check_circle_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_purchasesProvider);
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.tr('Achats', 'Purchases'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSimple(context, ref),
        icon: const Icon(Icons.add),
        label: Text(S.tr('Réception', 'Receive')),
      ),
      body: async.when(
        loading: () => const KumbaSkeletonList(),
        error: (e, _) => KumbaErrorState(message: e.toString()),
        data: (list) {
          if (list.isEmpty) {
            return KumbaEmptyState(
              title: 'Aucun achat',
              subtitle: 'Réceptionnez une marchandise pour augmenter le stock.',
              actionLabel: 'Réceptionner',
              onAction: () => _addSimple(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = list[i];
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                title: Text(p.reference),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(p.purchasedAt)),
                trailing: Text(
                  MoneyFormat.format(p.total),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
