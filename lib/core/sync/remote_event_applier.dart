import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../logging/app_logger.dart';
import 'http_sync_client.dart';

/// Applies cloud events directly to SQLite without enqueueing them again.
class RemoteEventApplier {
  const RemoteEventApplier(this.db);

  final AppDatabase db;

  Future<void> apply(RemoteSyncEvent event) async {
    if (event.operation == 'delete') {
      await _applyDelete(event);
      return;
    }
    switch (event.entityType) {
      case 'business':
        await _applyBusiness(event);
      case 'product':
        await _applyProduct(event);
      case 'customer':
        await _applyCustomer(event);
      case 'expense':
        await _applyExpense(event);
      case 'payment':
        await _applyPaymentBundle(event);
      case 'sale':
        await _applySaleBundle(event);
      case 'sale_return':
        await _applyReturnBundle(event);
      case 'supplier':
        await _applySupplier(event);
      case 'purchase':
        await _applyPurchaseBundle(event);
      case 'quote':
        await _applyQuoteBundle(event);
      case 'invoice':
        await _applyInvoiceBundle(event);
      case 'delivery':
        await _applyDelivery(event);
      case 'user':
        await _applyUser(event);
      case 'attendance':
        await _applyAttendance(event);
      case 'inventory':
        await _applyInventoryBundle(event);
      case 'automation_rule':
        await _applyAutomationRule(event);
      case 'automation_run':
        await _applyAutomationRun(event);
      case 'supplier_product':
        await _applySupplierProduct(event);
      default:
        AppLogger.w(
          'Remote sync event ignored: unsupported type ${event.entityType}',
        );
    }
  }

  Future<void> _applySupplier(RemoteSyncEvent event) async {
    final value = _data(event)..['businessId'] = event.businessId;
    await db
        .into(db.suppliers)
        .insertOnConflictUpdate(Supplier.fromJson(value));
  }

  Future<void> _applyPurchaseBundle(RemoteSyncEvent event) async {
    final raw = event.payload['purchase'];
    if (raw is! Map) return;
    await db.transaction(() async {
      final value = Map<String, dynamic>.from(raw)
        ..['businessId'] = event.businessId;
      await db
          .into(db.purchases)
          .insertOnConflictUpdate(Purchase.fromJson(value));
      await _insertBundleRows(
        event.payload['items'],
        (value) => db
            .into(db.purchaseItems)
            .insertOnConflictUpdate(PurchaseItem.fromJson(value)),
      );
    });
  }

  Future<void> _applyQuoteBundle(RemoteSyncEvent event) async {
    final raw = event.payload['quote'];
    if (raw is! Map) return;
    await db.transaction(() async {
      final value = Map<String, dynamic>.from(raw)
        ..['businessId'] = event.businessId;
      await db.into(db.quotes).insertOnConflictUpdate(Quote.fromJson(value));
      await _insertBundleRows(
        event.payload['items'],
        (value) => db
            .into(db.quoteItems)
            .insertOnConflictUpdate(QuoteItem.fromJson(value)),
      );
    });
  }

  Future<void> _applyInvoiceBundle(RemoteSyncEvent event) async {
    final raw = event.payload['invoice'];
    if (raw is! Map) return;
    await db.transaction(() async {
      final value = Map<String, dynamic>.from(raw)
        ..['businessId'] = event.businessId;
      await db
          .into(db.invoices)
          .insertOnConflictUpdate(Invoice.fromJson(value));
      await _insertBundleRows(
        event.payload['items'],
        (value) => db
            .into(db.invoiceItems)
            .insertOnConflictUpdate(InvoiceItem.fromJson(value)),
      );
    });
  }

  Future<void> _applyDelivery(RemoteSyncEvent event) async {
    final value = _data(event)..['businessId'] = event.businessId;
    await db
        .into(db.deliveries)
        .insertOnConflictUpdate(Delivery.fromJson(value));
  }

