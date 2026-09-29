import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/permissions/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/id_generator.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../l10n/app_strings.dart';
import 'package:drift/drift.dart' hide Column;

final _employeesProvider = FutureProvider.autoDispose<List<User>>((ref) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  return ref.watch(databaseProvider).getUsersForBusiness(business.id);
});

class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    var role = AppRole.seller;

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
                S.tr('Nouvel employé', 'New employee'),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              KumbaTextField(controller: name, label: 'Nom complet'),
              const SizedBox(height: 12),
              KumbaTextField(
                controller: phone,
                label: 'Téléphone',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AppRole>(
                initialValue: role,
                items: AppRole.values
                    .where((r) => r != AppRole.owner)
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(RolePermissions.label(r)),
                      ),
                    )
                    .toList(),
                onChanged: (r) => setModal(() => role = r!),
                decoration: InputDecoration(labelText: S.tr('Rôle', 'Role')),
              ),
              const SizedBox(height: 16),
              KumbaButton(
                label: 'Ajouter',
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;

    final business = ref.read(sessionProvider).business!;
    final now = DateTime.now();
    final id = IdGenerator.uuid();
    await ref
        .read(databaseProvider)
        .insertUser(
          UsersCompanion.insert(
            id: id,
            businessId: business.id,
            fullName: name.text.trim(),
            phone: Value(phone.text.isEmpty ? null : phone.text),
            role: Value(role.name),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final db = ref.read(databaseProvider);
    final user = await db.getUser(id);
    if (user != null) {
      await ref
          .read(syncEngineProvider)
          .enqueue(
            businessId: business.id,
            entityType: 'user',
            entityId: id,
            operation: 'create',
            payload: user.toJson(),
            userId: ref.read(sessionProvider).user?.id,
          );
    }
    ref.invalidate(_employeesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_employeesProvider);
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.tr('Employés', 'Employees'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, ref),
        child: const Icon(Icons.person_add),
      ),
      body: async.when(
        loading: () => const KumbaSkeletonList(),
        error: (e, _) => KumbaErrorState(message: e.toString()),
        data: (list) {
          if (list.isEmpty) {
            return KumbaEmptyState(
              title: S.tr('Aucun employé', 'No employees'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final u = list[i];
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                leading: CircleAvatar(child: Text(u.fullName[0].toUpperCase())),
                title: Text(u.fullName),
                subtitle: Text(
                  RolePermissions.label(RolePermissions.parseRole(u.role)),
                ),
                trailing: Text(u.status),
              );
            },
          );
        },
      ),
    );
  }
}
