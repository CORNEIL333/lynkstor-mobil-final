import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/permissions/permission_guard.dart';
import '../../core/permissions/permissions.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/utils/id_generator.dart';
import '../../core/logging/app_logger.dart';
import 'analytics_service.dart';

class CustomerInput {
  CustomerInput({
    required this.name,
    this.phone,
    this.neighborhood,
    this.email,
    this.creditLimit = 0,
    this.note,
    this.photoPath,
  });

  final String name;
  final String? phone;
  final String? neighborhood;
  final String? email;
  final double creditLimit;
  final String? note;
  final String? photoPath;
}

class CustomerService {
  CustomerService({required this.db, required this.sync});

  final AppDatabase db;
  final SyncEngine sync;

  Future<List<Customer>> list(String businessId, {String? query}) =>
      db.getCustomers(businessId, query: query);

  Future<Customer?> byId(String id) => db.getCustomer(id);

  Future<List<Customer>> debtors(String businessId) =>
      db.getDebtors(businessId);

  Future<Customer> create(
    String businessId,
    CustomerInput input, {
    String? userId,
    String userRole = 'owner',
  }) async {
    PermissionGuard.of(userRole).require(AppPermission.customersManage);
    if (input.name.trim().isEmpty) {
      throw const ValidationException('Le nom du client est obligatoire.');
    }
    if (!input.creditLimit.isFinite || input.creditLimit < 0) {
      throw const ValidationException(
        'La limite de crédit doit être un nombre positif.',
      );
    }
    final now = DateTime.now();
    final id = IdGenerator.uuid();
    await db.insertCustomer(
      CustomersCompanion.insert(
        id: id,
        businessId: businessId,
        name: input.name.trim(),
        phone: Value(input.phone),
        neighborhood: Value(input.neighborhood),
        email: Value(input.email),
        creditLimit: Value(input.creditLimit),
        note: Value(input.note),
        photoPath: Value(input.photoPath),
        createdAt: now,
        updatedAt: now,
      ),
    );
    final created = (await db.getCustomer(id))!;
    await sync.enqueue(
      businessId: businessId,
      entityType: 'customer',
      entityId: id,
      operation: 'create',
      payload: created.toJson(),
      userId: userId,
    );
    AppLogger.audit('customer.created', userId: userId, entityId: id);
    AppAnalytics.track('customer.created');
    return created;
  }

  /// Encaissement de dette — le solde ne change QUE via un mouvement.
  Future<Payment> collectDebt({
    required String businessId,
    required String customerId,
    required double amount,
    required String method,
    String? methodRef,
    String? note,
    String? userId,
    String userRole = 'owner',
  }) async {
    PermissionGuard.of(userRole).require(AppPermission.debtsCollect);
    if (!amount.isFinite || amount <= 0) {
      throw const ValidationException('Le montant doit être supérieur à zéro.');
    }
    if (method.trim().isEmpty || method == 'credit') {
      throw const ValidationException('Le moyen de paiement est invalide.');
    }
    final customer = await db.getCustomer(customerId);
    if (customer == null) throw const NotFoundException('Client introuvable.');
    if (customer.businessId != businessId) {
      throw const ValidationException(
        'Ce client n’appartient pas à ce commerce.',
      );
    }
    if (amount > customer.balance) {
      throw ValidationException(
        'Le montant (${amount.toStringAsFixed(0)}) dépasse la dette (${customer.balance.toStringAsFixed(0)}).',
      );
    }

    final now = DateTime.now();
    final paymentId = IdGenerator.uuid();
    final newBalance = customer.balance - amount;

    await db.transaction(() async {
      await db
          .into(db.payments)
          .insertOnConflictUpdate(
            PaymentsCompanion.insert(
              id: paymentId,
              businessId: businessId,
              reference: IdGenerator.businessRef('ENC'),
              type: 'debt',
              relatedType: const Value('customer'),
              relatedId: Value(customerId),
              customerId: Value(customerId),
              amount: amount,
              method: method,
              methodRef: Value(methodRef),
              note: Value(note),
              userId: Value(userId),
              paidAt: now,
              createdAt: now,
              idempotencyKey: IdGenerator.uuid(),
            ),
          );

      await db
          .into(db.debtMovements)
          .insertOnConflictUpdate(
            DebtMovementsCompanion.insert(
              id: IdGenerator.uuid(),
              businessId: businessId,
              customerId: customerId,
              type: 'payment',
              amount: -amount,
              balanceBefore: customer.balance,
              balanceAfter: newBalance,
              relatedType: const Value('payment'),
              relatedId: Value(paymentId),
              note: Value(note),
              userId: Value(userId),
              createdAt: now,
            ),
          );

      await db.updateCustomerRow(
        customer.copyWith(
          balance: newBalance,
          lastActivityAt: Value(now),
          updatedAt: now,
          version: customer.version + 1,
        ),
      );

      await db.insertAudit(
        AuditLogsCompanion.insert(
          id: IdGenerator.uuid(),
          businessId: businessId,
          userId: Value(userId),
          action: 'debt.collected',
          entityType: const Value('customer'),
          entityId: Value(customerId),
          detailsJson: Value('{"amount":$amount,"method":"$method"}'),
          createdAt: now,
        ),
      );
    });

    final payment = (await (db.select(
      db.payments,
    )..where((t) => t.id.equals(paymentId))).getSingle());
    final movements = await (db.select(
      db.debtMovements,
    )..where((t) => t.relatedId.equals(paymentId))).get();
    final updatedCustomer = (await db.getCustomer(customerId))!;
    await sync.enqueue(
      businessId: businessId,
      entityType: 'payment',
      entityId: paymentId,
      operation: 'create',
      payload: {
        'payment': payment.toJson(),
        'debtMovements': movements.map((row) => row.toJson()).toList(),
        'customer': updatedCustomer.toJson(),
        'version': 1,
      },
      userId: userId,
    );

    AppLogger.audit('debt.collected', userId: userId, entityId: customerId);
    AppAnalytics.track('debt.collected');
    return payment;
  }

  Future<List<DebtMovement>> movements(String customerId) =>
      db.getDebtMovements(customerId);
}
