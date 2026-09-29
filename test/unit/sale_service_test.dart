import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/errors/app_exception.dart';
import 'package:kumba_business/core/sync/sync_engine.dart';
import 'package:kumba_business/core/utils/id_generator.dart';
import 'package:kumba_business/shared/services/product_service.dart';
import 'package:kumba_business/shared/services/sale_service.dart';
import 'package:kumba_business/shared/services/automation_service.dart';
import 'package:kumba_business/shared/services/notification_service.dart';

void main() {
  late AppDatabase db;
  late SaleService sales;
  late ProductService products;
  late AutomationService automation;
  late String businessId;

  setUp(() async {
    db = createTestDatabase();
    final sync = SyncEngine(db);
    final notifications = NotificationService(db: db);
    automation = AutomationService(
      db: db,
      notifications: notifications,
      sync: sync,
    );
    sales = SaleService(db: db, sync: sync, automation: automation);
    products = ProductService(db: db, sync: sync);
    businessId = IdGenerator.uuid();
    final now = DateTime.now();
    await db.insertBusiness(
      BusinessesCompanion.insert(
        id: businessId,
        name: 'Test Boutique',
        ownerName: 'Test',
        phone: '600000000',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('completeSale reduces stock and persists sale', () async {
    final product = await products.create(
      businessId,
      ProductInput(
        name: 'Riz 25kg',
        salePrice: 18500,
        costPrice: 16000,
        stockQty: 10,
      ),
    );

    final sale = await sales.completeSale(
      CompleteSaleInput(
        businessId: businessId,
        lines: [
          CartLine(
            productId: product.id,
            productName: product.name,
            unitPrice: product.salePrice,
            quantity: 2,
            costPrice: product.costPrice,
            trackStock: true,
            availableStock: 10,
          ),
        ],
        payments: [PaymentPart(method: 'cash', amount: 37000)],
      ),
    );

    expect(sale.total, 37000);
    expect(sale.status, 'completed');

    final updated = await products.byId(product.id);
    expect(updated!.stockQty, 8);

    final items = await sales.items(sale.id);
    expect(items.length, 1);
  });

  test('credit sale without customer throws', () async {
    final product = await products.create(
      businessId,
      ProductInput(name: 'Huile', salePrice: 1200, stockQty: 5),
    );

    expect(
      () => sales.completeSale(
        CompleteSaleInput(
          businessId: businessId,
          lines: [
            CartLine(
              productId: product.id,
              productName: product.name,
              unitPrice: 1200,
              quantity: 1,
              trackStock: true,
              availableStock: 5,
            ),
          ],
          payments: [PaymentPart(method: 'credit', amount: 0)],
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('insufficient stock throws StockException', () async {
    final product = await products.create(
      businessId,
      ProductInput(name: 'Savon', salePrice: 450, stockQty: 1),
    );

    expect(
      () => sales.completeSale(
        CompleteSaleInput(
          businessId: businessId,
          lines: [
            CartLine(
              productId: product.id,
              productName: product.name,
              unitPrice: 450,
              quantity: 5,
              trackStock: true,
              availableStock: 1,
            ),
          ],
          payments: [PaymentPart(method: 'cash', amount: 2250)],
        ),
      ),
      throwsA(isA<StockException>()),
    );
  });

  test('duplicate cart lines cannot oversell the same product', () async {
    final product = await products.create(
      businessId,
      ProductInput(name: 'Farine', salePrice: 1000, stockQty: 3),
    );

    expect(
      () => sales.completeSale(
        CompleteSaleInput(
          businessId: businessId,
          lines: [
            for (var i = 0; i < 2; i++)
              CartLine(
                productId: product.id,
                productName: product.name,
                unitPrice: 1000,
                quantity: 2,
                trackStock: true,
                availableStock: 3,
              ),
          ],
          payments: [PaymentPart(method: 'cash', amount: 4000)],
        ),
      ),
      throwsA(isA<StockException>()),
    );

    expect((await products.byId(product.id))!.stockQty, 3);
  });

  test('sale rejects a product belonging to another business', () async {
    final otherBusinessId = IdGenerator.uuid();
    final now = DateTime.now();
    await db.insertBusiness(
      BusinessesCompanion.insert(
        id: otherBusinessId,
        name: 'Autre boutique',
        ownerName: 'Autre',
        phone: '611111111',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final foreignProduct = await products.create(
      otherBusinessId,
      ProductInput(name: 'Produit externe', salePrice: 500, stockQty: 10),
    );

    expect(
      () => sales.completeSale(
        CompleteSaleInput(
          businessId: businessId,
          lines: [
            CartLine(
              productId: foreignProduct.id,
              productName: foreignProduct.name,
              unitPrice: 500,
              quantity: 1,
              trackStock: true,
              availableStock: 10,
            ),
          ],
          payments: [PaymentPart(method: 'cash', amount: 500)],
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test(
    'unlisted item can be sold then linked without changing stock',
    () async {
      final sale = await sales.completeSale(
        CompleteSaleInput(
          businessId: businessId,
          lines: [
            CartLine(
              productId: null,
              productName: 'Article libre',
              unitPrice: 2500,
              quantity: 2,
              trackStock: false,
            ),
          ],
          payments: [PaymentPart(method: 'cash', amount: 5000)],
        ),
      );

      var items = await sales.items(sale.id);
      expect(items.single.productId, isNull);

      final product = await products.create(
        businessId,
        ProductInput(name: 'Article libre', salePrice: 2500, stockQty: 6),
      );
      await sales.linkAdHocItems(
        saleId: sale.id,
        productId: product.id,
        productName: 'Article libre',
      );

      items = await sales.items(sale.id);
      expect(items.single.productId, product.id);
      expect((await products.byId(product.id))!.stockQty, 6);

      final notifications = await db.select(db.appNotifications).get();
      expect(notifications.single.type, 'catalog');
    },
  );

  test('sale crossing threshold creates one stock alert', () async {
    final product = await products.create(
      businessId,
      ProductInput(
        name: 'Clous',
        salePrice: 100,
        stockQty: 3,
        lowStockThreshold: 2,
      ),
    );

    await sales.completeSale(
      CompleteSaleInput(
        businessId: businessId,
        lines: [
          CartLine(
            productId: product.id,
            productName: product.name,
            unitPrice: product.salePrice,
            quantity: 1,
            trackStock: true,
            availableStock: 3,
          ),
        ],
        payments: [PaymentPart(method: 'cash', amount: 100)],
      ),
    );

    final notifications = await db.select(db.appNotifications).get();
    expect(
      notifications.where((notification) => notification.type == 'stock'),
      hasLength(1),
    );
  });

  test('restocked product archives its open stock alert', () async {
    final product = await products.create(
      businessId,
      ProductInput(
        name: 'Vis',
        salePrice: 50,
        stockQty: 1,
        lowStockThreshold: 2,
      ),
    );
    await automation.evaluateProductStock(
      businessId: businessId,
      productId: product.id,
    );

    await products.adjustStock(
      businessId: businessId,
      productId: product.id,
      newQty: 10,
      reason: 'Réapprovisionnement test',
    );
    await automation.evaluateProductStock(
      businessId: businessId,
      productId: product.id,
    );

    final notifications = await db.select(db.appNotifications).get();
    expect(notifications, hasLength(1));
    expect(notifications.single.isArchived, isTrue);
  });
}
