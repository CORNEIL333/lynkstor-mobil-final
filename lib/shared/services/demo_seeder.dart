import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/utils/id_generator.dart';

/// Données de démonstration réalistes (boutique camerounaise / ouest-africaine).
class DemoSeeder {
  DemoSeeder({required this.db});

  final AppDatabase db;

  Future<void> seed(String businessId, {String? userId}) async {
    final now = DateTime.now();
    final existing = await db.getProducts(businessId);
    if (existing.isNotEmpty) return;

    final catFood = IdGenerator.uuid();
    final catDrink = IdGenerator.uuid();
    final catHouse = IdGenerator.uuid();

    await db
        .into(db.categories)
        .insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: catFood,
            businessId: businessId,
            name: 'Alimentation',
            color: const Value('#2D6A4F'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.categories)
        .insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: catDrink,
            businessId: businessId,
            name: 'Boissons',
            color: const Value('#3D5A8A'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.categories)
        .insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: catHouse,
            businessId: businessId,
            name: 'Maison',
            color: const Value('#C4785A'),
            createdAt: now,
            updatedAt: now,
          ),
        );

    final products = <Map<String, dynamic>>[
      {
        'name': 'Riz long grain 25 kg',
        'cat': catFood,
        'price': 18500,
        'cost': 16000,
        'stock': 24,
        'barcode': '6111258450011',
        'unit': 'sac',
      },
      {
        'name': 'Huile de palme 1 L',
        'cat': catFood,
        'price': 1200,
        'cost': 900,
        'stock': 48,
        'barcode': '6111258450028',
        'unit': 'bouteille',
      },
      {
        'name': 'Sucre en poudre 1 kg',
        'cat': catFood,
        'price': 900,
        'cost': 700,
        'stock': 60,
        'barcode': '6111258450035',
        'unit': 'paquet',
      },
      {
        'name': 'Sardines en boîte',
        'cat': catFood,
        'price': 650,
        'cost': 480,
        'stock': 80,
        'barcode': '6111258450042',
        'unit': 'boîte',
      },
      {
        'name': 'Tomate concentrée 70 g',
        'cat': catFood,
        'price': 200,
        'cost': 140,
        'stock': 120,
        'barcode': '6111258450059',
        'unit': 'boîte',
      },
      {
        'name': 'Eau minérale 1,5 L',
        'cat': catDrink,
        'price': 350,
        'cost': 220,
        'stock': 96,
        'barcode': '6111258450066',
        'unit': 'bouteille',
      },
      {
        'name': 'Jus d\'ananas 1 L',
        'cat': catDrink,
        'price': 800,
        'cost': 550,
        'stock': 36,
        'barcode': '6111258450073',
        'unit': 'bouteille',
      },
      {
        'name': 'Savon de ménage',
        'cat': catHouse,
        'price': 450,
        'cost': 300,
        'stock': 50,
        'barcode': '6111258450080',
        'unit': 'pièce',
      },
      {
        'name': 'Lessive 500 g',
        'cat': catHouse,
        'price': 1500,
        'cost': 1100,
        'stock': 28,
        'barcode': '6111258450097',
        'unit': 'paquet',
      },
      {
        'name': 'Allumettes (paquet)',
        'cat': catHouse,
        'price': 100,
        'cost': 60,
        'stock': 200,
        'barcode': '6111258450103',
        'unit': 'paquet',
      },
      {
        'name': 'Maggi cube (x24)',
        'cat': catFood,
        'price': 600,
        'cost': 420,
        'stock': 40,
        'barcode': '6111258450110',
        'unit': 'paquet',
      },
      {
        'name': 'Farine de blé 1 kg',
        'cat': catFood,
        'price': 750,
        'cost': 550,
        'stock': 4, // low stock
        'barcode': '6111258450127',
        'unit': 'paquet',
      },
    ];

    for (final p in products) {
      final id = IdGenerator.uuid();
      final stock = (p['stock'] as num).toDouble();
      await db.insertProduct(
        ProductsCompanion.insert(
          id: id,
          businessId: businessId,
          categoryId: Value(p['cat'] as String),
          name: p['name'] as String,
          salePrice: Value((p['price'] as num).toDouble()),
          costPrice: Value((p['cost'] as num).toDouble()),
          stockQty: Value(stock),
          barcode: Value(p['barcode'] as String),
          unit: Value(p['unit'] as String),
          lowStockThreshold: const Value(5),
          isFavorite: Value(
            (p['name'] as String).contains('Riz') ||
                (p['name'] as String).contains('Huile'),
          ),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db
          .into(db.stockMovements)
          .insertOnConflictUpdate(
            StockMovementsCompanion.insert(
              id: IdGenerator.uuid(),
              businessId: businessId,
              productId: id,
              type: 'init',
              quantity: stock,
              qtyBefore: 0,
              qtyAfter: stock,
              note: const Value('Stock démonstration'),
              userId: Value(userId),
              createdAt: now,
            ),
          );
    }

    // Clients
    final clients = [
      {
        'name': 'Amina Ngozi',
        'phone': '690112233',
        'neighborhood': 'Akwa',
        'balance': 12500.0,
      },
      {
        'name': 'Jean-Paul Mbarga',
        'phone': '677445566',
        'neighborhood': 'Bonanjo',
        'balance': 0.0,
      },
      {
        'name': 'Fatou Diallo',
        'phone': '655998877',
        'neighborhood': 'Deido',
        'balance': 32000.0,
      },
      {
        'name': 'Boutique Chez Maman',
        'phone': '699001122',
        'neighborhood': 'New Bell',
        'balance': 8500.0,
      },
    ];

    for (final c in clients) {
      await db.insertCustomer(
        CustomersCompanion.insert(
          id: IdGenerator.uuid(),
          businessId: businessId,
          name: c['name'] as String,
          phone: Value(c['phone'] as String),
          neighborhood: Value(c['neighborhood'] as String),
          balance: Value(c['balance'] as double),
          creditLimit: const Value(50000),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    // Fournisseur
    await db
        .into(db.suppliers)
        .insertOnConflictUpdate(
          SuppliersCompanion.insert(
            id: IdGenerator.uuid(),
            businessId: businessId,
            name: 'Grossiste Marché Central',
            phone: const Value('233456789'),
            address: const Value('Douala — Marché Central'),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}
