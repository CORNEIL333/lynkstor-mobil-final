import 'dart:convert';
import 'package:flutter/services.dart';

/// Supplier observations from the prototype; never a shop's stock or cost price.
class PrototypeCatalogueItem {
  PrototypeCatalogueItem.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      category = json['category'] as String,
      brand = json['brand'] as String?,
      seller = json['seller'] as String,
      observedAt = json['observedAt'] as String,
      price = (json['price'] as num?)?.toDouble(),
      needsReview = json['needsReview'] == true,
      priceStatus = json['priceStatus'] as String;

  final String id, name, category, seller, observedAt, priceStatus;
  final String? brand;
  final double? price;
  final bool needsReview;

  double? get suggestedPrice =>
      !needsReview &&
          priceStatus == 'published' &&
          price != null &&
          price!.isFinite &&
          price! > 0
      ? price
      : null;

  bool matches(String query, String? selectedCategory) =>
      (selectedCategory == null || category == selectedCategory) &&
      '$name $category ${brand ?? ''} $seller'.toLowerCase().contains(
        query.trim().toLowerCase(),
      );
}

class PrototypeCatalogue {
  static const sources = {
    'boulangerie': 'Boulangerie',
    'parfumerie': 'Parfumerie',
    'telephonie-electromenager': 'Téléphonie & électroménager',
  };

  static Future<List<PrototypeCatalogueItem>> load(
    String source, {
    AssetBundle? bundle,
  }) async {
    if (!sources.containsKey(source)) {
      throw ArgumentError.value(source, 'source');
    }
    final json =
        jsonDecode(
              await (bundle ?? rootBundle).loadString(
                'assets/catalogue/$source.json',
              ),
            )
            as List<dynamic>;
    return json
        .map(
          (item) =>
              PrototypeCatalogueItem.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }
}
