import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';

final _invoicesProvider = FutureProvider.autoDispose<List<Invoice>>((
  ref,
) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  return ref.watch(databaseProvider).getInvoices(business.id);
});

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  Future<void> _fromLastSale(BuildContext context, WidgetRef ref) async {
    final business = ref.read(sessionProvider).business!;
    final sales = await ref.read(saleServiceProvider).list(business.id);
    if (!context.mounted) return;
    if (sales.isEmpty) {
      showLkToast(
        context,
        S.tr('Aucune vente à facturer.', 'No sale to invoice.'),
        tone: LkToastTone.warning,
        icon: Icons.info_outline,
      );
      return;
    }
    final sale = sales.first;
    final items = await ref.read(saleServiceProvider).items(sale.id);
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final id = IdGenerator.uuid();

    await db.transaction(() async {
      await db
          .into(db.invoices)
          .insert(
            InvoicesCompanion.insert(
              id: id,
              businessId: business.id,
              reference: IdGenerator.businessRef('FAC'),
              customerId: Value(sale.customerId),
              customerName: Value(sale.customerName),
              saleId: Value(sale.id),
              status: Value(sale.amountDue > 0 ? 'partial' : 'paid'),
              subtotal: Value(sale.subtotal),
              discount: Value(sale.discount),
              total: Value(sale.total),
              amountPaid: Value(sale.amountPaid),
              amountDue: Value(sale.amountDue),
              userId: Value(ref.read(sessionProvider).user?.id),
              issuedAt: now,
              createdAt: now,
            ),
          );

      for (final i in items) {
        await db
            .into(db.invoiceItems)
            .insert(
              InvoiceItemsCompanion.insert(
                id: IdGenerator.uuid(),
                invoiceId: id,
                productId: Value(i.productId),
                productName: i.productName,
                quantity: i.quantity,
                unitPrice: i.unitPrice,
                discount: Value(i.discount),
                lineTotal: i.lineTotal,
              ),
            );
      }
    });
    final invoice = await (db.select(
      db.invoices,
    )..where((row) => row.id.equals(id))).getSingle();
    final invoiceItems = await (db.select(
      db.invoiceItems,
    )..where((row) => row.invoiceId.equals(id))).get();
    await ref
        .read(syncEngineProvider)
        .enqueue(
          businessId: business.id,
          entityType: 'invoice',
          entityId: id,
          operation: 'create',
          payload: {
            'invoice': invoice.toJson(),
            'items': invoiceItems.map((row) => row.toJson()).toList(),
          },
          userId: ref.read(sessionProvider).user?.id,
        );

    ref.invalidate(_invoicesProvider);
    if (context.mounted) {
      showLkToast(
        context,
        S.tr(
          'Facture créée depuis ${sale.reference}',
          'Invoice created from ${sale.reference}',
        ),
        tone: LkToastTone.success,
        icon: Icons.check_circle_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_invoicesProvider);
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: Text(S.tr('Factures', 'Invoices')),
        actions: [
          TextButton(
            onPressed: () => _fromLastSale(context, ref),
            child: Text(S.tr('Depuis vente', 'From sale')),
          ),
        ],
      ),
      body: async.when(
        loading: () => const KumbaSkeletonList(),
        error: (e, _) => KumbaErrorState(message: e.toString()),
        data: (list) {
          if (list.isEmpty) {
            return KumbaEmptyState(
              title: 'Aucune facture',
              subtitle: 'Générez une facture à partir d’une vente récente.',
              actionLabel: 'Depuis dernière vente',
              onAction: () => _fromLastSale(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final inv = list[i];
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(
                    inv.reference,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${inv.customerName ?? 'Comptant'} · ${DateFormat('dd/MM/yyyy').format(inv.issuedAt)}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        MoneyFormat.format(inv.total),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        inv.status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: inv.amountDue > 0
                              ? AppColors.kpiDebt
                              : AppColors.kpiSales,
                        ),
                      ),
                    ],
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
