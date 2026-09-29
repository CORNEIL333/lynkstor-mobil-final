import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/utils/id_generator.dart';
import 'notification_service.dart';

class AutomationService {
  AutomationService({
    required this.db,
    required this.notifications,
    required this.sync,
  });

  final AppDatabase db;
  final NotificationService notifications;
  final SyncEngine sync;

  Future<void> ensureDefaultRules(String businessId) async {
    final existing = await (db.select(
      db.automationRules,
    )..where((t) => t.businessId.equals(businessId))).get();
    if (existing.any((rule) => rule.triggerType == 'stock_critical')) return;
    final now = DateTime.now();
    final id = IdGenerator.uuid();
    await db
        .into(db.automationRules)
        .insert(
          AutomationRulesCompanion.insert(
            id: id,
            businessId: businessId,
            triggerType: 'stock_critical',
            name: 'Alerte stock critique',
            actionType: 'draft_supplier_message',
            conditionJson: const Value('{"useProductThreshold":true}'),
            actionConfigJson: const Value('{"channels":["whatsapp","sms"]}'),
            cooldownMinutes: const Value(1440),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final rule = await (db.select(
      db.automationRules,
    )..where((row) => row.id.equals(id))).getSingle();
    await sync.enqueue(
      businessId: businessId,
      entityType: 'automation_rule',
      entityId: id,
      operation: 'create',
      payload: rule.toJson(),
    );
  }

  Future<void> evaluateProductStock({
    required String businessId,
    required String productId,
  }) async {
    await ensureDefaultRules(businessId);
    final product = await db.getProduct(productId);
    if (product == null || product.businessId != businessId) {
      return;
    }
    if (!product.trackStock ||
        product.isService ||
        product.stockQty > product.lowStockThreshold) {
      await (db.update(db.appNotifications)..where(
            (t) =>
                t.businessId.equals(businessId) &
                t.type.equals('stock') &
                t.entityId.equals(productId) &
                t.isArchived.equals(false),
          ))
          .write(const AppNotificationsCompanion(isArchived: Value(true)));
      return;
    }

    final relation =
        await (db.select(db.supplierProducts)
              ..where(
                (t) =>
                    t.businessId.equals(businessId) &
                    t.productId.equals(productId),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.isPreferred)])
              ..limit(1))
            .getSingleOrNull();
    Supplier? supplier;
    if (relation != null) {
      supplier = await (db.select(
        db.suppliers,
      )..where((t) => t.id.equals(relation.supplierId))).getSingleOrNull();
    }
    final reorderQuantity = relation?.reorderQuantity ?? 1;
    final args = <String, Object?>{
      'product': product.name,
      'stock': product.stockQty,
      'threshold': product.lowStockThreshold,
      'reorderQuantity': reorderQuantity,
      if (supplier != null) 'supplier': supplier.name,
    };
    final actionPayload = <String, Object?>{
      'productId': product.id,
      'productName': product.name,
      'stock': product.stockQty,
      'threshold': product.lowStockThreshold,
      'reorderQuantity': reorderQuantity,
      if (supplier != null) ...{
        'supplierId': supplier.id,
        'supplierName': supplier.name,
        'phone': supplier.phone,
      },
    };
    final created = await notifications.create(
      businessId: businessId,
      type: 'stock',
      severity: product.stockQty <= 0 ? 'critical' : 'warning',
      titleKey: 'stockCriticalTitle',
      bodyKey: supplier == null
          ? 'stockCriticalNoSupplierBody'
          : 'stockCriticalSupplierBody',
      args: args,
      entityType: 'product',
      entityId: product.id,
      actionType: supplier == null
          ? 'configure_supplier'
          : 'draft_supplier_message',
      actionPayload: actionPayload,
      dedupeKey: 'stock:${product.id}:${product.stockQty <= 0 ? 'out' : 'low'}',
    );
    if (created == null) return;
    await _recordRun(
      businessId: businessId,
      triggerType: 'stock_critical',
      entityType: 'product',
      entityId: product.id,
      result: {'notificationId': created.id, 'args': args},
    );
  }

  Future<void> notifyAdHocProduct({
    required String businessId,
    required String saleId,
    required String productName,
    required double unitPrice,
    required String unit,
  }) async {
    await notifications.create(
      businessId: businessId,
      type: 'catalog',
      severity: 'info',
      titleKey: 'adHocProductTitle',
      bodyKey: 'adHocProductBody',
      args: {'product': productName},
      entityType: 'sale',
      entityId: saleId,
      actionType: 'configure_ad_hoc_product',
      actionPayload: {
        'saleId': saleId,
        'name': productName,
        'price': unitPrice,
        'unit': unit,
      },
      dedupeKey: 'adhoc:$saleId:$productName',
      dedupeWindow: const Duration(days: 365),
    );
  }

  Future<void> _recordRun({
    required String businessId,
    required String triggerType,
    String? entityType,
    String? entityId,
    Map<String, Object?> result = const {},
  }) async {
    final id = IdGenerator.uuid();
    await db
        .into(db.automationRuns)
        .insert(
          AutomationRunsCompanion.insert(
            id: id,
            businessId: businessId,
            triggerType: triggerType,
            entityType: Value(entityType),
            entityId: Value(entityId),
            resultJson: Value(jsonEncode(result)),
            createdAt: DateTime.now(),
          ),
        );
    final run = await (db.select(
      db.automationRuns,
    )..where((row) => row.id.equals(id))).getSingle();
    await sync.enqueue(
      businessId: businessId,
      entityType: 'automation_run',
      entityId: id,
      operation: 'create',
      payload: run.toJson(),
    );
  }

  Future<void> setPreferredSupplier({
    required String businessId,
    required String productId,
    required String supplierId,
    required double reorderQuantity,
  }) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.supplierProducts)..where(
            (t) =>
                t.businessId.equals(businessId) & t.productId.equals(productId),
          ))
          .write(const SupplierProductsCompanion(isPreferred: Value(false)));
      final existing =
          await (db.select(db.supplierProducts)
                ..where(
                  (t) =>
                      t.businessId.equals(businessId) &
                      t.productId.equals(productId) &
                      t.supplierId.equals(supplierId),
                )
                ..limit(1))
              .getSingleOrNull();
      if (existing == null) {
        await db
            .into(db.supplierProducts)
            .insert(
              SupplierProductsCompanion.insert(
                id: IdGenerator.uuid(),
                businessId: businessId,
                supplierId: supplierId,
                productId: productId,
                isPreferred: const Value(true),
                reorderQuantity: Value(reorderQuantity),
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (db.update(
          db.supplierProducts,
        )..where((t) => t.id.equals(existing.id))).write(
          SupplierProductsCompanion(
            isPreferred: const Value(true),
            reorderQuantity: Value(reorderQuantity),
            updatedAt: Value(now),
          ),
        );
      }
    });
    final relations =
        await (db.select(db.supplierProducts)..where(
              (row) =>
                  row.businessId.equals(businessId) &
                  row.productId.equals(productId),
            ))
            .get();
    for (final relation in relations) {
      await sync.enqueue(
        businessId: businessId,
        entityType: 'supplier_product',
        entityId: relation.id,
        operation: 'upsert',
        payload: relation.toJson(),
      );
    }
  }

  Future<SupplierProduct?> preferredSupplier(String productId) {
    return (db.select(db.supplierProducts)
          ..where((t) => t.productId.equals(productId))
          ..orderBy([(t) => OrderingTerm.desc(t.isPreferred)])
          ..limit(1))
        .getSingleOrNull();
  }
}
