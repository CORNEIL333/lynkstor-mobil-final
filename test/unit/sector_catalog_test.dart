import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/catalog/sector_catalog.dart';
import 'package:kumba_business/core/config/app_config.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/sync/sync_engine.dart';
import 'package:kumba_business/core/utils/id_generator.dart';
import 'package:kumba_business/shared/services/product_service.dart';
import 'package:kumba_business/shared/services/sector_catalog_service.dart';

void main() {
  group('SectorCatalog', () {
    test('every activity sector has more than 1000 registered products', () {
      for (final sector in SectorCatalog.sectors) {
        final products = SectorCatalog.forSector(sector);
        expect(
          products.length,
          greaterThan(AppConfig.minSectorCatalogSize),
          reason: '$sector has ${products.length} products',
        );
      }
    });

    test('ids, names and barcodes are unique within a sector', () {
      for (final sector in SectorCatalog.sectors) {
        final products = SectorCatalog.forSector(sector);
        expect(products.map((p) => p.id).toSet(), hasLength(products.length));
        expect(products.map((p) => p.name).toSet(), hasLength(products.length));
        expect(
          products.map((p) => p.barcode).toSet(),
          hasLength(products.length),
        );
      }
    });

    test('activation key is disabled for the test shop panel', () {
      expect(AppConfig.requireAgentActivationCode, isFalse);
    });

    test('products are not services-only and keep a positive price', () {
      for (final sector in SectorCatalog.sectors) {
        final products = SectorCatalog.forSector(sector);
        expect(products.every((p) => p.salePrice > 0), isTrue);
        expect(products.any((p) => !p.isService), isTrue);
      }
    });
  });

  group('SectorCatalogService', () {
    late AppDatabase db;
    late ProductService products;
    late SectorCatalogService catalog;
    late String businessId;

    setUp(() async {
      db = createTestDatabase();
      products = ProductService(db: db, sync: SyncEngine(db));
      catalog = SectorCatalogService(db: db, products: products);
      businessId = IdGenerator.uuid();
      final now = DateTime.now();
      await db.insertBusiness(
        BusinessesCompanion.insert(
          id: businessId,
          name: 'Panel Test',
          ownerName: 'Test',
          phone: '690000000',
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('registered products stay inactive until activated', () async {
      final registered = catalog.registered('boutique');
      expect(registered.length, greaterThan(1000));

      final inactive = await catalog.offers(
        sector: 'boutique',
        businessId: businessId,
      );
      expect(inactive.length, registered.length);
      expect(inactive.every((o) => !o.activated), isTrue);

      final shopProducts = await products.list(businessId);
      expect(shopProducts, isEmpty);
    });

    test('activating a catalog product adds it once with stock 0', () async {
      final sample = catalog.registered('boutique').first;
      final created = await catalog.activate(businessId, sample);
      expect(created.sku, sample.id);
      expect(created.stockQty, 0);
      expect(created.name, sample.name);

      final again = await catalog.activate(businessId, sample);
      expect(again.id, created.id);

      final shopProducts = await products.list(businessId);
      expect(shopProducts, hasLength(1));

      final remaining = await catalog.offers(
        sector: 'boutique',
        businessId: businessId,
        filter: CatalogOfferFilter.inactive,
      );
      expect(remaining.length, catalog.registered('boutique').length - 1);
    });
  });
}
