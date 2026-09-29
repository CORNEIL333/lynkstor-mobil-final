import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/permissions/permission_guard.dart';
import '../../core/permissions/permissions.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/utils/id_generator.dart';
import '../../core/logging/app_logger.dart';
import 'analytics_service.dart';

class ExpenseInput {
  ExpenseInput({
    required this.amount,
    this.categoryId,
    this.categoryName,
    this.account = 'cash',
    this.description,
    this.photoPath,
    DateTime? expenseDate,
  }) : expenseDate = expenseDate ?? DateTime.now();

  final double amount;
  final String? categoryId;
  final String? categoryName;
  final String account;
  final String? description;
  final String? photoPath;
  final DateTime expenseDate;
}

class ExpenseService {
  ExpenseService({required this.db, required this.sync});

  final AppDatabase db;
  final SyncEngine sync;

  Future<List<Expense>> list(
    String businessId, {
    DateTime? from,
    DateTime? to,
  }) => db.getExpenses(businessId, from: from, to: to);

  Future<List<ExpenseCategory>> categories(String businessId) =>
      (db.select(db.expenseCategories)..where(
            (t) => t.businessId.equals(businessId) & t.isDeleted.equals(false),
          ))
          .get();

  Future<Expense> create(
    String businessId,
    ExpenseInput input, {
    String? userId,
    String userRole = 'owner',
  }) async {
    PermissionGuard.of(userRole).require(AppPermission.expensesCreate);
    if (input.amount <= 0) {
      throw const ValidationException(
        'Le montant de la dépense doit être supérieur à zéro.',
      );
    }

    final now = DateTime.now();
    final id = IdGenerator.uuid();

    await db.transaction(() async {
      await db
          .into(db.expenses)
          .insertOnConflictUpdate(
            ExpensesCompanion.insert(
              id: id,
              businessId: businessId,
              reference: IdGenerator.businessRef('DEP'),
              amount: input.amount,
              categoryId: Value(input.categoryId),
              categoryName: Value(input.categoryName),
              account: Value(input.account),
              description: Value(input.description),
              photoPath: Value(input.photoPath),
              userId: Value(userId),
              expenseDate: input.expenseDate,
              createdAt: now,
              idempotencyKey: IdGenerator.uuid(),
            ),
          );

      await db.insertAudit(
        AuditLogsCompanion.insert(
          id: IdGenerator.uuid(),
          businessId: businessId,
          userId: Value(userId),
          action: 'expense.created',
          entityType: const Value('expense'),
          entityId: Value(id),
          detailsJson: Value('{"amount":${input.amount}}'),
          createdAt: now,
        ),
      );
    });

    final created = (await (db.select(
      db.expenses,
    )..where((t) => t.id.equals(id))).getSingle());
    await sync.enqueue(
      businessId: businessId,
      entityType: 'expense',
      entityId: id,
      operation: 'create',
      payload: created.toJson(),
      userId: userId,
    );

    AppLogger.audit('expense.created', userId: userId, entityId: id);
    AppAnalytics.track(
      'expense.created',
      properties: {'amount': input.amount},
    );
    return created;
  }
}
