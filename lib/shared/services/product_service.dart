import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/permissions/permission_guard.dart';
import '../../core/permissions/permissions.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/utils/id_generator.dart';
import '../../core/logging/app_logger.dart';
import 'analytics_service.dart';
import 'automation_service.dart';

class ProductInput {
  ProductInput({
    required this.name,
    required this.salePrice,
    this.description,
    this.categoryId,
    this.sku,
    this.barcode,
    this.unit = 'pièce',
    this.costPrice = 0,
    this.wholesalePrice,
    this.stockQty = 0,
    this.lowStockThreshold = 5,
    this.trackStock = true,
    this.isService = false,
    this.photoPath,
  });

  final String name;
  final String? description;
  final String? categoryId;
  final String? sku;
  final String? barcode;
  final String unit;
  final double salePrice;
  final double costPrice;
  final double? wholesalePrice;
  final double stockQty;
  final double lowStockThreshold;
  final bool trackStock;
  final bool isService;
  final String? photoPath;
}

class ProductService {
  ProductService({required this.db, required this.sync, this.automation});

  final AppDatabase db;
  final SyncEngine sync;
  final AutomationService? automation;

  Future<List<Product>> list(
    String businessId, {
    String? query,
    bool? lowStock,
  }) => db.getProducts(businessId, query: query, lowStock: lowStock);

  Future<Product?> byId(String id) => db.getProduct(id);

  Future<Product?> byBarcode(String businessId, String barcode) =>
      db.getProductByBarcode(businessId, barcode);

  Future<Product?> bySku(String businessId, String sku) =>
      db.getProductBySku(businessId, sku);

  Future<Set<String>> skus(String businessId) => db.getProductSkus(businessId);

  Future<Product> create(
    String businessId,
    ProductInput input, {
    String? userId,
    String userRole = 'owner',
  }) async {
    PermissionGuard.of(userRole).require(AppPermission.productsManage);
    if (input.name.trim().isEmpty) {
      throw const ValidationException('Le nom du produit est obligatoire.');
    }
    if (!input.salePrice.isFinite ||
        !input.costPrice.isFinite ||
        !input.stockQty.isFinite ||
        !input.lowStockThreshold.isFinite ||
        input.salePrice < 0 ||
        input.costPrice < 0 ||
        input.stockQty < 0 ||
        input.lowStockThreshold < 0) {
      throw const ValidationException(
        'Les prix, le stock et le seuil doivent être des nombres positifs.',
      );
    }

    final now = DateTime.now();
    final id = IdGenerator.uuid();

    await db.transaction(() async {
      await db.insertProduct(
        ProductsCompanion.insert(
          id: id,
          businessId: businessId,
          categoryId: Value(input.categoryId),
          name: input.name.trim(),
          description: Value(input.description),
          sku: Value(input.sku),
          barcode: Value(input.barcode),
          unit: Value(input.unit),
          salePrice: Value(input.salePrice),
          costPrice: Value(input.costPrice),
          wholesalePrice: Value(input.wholesalePrice),
          stockQty: Value(input.isService ? 0 : input.stockQty),
          lowStockThreshold: Value(input.lowStockThreshold),
          trackStock: Value(input.trackStock && !input.isService),
          isService: Value(input.isService),
          photoPath: Value(input.photoPath),
          createdAt: now,
          updatedAt: now,
        ),
      );

      if (!input.isService && input.trackStock && input.stockQty != 0) {
        await db
            .into(db.stockMovements)
            .insertOnConflictUpdate(
              StockMovementsCompanion.insert(
                id: IdGenerator.uuid(),
                businessId: businessId,
                productId: id,
                type: 'init',
                quantity: input.stockQty,
                qtyBefore: 0,
                qtyAfter: input.stockQty,
                note: const Value('Stock initial'),
                userId: Value(userId),
                createdAt: now,
              ),
            );
      }

      await db.insertAudit(
        AuditLogsCompanion.insert(
          id: IdGenerator.uuid(),
          businessId: businessId,
          userId: Value(userId),
          action: 'product.created',
          entityType: const Value('product'),
          entityId: Value(id),
          createdAt: now,
        ),
      );
    });

    final created = (await db.getProduct(id))!;
    await sync.enqueue(
      businessId: businessId,
      entityType: 'product',
      entityId: id,
      operation: 'create',
      payload: created.toJson(),
      userId: userId,
    );

    AppLogger.audit('product.created', userId: userId, entityId: id);
    AppAnalytics.track(
      'product.created',
      properties: {
        'fromCatalog': (input.sku ?? '').startsWith('CAT-'),
        'isService': input.isService,
      },
    );
    await automation?.evaluateProductStock(
      businessId: businessId,
      productId: id,
    );
    return created;
  }

