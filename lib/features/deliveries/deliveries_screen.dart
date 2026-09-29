import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../l10n/app_strings.dart';

final _deliveriesProvider = FutureProvider.autoDispose<List<Delivery>>((
  ref,
) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  return ref.watch(databaseProvider).getDeliveries(business.id);
});

class DeliveriesScreen extends ConsumerWidget {
  const DeliveriesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final amount = TextEditingController(text: '0');

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
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
              'Nouvelle livraison',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            KumbaTextField(controller: name, label: 'Client'),
            const SizedBox(height: 12),
            KumbaTextField(
              controller: phone,
              label: 'Téléphone',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            KumbaTextField(controller: address, label: 'Adresse / quartier'),
            const SizedBox(height: 12),
            KumbaAmountField(controller: amount, label: 'Montant à encaisser'),
            const SizedBox(height: 16),
            KumbaButton(
              label: 'Créer',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;

    final business = ref.read(sessionProvider).business!;
    final id = IdGenerator.uuid();
    await ref
        .read(databaseProvider)
        .into(ref.read(databaseProvider).deliveries)
        .insert(
          DeliveriesCompanion.insert(
            id: id,
            businessId: business.id,
            reference: IdGenerator.businessRef('LIV'),
            customerName: name.text.trim(),
            customerPhone: Value(phone.text.isEmpty ? null : phone.text),
            address: Value(address.text.isEmpty ? null : address.text),
            amountToCollect: Value(MoneyFormat.parse(amount.text) ?? 0),
            assignedTo: Value(ref.read(sessionProvider).user?.id),
            createdAt: DateTime.now(),
            scheduledAt: Value(DateTime.now()),
          ),
        );
    final db = ref.read(databaseProvider);
    final delivery = await (db.select(
      db.deliveries,
    )..where((row) => row.id.equals(id))).getSingle();
    await ref
        .read(syncEngineProvider)
        .enqueue(
          businessId: business.id,
          entityType: 'delivery',
          entityId: id,
          operation: 'create',
          payload: delivery.toJson(),
          userId: ref.read(sessionProvider).user?.id,
        );
    ref.invalidate(_deliveriesProvider);
  }

  Future<void> _updateStatus(WidgetRef ref, Delivery d, String status) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.deliveries)..where((t) => t.id.equals(d.id))).write(
      DeliveriesCompanion(
        status: Value(status),
        deliveredAt: status == 'delivered'
            ? Value(DateTime.now())
            : const Value.absent(),
        amountCollected: status == 'delivered'
            ? Value(d.amountToCollect)
            : const Value.absent(),
      ),
    );
    final updated = await (db.select(
      db.deliveries,
    )..where((row) => row.id.equals(d.id))).getSingle();
    await ref
        .read(syncEngineProvider)
        .enqueue(
          businessId: d.businessId,
          entityType: 'delivery',
          entityId: d.id,
          operation: 'update',
          payload: updated.toJson(),
          userId: ref.read(sessionProvider).user?.id,
        );
    ref.invalidate(_deliveriesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_deliveriesProvider);
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.tr('Livraisons', 'Deliveries'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, ref),
        child: const Icon(Icons.add),
      ),
      body: async.when(
        loading: () => const KumbaSkeletonList(),
        error: (e, _) => KumbaErrorState(message: e.toString()),
        data: (list) {
          if (list.isEmpty) {
            return KumbaEmptyState(
              title: 'Aucune livraison',
              actionLabel: 'Planifier',
              onAction: () => _add(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = list[i];
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              d.customerName,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          KumbaStatusBadge(
                            label: d.status,
                            color: d.status == 'delivered'
                                ? AppColors.kpiSales
                                : d.status == 'en_route'
                                ? AppColors.fab
                                : AppColors.kpiDebt,
                          ),
                        ],
                      ),
                      if (d.address != null) Text(d.address!),
                      Text(d.reference),
                      if (d.amountToCollect > 0)
                        Text(
                          'À encaisser : ${MoneyFormat.format(d.amountToCollect)}',
                        ),
                      if (d.scheduledAt != null)
                        Text(DateFormat('dd/MM HH:mm').format(d.scheduledAt!)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (d.customerPhone != null)
                            TextButton.icon(
                              onPressed: () => launchUrl(
                                Uri.parse('tel:${d.customerPhone}'),
                              ),
                              icon: const Icon(Icons.phone, size: 18),
                              label: Text(S.tr('Appeler', 'Call')),
                            ),
                          if (d.status != 'delivered')
                            TextButton(
                              onPressed: () =>
                                  _updateStatus(ref, d, 'en_route'),
                              child: Text(S.tr('En route', 'On the way')),
                            ),
                          if (d.status != 'delivered')
                            TextButton(
                              onPressed: () =>
                                  _updateStatus(ref, d, 'delivered'),
                              child: Text(S.tr('Livrée', 'Delivered')),
                            ),
                        ],
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