  Future<void> _applyUser(RemoteSyncEvent event) async {
    final value = _data(event)..['businessId'] = event.businessId;
    await db.into(db.users).insertOnConflictUpdate(User.fromJson(value));
  }

  Future<void> _applyAttendance(RemoteSyncEvent event) async {
    final value = _data(event)..['businessId'] = event.businessId;
    await db
        .into(db.attendanceRecords)
        .insertOnConflictUpdate(AttendanceRecord.fromJson(value));
  }

  Future<void> _applyInventoryBundle(RemoteSyncEvent event) async {
    final raw = event.payload['session'];
    if (raw is! Map) return;
    await db.transaction(() async {
      final value = Map<String, dynamic>.from(raw)
        ..['businessId'] = event.businessId;
      await db
          .into(db.inventorySessions)
          .insertOnConflictUpdate(InventorySession.fromJson(value));
      await _insertBundleRows(
        event.payload['lines'],
        (value) => db
            .into(db.inventoryLines)
            .insertOnConflictUpdate(InventoryLine.fromJson(value)),
      );
    });
  }

  Future<void> _applyAutomationRule(RemoteSyncEvent event) async {
    final value = _data(event)..['businessId'] = event.businessId;
    await db
        .into(db.automationRules)
        .insertOnConflictUpdate(AutomationRule.fromJson(value));
  }

  Future<void> _applyAutomationRun(RemoteSyncEvent event) async {
    final value = _data(event)..['businessId'] = event.businessId;
    await db
        .into(db.automationRuns)
        .insertOnConflictUpdate(AutomationRun.fromJson(value));
  }

  Future<void> _applySupplierProduct(RemoteSyncEvent event) async {
    final value = _data(event)..['businessId'] = event.businessId;
    await db
        .into(db.supplierProducts)
        .insertOnConflictUpdate(SupplierProduct.fromJson(value));
  }

  Map<String, dynamic> _data(RemoteSyncEvent event) {
    final nested = event.payload['data'];
    return nested is Map
        ? Map<String, dynamic>.from(nested)
        : Map<String, dynamic>.from(event.payload);
  }

  Future<void> _applyBusiness(RemoteSyncEvent event) async {
    final existing = await db.getBusiness(event.businessId);
    final value = {
      if (existing != null) ...existing.toJson(),
      ..._data(event),
      'id': event.businessId,
      'version': event.entityVersion,
      'updatedAt': event.createdAt.toIso8601String(),
    };
    if (value['name'] == null ||
        value['ownerName'] == null ||
        value['phone'] == null) {
      AppLogger.w('Incomplete remote business ${event.entityId} ignored');
      return;
    }
    await db
        .into(db.businesses)
        .insertOnConflictUpdate(Business.fromJson(value));
  }