  Future<Product> update(
    Product product,
    ProductInput input, {
    String? userId,
  }) async {
    if (input.name.trim().isEmpty) {
      throw const ValidationException('Le nom du produit est obligatoire.');
    }
    if (!input.salePrice.isFinite ||
        !input.costPrice.isFinite ||
        !input.stockQty.isFinite ||
        !input.lowStockThreshold.isFinite ||
        input.salePrice < 0 ||
        input.costPrice < 0 ||
        input.stockQty < 0 ||
        input.lowStockThreshold < 0) {
      throw const ValidationException(
        'Prix, stock et seuil doivent être des nombres positifs.',
      );
    }
    final now = DateTime.now();
    final updated = product.copyWith(
      name: input.name.trim(),
      description: Value(input.description),
      categoryId: Value(input.categoryId),
      sku: Value(input.sku),
      barcode: Value(input.barcode),
      unit: input.unit,
      salePrice: input.salePrice,
      costPrice: input.costPrice,
      wholesalePrice: Value(input.wholesalePrice),
      lowStockThreshold: input.lowStockThreshold,
      trackStock: input.trackStock && !input.isService,
      isService: input.isService,
      photoPath: Value(input.photoPath),
      updatedAt: now,
      version: product.version + 1,
    );
    await db.updateProductRow(updated);
    await sync.enqueue(
      businessId: product.businessId,
      entityType: 'product',
      entityId: product.id,
      operation: 'update',
      payload: updated.toJson(),
      userId: userId,
    );
    AppLogger.audit('product.updated', userId: userId, entityId: product.id);
    await automation?.evaluateProductStock(
      businessId: product.businessId,
      productId: product.id,
    );
    return updated;
  }

  /// Ajustement de stock avec mouvement obligatoire.
  Future<void> adjustStock({
    required String businessId,
    required String productId,
    required double newQty,
    required String reason,
    String? userId,
    String type = 'adjustment',
    String userRole = 'owner',
  }) async {
    PermissionGuard.of(userRole).require(AppPermission.stockAdjust);
    final product = await db.getProduct(productId);
    if (product == null) throw const NotFoundException('Produit introuvable.');
    if (product.businessId != businessId) {
      throw const ValidationException(
        'Ce produit n’appartient pas à ce commerce.',
      );
    }
    if (!newQty.isFinite || newQty < 0) {
      throw const ValidationException(
        'La nouvelle quantité doit être un nombre positif.',
      );
    }
    if (!product.trackStock) return;

    final delta = newQty - product.stockQty;
    if (delta == 0) return;

    final now = DateTime.now();
    final updated = product.copyWith(
      stockQty: newQty,
      updatedAt: now,
      version: product.version + 1,
    );
    await db.transaction(() async {
      await db
          .into(db.stockMovements)
          .insertOnConflictUpdate(
            StockMovementsCompanion.insert(
              id: IdGenerator.uuid(),
              businessId: businessId,
              productId: productId,
              type: type,
              quantity: delta,
              qtyBefore: product.stockQty,
              qtyAfter: newQty,
              note: Value(reason),
              userId: Value(userId),
              createdAt: now,
            ),
          );
      await db.updateProductRow(updated);
    });
    await sync.enqueue(
      businessId: businessId,
      entityType: 'product',
      entityId: productId,
      operation: 'update',
      payload: updated.toJson(),
      userId: userId,
    );
    await automation?.evaluateProductStock(
      businessId: businessId,
      productId: productId,
    );
  }

  Future<List<Category>> categories(String businessId) =>
      (db.select(db.categories)..where(
            (t) => t.businessId.equals(businessId) & t.isDeleted.equals(false),
          ))
          .get();

  Future<Category> createCategory(String businessId, String name) async {
    final now = DateTime.now();
    final id = IdGenerator.uuid();
    await db
        .into(db.categories)
        .insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: id,
            businessId: businessId,
            name: name.trim(),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await (db.select(
      db.categories,
    )..where((t) => t.id.equals(id))).getSingle());
  }
}
