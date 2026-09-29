import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/errors/app_exception.dart';
import 'package:kumba_business/core/sync/sync_engine.dart';
import 'package:kumba_business/core/utils/id_generator.dart';
import 'package:kumba_business/shared/services/customer_service.dart';
import 'package:kumba_business/shared/services/product_service.dart';
import 'package:kumba_business/shared/services/sale_service.dart';

void main() {
  late AppDatabase db;
  late SaleService sales;
  late ProductService products;
  late CustomerService customers;
  late String businessId;

  setUp(() async {
    db = createTestDatabase();
    final sync = SyncEngine(db);
    sales = SaleService(db: db, sync: sync);
    products = ProductService(db: db, sync: sync);
    customers = CustomerService(db: db, sync: sync);
    businessId = IdGenerator.uuid();
    final now = DateTime.now();
    await db.insertBusiness(
      BusinessesCompanion.insert(
        id: businessId,
        name: 'Test',
        ownerName: 'Owner',
        phone: '600',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async => db.close());

  test('credit sale increases customer balance via debt movement', () async {
    final product = await products.create(
      businessId,
      ProductInput(name: 'Riz', salePrice: 10000, stockQty: 20),
    );
    final customer = await customers.create(
      businessId,
      CustomerInput(name: 'Amina', creditLimit: 50000),
    );

    final sale = await sales.completeSale(
      CompleteSaleInput(
        businessId: businessId,
        customerId: customer.id,
        customerName: customer.name,
        lines: [
          CartLine(
            productId: product.id,
            productName: product.name,
            unitPrice: 10000,
            quantity: 1,
            trackStock: true,
            availableStock: 20,
          ),
        ],
        payments: [PaymentPart(method: 'credit', amount: 0)],
      ),
    );

    expect(sale.amountDue, 10000);
    final updated = await customers.byId(customer.id);
    expect(updated!.balance, 10000);

    final movements = await customers.movements(customer.id);
    expect(movements.length, 1);
    expect(movements.first.type, 'credit_sale');
  });

  test('debt collection decreases balance and never allows overpay', () async {
    final customer = await customers.create(
      businessId,
      CustomerInput(name: 'Jean', creditLimit: 100000),
    );
    // force balance via a product credit sale
    final product = await products.create(
      businessId,
      ProductInput(name: 'Huile', salePrice: 5000, stockQty: 10),
    );
    await sales.completeSale(
      CompleteSaleInput(
        businessId: businessId,
        customerId: customer.id,
        customerName: customer.name,
        lines: [
          CartLine(
            productId: product.id,
            productName: product.name,
            unitPrice: 5000,
            quantity: 1,
            trackStock: true,
            availableStock: 10,
          ),
        ],
        payments: [PaymentPart(method: 'credit', amount: 0)],
      ),
    );

    await customers.collectDebt(
      businessId: businessId,
      customerId: customer.id,
      amount: 2000,
      method: 'cash',
    );
    final mid = await customers.byId(customer.id);
    expect(mid!.balance, 3000);

    expect(
      () => customers.collectDebt(
        businessId: businessId,
        customerId: customer.id,
        amount: 99999,
        method: 'cash',
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('return restocks and is audited', () async {
    final product = await products.create(
      businessId,
      ProductInput(name: 'Savon', salePrice: 450, stockQty: 10),
    );
    final sale = await sales.completeSale(
      CompleteSaleInput(
        businessId: businessId,
        lines: [
          CartLine(
            productId: product.id,
            productName: product.name,
            unitPrice: 450,
            quantity: 3,
            trackStock: true,
            availableStock: 10,
          ),
        ],
        payments: [PaymentPart(method: 'cash', amount: 1350)],
      ),
    );

    await sales.createReturn(
      businessId: businessId,
      saleId: sale.id,
      lines: [
        (
          productId: product.id,
          productName: product.name,
          qty: 1,
          unitPrice: 450,
        ),
      ],
      reason: 'Erreur de caisse',
      refundMethod: 'refund',
      restock: true,
    );

    final after = await products.byId(product.id);
    expect(after!.stockQty, 8); // 10 - 3 + 1
  });

  test('successive returns cannot exceed the original sold quantity', () async {
    final product = await products.create(
      businessId,
      ProductInput(name: 'Biscuit', salePrice: 250, stockQty: 10),
    );
    final sale = await sales.completeSale(
      CompleteSaleInput(
        businessId: businessId,
        lines: [
          CartLine(
            productId: product.id,
            productName: product.name,
            unitPrice: 250,
            quantity: 2,
            trackStock: true,
            availableStock: 10,
          ),
        ],
        payments: [PaymentPart(method: 'cash', amount: 500)],
      ),
    );

    await sales.createReturn(
      businessId: businessId,
      saleId: sale.id,
      lines: [
        (
          productId: product.id,
          productName: product.name,
          qty: 1,
          unitPrice: 250,
        ),
      ],
      reason: 'Premier retour',
      refundMethod: 'refund',
    );

    expect(
      () => sales.createReturn(
        businessId: businessId,
        saleId: sale.id,
        lines: [
          (
            productId: product.id,
            productName: product.name,
            qty: 2,
            unitPrice: 250,
          ),
        ],
        reason: 'Retour en trop',
        refundMethod: 'refund',
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('credit return reduces customer debt and updates sale status', () async {
    final product = await products.create(
      businessId,
      ProductInput(name: 'Lait', salePrice: 1000, stockQty: 10),
    );
    final customer = await customers.create(
      businessId,
      CustomerInput(name: 'Mariam', creditLimit: 10000),
    );
    final sale = await sales.completeSale(
      CompleteSaleInput(
        businessId: businessId,
        customerId: customer.id,
        customerName: customer.name,
        lines: [
          CartLine(
            productId: product.id,
            productName: product.name,
            unitPrice: 1000,
            quantity: 2,
            trackStock: true,
            availableStock: 10,
          ),
        ],
        payments: [PaymentPart(method: 'credit', amount: 0)],
      ),
    );

    await sales.createReturn(
      businessId: businessId,
      saleId: sale.id,
      lines: [
        (
          productId: product.id,
          productName: product.name,
          qty: 1,
          unitPrice: 1000,
        ),
      ],
      reason: 'Produit endommagé',
      refundMethod: 'credit_note',
    );

    expect((await customers.byId(customer.id))!.balance, 1000);
    expect((await sales.byId(sale.id))!.status, 'partially_returned');
  });

  test('seller role denied on return', () async {
    final product = await products.create(
      businessId,
      ProductInput(name: 'Eau', salePrice: 350, stockQty: 5),
    );
    final sale = await sales.completeSale(
      CompleteSaleInput(
        businessId: businessId,
        lines: [
          CartLine(
            productId: product.id,
            productName: product.name,
            unitPrice: 350,
            quantity: 1,
            trackStock: true,
            availableStock: 5,
          ),
        ],
        payments: [PaymentPart(method: 'cash', amount: 350)],
      ),
    );

    expect(
      () => sales.createReturn(
        businessId: businessId,
        saleId: sale.id,
        lines: [
          (
            productId: product.id,
            productName: product.name,
            qty: 1,
            unitPrice: 350,
          ),
        ],
        reason: 'Test',
        refundMethod: 'refund',
        userRole: 'seller',
      ),
      throwsA(isA<PermissionException>()),
    );
  });

  test('seller role denied on product create', () async {
    expect(
      () => products.create(
        businessId,
        ProductInput(name: 'X', salePrice: 1),
        userRole: 'seller',
      ),
      throwsA(isA<PermissionException>()),
    );
  });
}