  Future<void> _applyProduct(RemoteSyncEvent event) async {
    final existing = await db.getProduct(event.entityId);
    if (existing != null && existing.version > event.entityVersion) return;
    final incoming = _data(event);
    if (existing == null) {
      final name = incoming['name'];
      if (name is! String || name.trim().isEmpty) {
        AppLogger.w('Incomplete remote product ${event.entityId} ignored');
        return;
      }
      await db
          .into(db.products)
          .insertOnConflictUpdate(
            ProductsCompanion.insert(
              id: event.entityId,
              businessId: event.businessId,
              name: name,
              description: Value(incoming['description'] as String?),
              categoryId: Value(incoming['categoryId'] as String?),
              sku: Value(incoming['sku'] as String?),
              barcode: Value(incoming['barcode'] as String?),
              unit: Value(incoming['unit'] as String? ?? 'pièce'),
              salePrice: Value(
                (incoming['salePrice'] as num?)?.toDouble() ?? 0,
              ),
              costPrice: Value(
                (incoming['costPrice'] as num?)?.toDouble() ?? 0,
              ),
              wholesalePrice: Value(
                (incoming['wholesalePrice'] as num?)?.toDouble(),
              ),
              stockQty: Value((incoming['stockQty'] as num?)?.toDouble() ?? 0),
              lowStockThreshold: Value(
                (incoming['lowStockThreshold'] as num?)?.toDouble() ?? 5,
              ),
              trackStock: Value(incoming['trackStock'] as bool? ?? true),
              isService: Value(incoming['isService'] as bool? ?? false),
              isFavorite: Value(incoming['isFavorite'] as bool? ?? false),
              isActive: Value(incoming['isActive'] as bool? ?? true),
              photoPath: Value(incoming['photoPath'] as String?),
              expiryDate: Value(incoming['expiryDate'] as String?),
              lotNumber: Value(incoming['lotNumber'] as String?),
              createdAt: _date(incoming['createdAt']) ?? event.createdAt,
              updatedAt: _date(incoming['updatedAt']) ?? event.createdAt,
              version: Value(event.entityVersion),
              isDeleted: Value(incoming['isDeleted'] as bool? ?? false),
            ),
          );
      return;
    }
    final value = {
      ...existing.toJson(),
      ...incoming,
      'id': event.entityId,
      'businessId': event.businessId,
      'version': event.entityVersion,
      'updatedAt': event.createdAt.toIso8601String(),
      'createdAt': existing.createdAt.toIso8601String(),
    };
    if (value['name'] == null) {
      AppLogger.w('Incomplete remote product ${event.entityId} ignored');
      return;
    }
    await db.into(db.products).insertOnConflictUpdate(Product.fromJson(value));
  }

  Future<void> _applyCustomer(RemoteSyncEvent event) async {
    final existing = await db.getCustomer(event.entityId);
    if (existing != null && existing.version > event.entityVersion) return;
    final incoming = _data(event);
    if (existing == null) {
      final name = incoming['name'];
      if (name is! String || name.trim().isEmpty) {
        AppLogger.w('Incomplete remote customer ${event.entityId} ignored');
        return;
      }
      await db
          .into(db.customers)
          .insertOnConflictUpdate(
            CustomersCompanion.insert(
              id: event.entityId,
              businessId: event.businessId,
              name: name,
              phone: Value(incoming['phone'] as String?),
              neighborhood: Value(incoming['neighborhood'] as String?),
              email: Value(incoming['email'] as String?),
              creditLimit: Value(
                (incoming['creditLimit'] as num?)?.toDouble() ?? 0,
              ),
              balance: Value((incoming['balance'] as num?)?.toDouble() ?? 0),
              note: Value(incoming['note'] as String?),
              photoPath: Value(incoming['photoPath'] as String?),
              createdAt: _date(incoming['createdAt']) ?? event.createdAt,
              updatedAt: _date(incoming['updatedAt']) ?? event.createdAt,
              version: Value(event.entityVersion),
              isDeleted: Value(incoming['isDeleted'] as bool? ?? false),
            ),
          );
      return;
    }
    final value = {
      ...existing.toJson(),
      ...incoming,
      'id': event.entityId,
      'businessId': event.businessId,
      'version': event.entityVersion,
      'updatedAt': event.createdAt.toIso8601String(),
      'createdAt': existing.createdAt.toIso8601String(),
    };
    if (value['name'] == null) {
      AppLogger.w('Incomplete remote customer ${event.entityId} ignored');
      return;
    }
    await db
        .into(db.customers)
        .insertOnConflictUpdate(Customer.fromJson(value));
  }

