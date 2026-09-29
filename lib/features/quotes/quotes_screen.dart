import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';

final _quotesProvider = FutureProvider.autoDispose<List<Quote>>((ref) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  return ref.watch(databaseProvider).getQuotes(business.id);
});

class QuotesScreen extends ConsumerWidget {
  const QuotesScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final products = await ref
        .read(productServiceProvider)
        .list(ref.read(sessionProvider).business!.id);
    final customers = await ref
        .read(customerServiceProvider)
        .list(ref.read(sessionProvider).business!.id);
    if (!context.mounted) return;
    if (products.isEmpty) {
      showLkToast(
        context,
        S.tr('Ajoutez des produits d’abord.', 'Add products first.'),
        tone: LkToastTone.warning,
        icon: Icons.info_outline,
      );
      return;
    }
    Product selected = products.first;
    Customer? customer = customers.isNotEmpty ? customers.first : null;
    final qtyCtrl = TextEditingController(text: '1');

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
            children: [
              Text(
                S.tr('Nouveau devis', 'New quote'),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (customers.isNotEmpty)
                DropdownButtonFormField<Customer>(
                  initialValue: customer,
                  items: customers
                      .map(
                        (c) => DropdownMenuItem(value: c, child: Text(c.name)),
                      )
                      .toList(),
                  onChanged: (c) => setModal(() => customer = c),
                  decoration: InputDecoration(
                    labelText: S.tr('Client', 'Customer'),
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Product>(
                initialValue: selected,
                items: products
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                    .toList(),
                onChanged: (p) => setModal(() => selected = p!),
                decoration: InputDecoration(
                  labelText: S.tr('Produit / service', 'Product / service'),
                ),
              ),
              const SizedBox(height: 12),
              KumbaTextField(
                controller: qtyCtrl,
                label: 'Quantité',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              KumbaButton(
                label: 'Créer le devis',
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;

    final qty = double.tryParse(qtyCtrl.text) ?? 1;
    final total = selected.salePrice * qty;
    final session = ref.read(sessionProvider);
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final id = IdGenerator.uuid();
    final refCode = IdGenerator.businessRef('DEV');

    await db.transaction(() async {
      await db
          .into(db.quotes)
          .insert(
            QuotesCompanion.insert(
              id: id,
              businessId: session.business!.id,
              reference: refCode,
              customerId: Value(customer?.id),
              customerName: Value(customer?.name),
              status: const Value('draft'),
              subtotal: Value(total),
              total: Value(total),
              userId: Value(session.user?.id),
              createdAt: now,
              updatedAt: now,
              validUntil: Value(now.add(const Duration(days: 15))),
            ),
          );
      await db
          .into(db.quoteItems)
          .insert(
            QuoteItemsCompanion.insert(
              id: IdGenerator.uuid(),
              quoteId: id,
              productId: Value(selected.id),
              productName: selected.name,
              quantity: qty,
              unitPrice: selected.salePrice,
              lineTotal: total,
            ),
          );
    });
    final quote = await (db.select(
      db.quotes,
    )..where((row) => row.id.equals(id))).getSingle();
    final quoteItems = await (db.select(
      db.quoteItems,
    )..where((row) => row.quoteId.equals(id))).get();
    await ref
        .read(syncEngineProvider)
        .enqueue(
          businessId: session.business!.id,
          entityType: 'quote',
          entityId: id,
          operation: 'create',
          payload: {
            'quote': quote.toJson(),
            'items': quoteItems.map((row) => row.toJson()).toList(),
          },
          userId: session.user?.id,
        );

    ref.invalidate(_quotesProvider);
    final text =
        '''
Devis $refCode
${session.business!.name}
Client : ${customer?.name ?? '—'}
${selected.name} × ${qty.toStringAsFixed(0)}
Total : ${MoneyFormat.format(total)}
Valable 15 jours
''';
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_quotesProvider);
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.tr('Devis', 'Quotes'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _create(context, ref),
        child: const Icon(Icons.add),
      ),
      body: async.when(
        loading: () => const KumbaSkeletonList(),
        error: (e, _) => KumbaErrorState(message: e.toString()),
        data: (list) {
          if (list.isEmpty) {
            return KumbaEmptyState(
              title: 'Aucun devis',
              actionLabel: 'Créer',
              onAction: () => _create(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final q = list[i];
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(
                    q.reference,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${q.customerName ?? 'Sans client'} · ${DateFormat('dd/MM').format(q.createdAt)}',
                  ),
                  trailing: Text(
                    MoneyFormat.format(q.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.fab,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
