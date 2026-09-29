import '../../core/catalog/sector_catalog.dart';
import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/permissions/permission_guard.dart';
import '../../core/permissions/permissions.dart';
import 'analytics_service.dart';
import 'product_service.dart';

enum CatalogOfferFilter { inactive, activated, all }

class SectorCatalogOffer {
  const SectorCatalogOffer({required this.product, required this.activated});

  final SectorCatalogProduct product;
  final bool activated;
}

class SectorCatalogService {
  SectorCatalogService({required this.db, required this.products});

  final AppDatabase db;
  final ProductService products;

  List<SectorCatalogProduct> registered(String sector) =>
      SectorCatalog.forSector(sector);

  List<String> categories(String sector) => SectorCatalog.categoriesFor(sector);

  Future<Set<String>> activatedSkus(String businessId) =>
      products.skus(businessId);

  Future<List<SectorCatalogOffer>> offers({
    required String sector,
    required String businessId,
    String query = '',
    String? category,
    CatalogOfferFilter filter = CatalogOfferFilter.inactive,
  }) async {
    final activated = await activatedSkus(businessId);
    final q = query.trim().toLowerCase();
    final out = <SectorCatalogOffer>[];
    for (final product in SectorCatalog.forSector(sector)) {
      if (category != null &&
          category.isNotEmpty &&
          product.category != category) {
        continue;
      }
      if (q.isNotEmpty &&
          !product.name.toLowerCase().contains(q) &&
          !product.category.toLowerCase().contains(q) &&
          !product.barcode.contains(query.trim())) {
        continue;
      }
      final isOn = activated.contains(product.id);
      switch (filter) {
        case CatalogOfferFilter.inactive:
          if (isOn) continue;
        case CatalogOfferFilter.activated:
          if (!isOn) continue;
        case CatalogOfferFilter.all:
          break;
      }
      out.add(SectorCatalogOffer(product: product, activated: isOn));
    }
    return out;
  }

  /// Active une référence du catalogue : elle entre dans le stock du commerce
  /// (quantité 0) et n’est plus proposée comme « non activée ».
  Future<Product> activate(
    String businessId,
    SectorCatalogProduct catalog, {
    String? userId,
    String userRole = 'owner',
  }) async {
    PermissionGuard.of(userRole).require(AppPermission.productsManage);
    final existing = await products.bySku(businessId, catalog.id);
    if (existing != null) return existing;

    final categoryId = await _ensureCategory(businessId, catalog.category);
    try {
      return await products.create(
        businessId,
        ProductInput(
          name: catalog.name,
          salePrice: catalog.salePrice,
          costPrice: catalog.costPrice,
          unit: catalog.unit,
          barcode: catalog.barcode,
          sku: catalog.id,
          categoryId: categoryId,
          stockQty: 0,
          trackStock: !catalog.isService,
          isService: catalog.isService,
        ),
        userId: userId,
        userRole: userRole,
      );
    } on ValidationException {
      rethrow;
    }
  }

  Future<int> activateMany(
    String businessId,
    Iterable<SectorCatalogProduct> items, {
    String? userId,
    String userRole = 'owner',
  }) async {
    PermissionGuard.of(userRole).require(AppPermission.productsManage);
    var created = 0;
    final already = await activatedSkus(businessId);
    for (final item in items) {
      if (already.contains(item.id)) continue;
      await activate(businessId, item, userId: userId, userRole: userRole);
      already.add(item.id);
      created++;
    }
    if (created > 0) {
      AppAnalytics.track(
        'catalog.activated',
        properties: {'count': created},
      );
    }
    return created;
  }

  Future<String> _ensureCategory(String businessId, String name) async {
    final existing = await products.categories(businessId);
    for (final category in existing) {
      if (category.name.toLowerCase() == name.toLowerCase()) {
        return category.id;
      }
    }
    final created = await products.createCategory(businessId, name);
    return created.id;
  }
}