  Future<void> _applyExpense(RemoteSyncEvent event) async {
    final existing = await (db.select(
      db.expenses,
    )..where((row) => row.id.equals(event.entityId))).getSingleOrNull();
    if (existing != null && existing.version > event.entityVersion) return;
    final incoming = _data(event);
    if (existing == null) {
      final amount = incoming['amount'];
      final categoryName = incoming['categoryName'] ?? incoming['category'];
      if (amount is! num || categoryName is! String) {
        AppLogger.w('Incomplete remote expense ${event.entityId} ignored');
        return;
      }
      await db
          .into(db.expenses)
          .insertOnConflictUpdate(
            ExpensesCompanion.insert(
              id: event.entityId,
              businessId: event.businessId,
              reference:
                  incoming['reference'] as String? ?? 'SYNC-${event.entityId}',
              categoryId: Value(incoming['categoryId'] as String?),
              categoryName: Value(categoryName),
              amount: amount.toDouble(),
              description: Value(incoming['description'] as String?),
              account: Value(incoming['account'] as String? ?? 'cash'),
              photoPath: Value(incoming['photoPath'] as String?),
              status: Value(incoming['status'] as String? ?? 'paid'),
              userId: Value(incoming['userId'] as String?),
              expenseDate: _date(incoming['expenseDate']) ?? event.createdAt,
              createdAt: _date(incoming['createdAt']) ?? event.createdAt,
              idempotencyKey: incoming['idempotencyKey'] as String? ?? event.id,
              version: Value(event.entityVersion),
              isDeleted: Value(incoming['isDeleted'] as bool? ?? false),
            ),
          );
      return;
    }
    final value = {
      ...existing.toJson(),
      ...incoming,
      'id': event.entityId,
      'businessId': event.businessId,
      'version': event.entityVersion,
      'createdAt': existing.createdAt.toIso8601String(),
    };
    if (value['categoryName'] == null || value['amount'] == null) {
      AppLogger.w('Incomplete remote expense ${event.entityId} ignored');
      return;
    }
    await db.into(db.expenses).insertOnConflictUpdate(Expense.fromJson(value));
  }

  Future<void> _applyPaymentBundle(RemoteSyncEvent event) async {
    final payment = event.payload['payment'];
    if (payment is! Map) {
      AppLogger.w('Legacy payment ${event.entityId} has no complete bundle');
      return;
    }
    await db.transaction(() async {
      final value = Map<String, dynamic>.from(payment)
        ..['businessId'] = event.businessId;
      await db
          .into(db.payments)
          .insertOnConflictUpdate(Payment.fromJson(value));
      await _insertBundleRows(
        event.payload['debtMovements'],
        (value) => db
            .into(db.debtMovements)
            .insertOnConflictUpdate(
              DebtMovement.fromJson(
                value,
              ).copyWith(businessId: event.businessId),
            ),
      );
      final customer = event.payload['customer'];
      if (customer is Map) {
        final value = Map<String, dynamic>.from(customer)
          ..['businessId'] = event.businessId;
        await db
            .into(db.customers)
            .insertOnConflictUpdate(Customer.fromJson(value));
      }
    });
  }

  Future<void> _applySaleBundle(RemoteSyncEvent event) async {
    final sale = event.payload['sale'];
    if (sale is! Map) {
      AppLogger.w('Legacy sale ${event.entityId} has no complete bundle');
      return;
    }
    await db.transaction(() async {
      final value = Map<String, dynamic>.from(sale)
        ..['businessId'] = event.businessId;
      await db.into(db.sales).insertOnConflictUpdate(Sale.fromJson(value));
      await _insertBundleRows(
        event.payload['items'],
        (value) => db
            .into(db.saleItems)
            .insertOnConflictUpdate(SaleItem.fromJson(value)),
      );
      await _insertBundleRows(event.payload['payments'], (value) {
        value['businessId'] = event.businessId;
        return db
            .into(db.payments)
            .insertOnConflictUpdate(Payment.fromJson(value));
      });
      await _insertBundleRows(event.payload['stockMovements'], (value) {
        value['businessId'] = event.businessId;
        return db
            .into(db.stockMovements)
            .insertOnConflictUpdate(StockMovement.fromJson(value));
      });
      await _insertBundleRows(event.payload['debtMovements'], (value) {
        value['businessId'] = event.businessId;
        return db
            .into(db.debtMovements)
            .insertOnConflictUpdate(DebtMovement.fromJson(value));
      });
      await _insertBundleRows(event.payload['products'], (value) {
        value['businessId'] = event.businessId;
        return db
            .into(db.products)
            .insertOnConflictUpdate(Product.fromJson(value));
      });
      final customer = event.payload['customer'];
      if (customer is Map) {
        final value = Map<String, dynamic>.from(customer)
          ..['businessId'] = event.businessId;
        await db
            .into(db.customers)
            .insertOnConflictUpdate(Customer.fromJson(value));
      }
    });
  }

