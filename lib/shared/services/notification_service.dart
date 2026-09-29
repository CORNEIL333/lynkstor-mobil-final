import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/utils/id_generator.dart';

class NotificationService {
  NotificationService({required this.db});

  final AppDatabase db;

  Stream<List<AppNotification>> watch(String businessId) {
    final query = db.select(db.appNotifications)
      ..where(
        (t) => t.businessId.equals(businessId) & t.isArchived.equals(false),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Stream<int> watchUnreadCount(String businessId) {
    final count = db.appNotifications.id.count();
    final query = db.selectOnly(db.appNotifications)
      ..addColumns([count])
      ..where(
        db.appNotifications.businessId.equals(businessId) &
            db.appNotifications.isRead.equals(false) &
            db.appNotifications.isArchived.equals(false),
      );
    return query.watchSingle().map((row) => row.read(count) ?? 0);
  }

  Future<AppNotification?> create({
    required String businessId,
    required String type,
    required String titleKey,
    required String bodyKey,
    Map<String, Object?> args = const {},
    String severity = 'info',
    String? entityType,
    String? entityId,
    String? actionType,
    Map<String, Object?>? actionPayload,
    String? dedupeKey,
    Duration dedupeWindow = const Duration(hours: 24),
  }) async {
    final now = DateTime.now();
    if (dedupeKey != null) {
      final existing =
          await (db.select(db.appNotifications)
                ..where(
                  (t) =>
                      t.businessId.equals(businessId) &
                      t.dedupeKey.equals(dedupeKey) &
                      t.createdAt.isBiggerOrEqualValue(
                        now.subtract(dedupeWindow),
                      ),
                )
                ..limit(1))
              .getSingleOrNull();
      if (existing != null) return null;
    }

    final id = IdGenerator.uuid();
    await db
        .into(db.appNotifications)
        .insertOnConflictUpdate(
          AppNotificationsCompanion.insert(
            id: id,
            businessId: businessId,
            type: type,
            severity: Value(severity),
            titleKey: titleKey,
            bodyKey: bodyKey,
            argsJson: Value(jsonEncode(args)),
            entityType: Value(entityType),
            entityId: Value(entityId),
            actionType: Value(actionType),
            actionPayloadJson: Value(
              actionPayload == null ? null : jsonEncode(actionPayload),
            ),
            dedupeKey: Value(dedupeKey),
            createdAt: now,
          ),
        );
    return (await (db.select(
      db.appNotifications,
    )..where((t) => t.id.equals(id))).getSingle());
  }

  Future<void> markRead(String id) async {
    await (db.update(db.appNotifications)..where((t) => t.id.equals(id))).write(
      AppNotificationsCompanion(
        isRead: const Value(true),
        readAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markAllRead(String businessId) async {
    await (db.update(db.appNotifications)..where(
          (t) => t.businessId.equals(businessId) & t.isRead.equals(false),
        ))
        .write(
          AppNotificationsCompanion(
            isRead: const Value(true),
            readAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> archive(String id) async {
    await (db.update(db.appNotifications)..where((t) => t.id.equals(id))).write(
      const AppNotificationsCompanion(isArchived: Value(true)),
    );
  }

  Future<void> deleteRead(String businessId) async {
    await (db.delete(db.appNotifications)..where(
          (t) => t.businessId.equals(businessId) & t.isRead.equals(true),
        ))
        .go();
  }
}
