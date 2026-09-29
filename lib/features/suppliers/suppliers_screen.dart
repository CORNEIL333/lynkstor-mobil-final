import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../l10n/app_strings.dart';

final _suppliersProvider = FutureProvider.autoDispose<List<Supplier>>((
  ref,
) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  return ref.watch(databaseProvider).getSuppliers(business.id);
});

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
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
              'Nouveau fournisseur',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            KumbaTextField(controller: name, label: 'Nom'),
            const SizedBox(height: 12),
            KumbaTextField(
              controller: phone,
              label: 'Téléphone',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            KumbaButton(
              label: 'Enregistrer',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final business = ref.read(sessionProvider).business!;
    final now = DateTime.now();
    final id = IdGenerator.uuid();
    await ref
        .read(databaseProvider)
        .into(ref.read(databaseProvider).suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: id,
            businessId: business.id,
            name: name.text.trim(),
            phone: Value(phone.text.isEmpty ? null : phone.text),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final db = ref.read(databaseProvider);
    final supplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(id))).getSingle();
    await ref
        .read(syncEngineProvider)
        .enqueue(
          businessId: business.id,
          entityType: 'supplier',
          entityId: id,
          operation: 'create',
          payload: supplier.toJson(),
          userId: ref.read(sessionProvider).user?.id,
        );
    ref.invalidate(_suppliersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_suppliersProvider);
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.tr('Fournisseurs', 'Suppliers'))),
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
              title: 'Aucun fournisseur',
              actionLabel: 'Ajouter',
              onAction: () => _add(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = list[i];
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                title: Text(s.name),
                subtitle: Text(s.phone ?? ''),
                trailing: s.balance > 0
                    ? Text(MoneyFormat.format(s.balance))
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