  Future<void> _applyReturnBundle(RemoteSyncEvent event) async {
    final saleReturn = event.payload['saleReturn'];
    if (saleReturn is! Map) {
      AppLogger.w('Legacy return ${event.entityId} has no complete bundle');
      return;
    }
    await db.transaction(() async {
      final value = Map<String, dynamic>.from(saleReturn)
        ..['businessId'] = event.businessId;
      await db
          .into(db.saleReturns)
          .insertOnConflictUpdate(SaleReturn.fromJson(value));
      await _insertBundleRows(
        event.payload['items'],
        (value) => db
            .into(db.saleReturnItems)
            .insertOnConflictUpdate(SaleReturnItem.fromJson(value)),
      );
      await _insertBundleRows(event.payload['stockMovements'], (value) {
        value['businessId'] = event.businessId;
        return db
            .into(db.stockMovements)
            .insertOnConflictUpdate(StockMovement.fromJson(value));
      });
      await _insertBundleRows(event.payload['payments'], (value) {
        value['businessId'] = event.businessId;
        return db
            .into(db.payments)
            .insertOnConflictUpdate(Payment.fromJson(value));
      });
      await _insertBundleRows(event.payload['debtMovements'], (value) {
        value['businessId'] = event.businessId;
        return db
            .into(db.debtMovements)
            .insertOnConflictUpdate(DebtMovement.fromJson(value));
      });
      await _insertBundleRows(event.payload['products'], (value) {
        value['businessId'] = event.businessId;
        return db
            .into(db.products)
            .insertOnConflictUpdate(Product.fromJson(value));
      });
      final sale = event.payload['sale'];
      if (sale is Map) {
        final value = Map<String, dynamic>.from(sale)
          ..['businessId'] = event.businessId;
        await db.into(db.sales).insertOnConflictUpdate(Sale.fromJson(value));
      }
      final customer = event.payload['customer'];
      if (customer is Map) {
        final value = Map<String, dynamic>.from(customer)
          ..['businessId'] = event.businessId;
        await db
            .into(db.customers)
            .insertOnConflictUpdate(Customer.fromJson(value));
      }
    });
  }

  Future<void> _insertBundleRows(
    Object? rawRows,
    Future<void> Function(Map<String, dynamic>) insert,
  ) async {
    if (rawRows is! List) return;
    for (final raw in rawRows) {
      if (raw is Map) await insert(Map<String, dynamic>.from(raw));
    }
  }

  Future<void> _applyDelete(RemoteSyncEvent event) async {
    final now = event.createdAt;
    switch (event.entityType) {
      case 'product':
        await (db.update(
          db.products,
        )..where((row) => row.id.equals(event.entityId))).write(
          ProductsCompanion(
            isDeleted: const Value(true),
            isActive: const Value(false),
            version: Value(event.entityVersion),
            updatedAt: Value(now),
          ),
        );
      case 'customer':
        await (db.update(
          db.customers,
        )..where((row) => row.id.equals(event.entityId))).write(
          CustomersCompanion(
            isDeleted: const Value(true),
            version: Value(event.entityVersion),
            updatedAt: Value(now),
          ),
        );
      default:
        AppLogger.w(
          'Remote delete ignored for unsupported type ${event.entityType}',
        );
    }
  }

  DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
