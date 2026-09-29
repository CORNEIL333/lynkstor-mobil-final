import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/id_generator.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_states.dart';
import '../../l10n/app_strings.dart';

final _attendanceProvider = FutureProvider.autoDispose<List<AttendanceRecord>>((
  ref,
) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  final db = ref.watch(databaseProvider);
  return (db.select(db.attendanceRecords)
        ..where((t) => t.businessId.equals(business.id))
        ..orderBy([(t) => OrderingTerm.desc(t.recordedAt)])
        ..limit(50))
      .get();
});

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  Future<void> _punch(WidgetRef ref, String type) async {
    final session = ref.read(sessionProvider);
    if (session.business == null || session.user == null) return;
    final id = IdGenerator.uuid();
    await ref
        .read(databaseProvider)
        .into(ref.read(databaseProvider).attendanceRecords)
        .insert(
          AttendanceRecordsCompanion.insert(
            id: id,
            businessId: session.business!.id,
            userId: session.user!.id,
            type: type,
            method: const Value('pin'),
            recordedAt: DateTime.now(),
          ),
        );
    final db = ref.read(databaseProvider);
    final record = await (db.select(
      db.attendanceRecords,
    )..where((row) => row.id.equals(id))).getSingle();
    await ref
        .read(syncEngineProvider)
        .enqueue(
          businessId: session.business!.id,
          entityType: 'attendance',
          entityId: id,
          operation: 'create',
          payload: record.toJson(),
          userId: session.user!.id,
        );
    ref.invalidate(_attendanceProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_attendanceProvider);
    final user = ref.watch(sessionProvider).user;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.tr('Pointage', 'Attendance'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Bonjour ${user?.fullName ?? ''}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Pointez votre arrivée ou départ. Aucun suivi GPS permanent.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: KumbaButton(
                  label: 'Arrivée',
                  icon: Icons.login_rounded,
                  onPressed: () => _punch(ref, 'check_in'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KumbaButton(
                  label: 'Départ',
                  variant: KumbaButtonVariant.outline,
                  icon: Icons.logout_rounded,
                  onPressed: () => _punch(ref, 'check_out'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Historique récent',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          async.when(
            loading: () => const KumbaLoading(),
            error: (e, _) => Text(e.toString()),
            data: (list) {
              if (list.isEmpty) {
                return Text(
                  S.tr(
                    'Aucun pointage enregistré.',
                    'No attendance record yet.',
                  ),
                );
              }
              return Column(
                children: list
                    .map(
                      (r) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          r.type == 'check_in' ? Icons.login : Icons.logout,
                          color: r.type == 'check_in'
                              ? AppColors.forest
                              : AppColors.terracotta,
                        ),
                        title: Text(
                          r.type == 'check_in' ? 'Arrivée' : 'Départ',
                        ),
                        subtitle: Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(r.recordedAt),
                        ),
                        trailing: Text(r.method),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
