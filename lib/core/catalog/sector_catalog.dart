import '../config/app_config.dart';

/// Référence du catalogue sectoriel — enregistrée dans l’app, non activée
/// tant que le commerçant ne l’ajoute pas à son stock.
class SectorCatalogProduct {
  const SectorCatalogProduct({
    required this.id,
    required this.sector,
    required this.category,
    required this.name,
    required this.unit,
    required this.salePrice,
    required this.costPrice,
    required this.barcode,
    this.isService = false,
  });

  /// Identifiant stable (SKU une fois activé) : `CAT-{secteur}-{index}`.
  final String id;
  final String sector;
  final String category;
  final String name;
  final String unit;
  final double salePrice;
  final double costPrice;
  final String barcode;
  final bool isService;
}

class _Spec {
  const _Spec({
    required this.category,
    required this.items,
    required this.basePrice,
    this.brands = const [''],
    this.sizes = const [''],
    this.variants = const [''],
    this.unit = 'pièce',
    this.isService = false,
    this.costRatio = 0.72,
  });

  final String category;
  final List<String> brands;
  final List<String> items;
  final List<String> sizes;
  final List<String> variants;
  final String unit;
  final double basePrice;
  final bool isService;
  final double costRatio;
}

/// Catalogue local : plus de 1000 références par secteur, proposées
/// au commerçant sans être insérées dans son stock.
class SectorCatalog {
  SectorCatalog._();

  static const sectors = [
    'boutique',
    'superette',
    'grossiste',
    'quincaillerie',
    'imprimerie',
    'salon',
    'ambulant',
    'services',
  ];

  static const _qualifiers = [
    'standard',
    'premium',
    'économique',
    'local',
    'importé',
    'format familial',
    'pack duo',
    'pack trio',
    'qualité pro',
    'promo',
  ];

  static final Map<String, List<SectorCatalogProduct>> _cache = {};

  static String normalizeSector(String sector) {
    switch (sector) {
      case 'epicerie':
      case 'general':
        return 'boutique';
      case 'pharmacie':
        return 'superette';
      default:
        return sectors.contains(sector) ? sector : 'boutique';
    }
  }

  static List<SectorCatalogProduct> forSector(String sector) {
    final key = normalizeSector(sector);
    return _cache.putIfAbsent(key, () => _build(key));
  }

  static List<String> categoriesFor(String sector) {
    final seen = <String>{};
    final out = <String>[];
    for (final product in forSector(sector)) {
      if (seen.add(product.category)) out.add(product.category);
    }
    return out;
  }

  static List<SectorCatalogProduct> _build(String sector) {
    final specs = _specsFor(sector);
    final out = <SectorCatalogProduct>[];
    final seen = <String>{};
    var index = 1;
    final sectorDigit = sectors.indexOf(sector) + 1;

    void addProduct(_Spec spec, String name, int brandI, int sizeI, int varI) {
      final key = name.toLowerCase();
      if (name.isEmpty || !seen.add(key)) return;
      final id = 'CAT-$sector-${index.toString().padLeft(5, '0')}';
      final price = _price(spec.basePrice, brandI, sizeI, varI);
      out.add(
        SectorCatalogProduct(
          id: id,
          sector: sector,
          category: spec.category,
          name: name,
          unit: spec.unit,
          salePrice: price,
          costPrice: _roundFcfa(price * spec.costRatio),
          barcode: _ean13('20$sectorDigit${index.toString().padLeft(9, '0')}'),
          isService: spec.isService,
        ),
      );
      index++;
    }

    for (final spec in specs) {
      for (var b = 0; b < spec.brands.length; b++) {
        for (final item in spec.items) {
          for (var v = 0; v < spec.variants.length; v++) {
            for (var s = 0; s < spec.sizes.length; s++) {
              final name = [
                spec.brands[b],
                item,
                spec.variants[v],
                spec.sizes[s],
              ].where((part) => part.trim().isNotEmpty).join(' ');
              addProduct(spec, name, b, s, v);
            }
          }
        }
      }
    }

    var qualifier = 0;
    final seed = List<SectorCatalogProduct>.from(out);
    while (out.length < AppConfig.minSectorCatalogSize && seed.isNotEmpty) {
      final tag = _qualifiers[qualifier % _qualifiers.length];
      qualifier++;
      for (final product in seed) {
        if (out.length >= AppConfig.minSectorCatalogSize + 80) break;
        final name = '${product.name} ($tag)';
        if (!seen.add(name.toLowerCase())) continue;
        final id = 'CAT-$sector-${index.toString().padLeft(5, '0')}';
        out.add(
          SectorCatalogProduct(
            id: id,
            sector: sector,
            category: product.category,
            name: name,
            unit: product.unit,
            salePrice: _roundFcfa(
              product.salePrice * (1 + (qualifier % 5) * 0.06),
            ),
            costPrice: _roundFcfa(
              product.costPrice * (1 + (qualifier % 5) * 0.06),
            ),
            barcode: _ean13(
              '20$sectorDigit${index.toString().padLeft(9, '0')}',
            ),
            isService: product.isService,
          ),
        );
        index++;
      }
    }

    return List<SectorCatalogProduct>.unmodifiable(out);
  }

  static List<_Spec> _specsFor(String sector) {
    switch (sector) {
      case 'superette':
        return [..._groceryRetail(), ..._superetteExtra()];
      case 'grossiste':
        return _groceryWholesale();
      case 'ambulant':
        return _groceryStreet();
      case 'quincaillerie':
        return _hardware();
      case 'imprimerie':
        return _printShop();
      case 'salon':
        return _salon();
      case 'services':
        return _services();
      case 'boutique':
      default:
        return _groceryRetail();
    }
  }

  static double _price(double base, int brandI, int sizeI, int varI) {
    final raw =
        base * (1 + sizeI * 0.38) * (1 + brandI * 0.07) * (1 + varI * 0.04);
    return _roundFcfa(raw);
  }

  static double _roundFcfa(double value) {
    if (value <= 0) return 50;
    if (value < 100) return (value / 5).round() * 5.0;
    if (value < 1000) return (value / 25).round() * 25.0;
    if (value < 10000) return (value / 50).round() * 50.0;
    return (value / 100).round() * 100.0;
  }

  static String _ean13(String twelve) {
    final digits = twelve.padLeft(12, '0').substring(0, 12);
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final n = int.parse(digits[i]);
      sum += i.isEven ? n : n * 3;
    }
    final check = (10 - (sum % 10)) % 10;
    return '$digits$check';
  }
}

List<_Spec> _groceryRetail() => [
  const _Spec(
    category: 'Céréales',
    brands: [
      'Super Riz',
      'Riz Mama',
      'Oryza',
      'Golden Grain',
      'Caprice',
      'Uncle',
      'Délice',
      'Royal',
      'Tenen',
      'Sahel',
    ],
    items: ['Riz long grain', 'Riz parfumé', 'Riz brisé'],
    sizes: ['500 g', '1 kg', '2 kg', '5 kg', '10 kg', '25 kg', '50 kg'],
    unit: 'paquet',
    basePrice: 650,
  ),
  const _Spec(
    category: 'Huiles',
    brands: [
      'Dinor',
      'Mayor',
      'Aya',
      'Palme d’Or',
      'King Oil',
      'Chef',
      'Tropical',
      'Sahel',
    ],
    items: ['Huile de palme', 'Huile de soja', 'Huile d’arachide'],
    sizes: ['25 cl', '50 cl', '1 L', '3 L', '5 L', '10 L'],
    unit: 'bouteille',
    basePrice: 450,
  ),
  const _Spec(
    category: 'Épicerie',
    brands: ['SSS', 'Kania', 'Bonjour', 'Mama Africa', 'Nestlé', 'Promasidor'],
    items: ['Sucre en poudre', 'Farine de blé', 'Farine de manioc', 'Sel iodé'],
    sizes: ['500 g', '1 kg', '2 kg', '5 kg'],
    unit: 'paquet',
    basePrice: 400,
  ),
  const _Spec(
    category: 'Pâtes',
    brands: ['Panzani', 'Moulin d’Or', 'Randa', 'Tria', 'Bonjour', 'Mama'],
    items: ['Spaghetti', 'Macaroni', 'Vermicelle', 'Couscous'],
    sizes: ['200 g', '500 g', '1 kg'],
    unit: 'paquet',
    basePrice: 350,
  ),
  const _Spec(
    category: 'Conserves',
    brands: ['Le Lion', 'Capitaine', 'Geisha', 'Texas', 'Jago', 'Gino'],
    items: ['Sardines', 'Thon', 'Tomate concentrée', 'Maïs doux', 'Haricots'],
    sizes: ['70 g', '125 g', '400 g', '800 g'],
    unit: 'boîte',
    basePrice: 250,
  ),
  const _Spec(
    category: 'Assaisonnements',
    brands: ['Maggi', 'Jumbo', 'Adja', 'Doli', 'Knorr'],
    items: ['Cube', 'Bouillon', 'Épices poulet', 'Poivre'],
    sizes: ['x10', 'x24', 'x48', 'sachet 100 g'],
    unit: 'paquet',
    basePrice: 200,
  ),
  const _Spec(
    category: 'Lait & café',
    brands: ['Nido', 'Cowbell', 'Peak', 'Gloria', 'Nescafé', 'Café Soluble'],
    items: ['Lait en poudre', 'Lait concentré', 'Café soluble', 'Cacao'],
    sizes: ['50 g', '200 g', '400 g', '900 g', '1,8 kg'],
    unit: 'boîte',
    basePrice: 500,
  ),
  const _Spec(
    category: 'Boissons',
    brands: [
      'Coca-Cola',
      'Fanta',
      'Sprite',
      'Youki',
      'XXL',
      'Malta',
      'Vimto',
      'Top',
      'D’jino',
      'Schweppes',
    ],
    items: ['Soda'],
    variants: ['Original', 'Orange', 'Citron', 'Ananas', 'Tropical'],
    sizes: ['25 cl', '33 cl', '50 cl', '1 L', '1,5 L'],
    unit: 'bouteille',
    basePrice: 250,
  ),
  const _Spec(
    category: 'Jus',
    brands: ['Ceres', 'Capri-Sun', 'Tampico', 'Planet', 'Délifruit', 'Pamelo'],
    items: ['Jus'],
    variants: ['Ananas', 'Mangue', 'Orange', 'Goyave', 'Cocktail', 'Bissap'],
    sizes: ['20 cl', '50 cl', '1 L'],
    unit: 'bouteille',
    basePrice: 300,
  ),
  const _Spec(
    category: 'Eau',
    brands: [
      'Supermont',
      'Tangui',
      'Source du Pays',
      'Voltic',
      'Awa',
      'Olgane',
    ],
    items: ['Eau minérale'],
    sizes: ['33 cl', '50 cl', '1,5 L', '5 L', 'pack x6'],
    unit: 'bouteille',
    basePrice: 200,
  ),
  const _Spec(
    category: 'Snacks',
    brands: [
      'Bimbo',
      'Tuc',
      'Prince',
      'Oreos',
      'Lucky',
      'Choco Prince',
      'Bonjour',
    ],
    items: ['Biscuits', 'Gaufrettes', 'Chips'],
    sizes: ['sachet', 'pack x2', 'pack x6', 'boîte'],
    unit: 'paquet',
    basePrice: 200,
  ),
  const _Spec(
    category: 'Hygiène',
    brands: ['Omo', 'Ariel', 'Klin', 'Savon Super', 'Lux', 'Dettol', 'Colgate'],
    items: ['Savon de ménage', 'Lessive', 'Dentifrice', 'Papier toilette'],
    sizes: ['pièce', '250 g', '500 g', '1 kg', 'pack x4'],
    unit: 'pièce',
    basePrice: 300,
  ),
  const _Spec(
    category: 'Bébés',
    brands: ['Pampers', 'Bébé Confort', 'Molfix', 'Nido 1+', 'Cerelac'],
    items: ['Couches', 'Lingettes', 'Céréales bébé'],
    sizes: ['T1', 'T2', 'T3', 'T4', 'T5'],
    unit: 'paquet',
    basePrice: 1500,
  ),
  const _Spec(
    category: 'Frais',
    brands: ['Danone', 'SICA', 'Camlait', 'La Laitière', 'Local'],
    items: ['Yaourt', 'Beurre', 'Œufs plateau'],
    variants: ['Nature', 'Fraise', 'Vanille', 'Banane'],
    sizes: ['pot', 'pack x4', 'pack x8'],
    unit: 'pièce',
    basePrice: 250,
  ),
];

List<_Spec> _superetteExtra() => [
  const _Spec(
    category: 'Surgelés',
    brands: ['Capitaine', 'Ocean', 'Mama', 'Quick'],
    items: ['Poisson', 'Poulet découpé', 'Frites', 'Légumes'],
    sizes: ['500 g', '1 kg', '2 kg'],
    unit: 'paquet',
    basePrice: 1500,
  ),
  const _Spec(
    category: 'Boulangerie',
    brands: ['Pain du Marché', 'Boulangerie Akwa', 'Délice'],
    items: ['Pain de mie', 'Baguette', 'Croissant', 'Beignet'],
    sizes: ['pièce', 'pack x6'],
    unit: 'pièce',
    basePrice: 150,
  ),
];

List<_Spec> _groceryWholesale() => [
  const _Spec(
    category: 'Céréales',
    brands: [
      'Super Riz',
      'Riz Mama',
      'Oryza',
      'Golden Grain',
      'Caprice',
      'Uncle',
      'Délice',
      'Royal',
      'Tenen',
      'Sahel',
    ],
    items: ['Riz long grain', 'Riz parfumé', 'Riz brisé', 'Maïs grain'],
    sizes: ['5 kg', '10 kg', '25 kg', '50 kg', 'carton 10x1 kg', 'palette'],
    unit: 'sac',
    basePrice: 4500,
  ),
  const _Spec(
    category: 'Huiles',
    brands: [
      'Dinor',
      'Mayor',
      'Aya',
      'Palme d’Or',
      'King Oil',
      'Chef',
      'Tropical',
    ],
    items: ['Huile de palme', 'Huile de soja'],
    sizes: ['5 L', '10 L', '20 L', 'carton 12x1 L', 'fût 25 L'],
    unit: 'bidon',
    basePrice: 4500,
  ),
  const _Spec(
    category: 'Boissons',
    brands: [
      'Coca-Cola',
      'Fanta',
      'Sprite',
      'Youki',
      'XXL',
      'Malta',
      'Vimto',
      'Top',
      'Castel',
      'Guinness',
    ],
    items: ['Carton soda', 'Casier bière'],
    variants: ['Original', 'Orange', 'Citron', 'Ananas'],
    sizes: ['x12', 'x24', 'x24 grand format'],
    unit: 'carton',
    basePrice: 4500,
  ),
  const _Spec(
    category: 'Épicerie',
    brands: [
      'SSS',
      'Kania',
      'Bonjour',
      'Nestlé',
      'Promasidor',
      'Maggi',
      'Jumbo',
    ],
    items: ['Sucre', 'Farine', 'Lait poudre', 'Cube bouillon', 'Tomate'],
    sizes: ['carton', 'sac 10 kg', 'sac 25 kg', 'pack x20', 'pack x50'],
    unit: 'carton',
    basePrice: 8000,
  ),
  const _Spec(
    category: 'Hygiène',
    brands: ['Omo', 'Ariel', 'Klin', 'Lux', 'Dettol', 'Colgate'],
    items: ['Lessive', 'Savon', 'Dentifrice', 'Javel'],
    sizes: ['carton x12', 'carton x24', 'seau 5 kg', 'seau 10 kg'],
    unit: 'carton',
    basePrice: 6500,
  ),
  const _Spec(
    category: 'Conserves',
    brands: ['Le Lion', 'Geisha', 'Texas', 'Jago', 'Gino', 'Capitaine'],
    items: ['Sardines', 'Thon', 'Tomate', 'Lait concentré'],
    sizes: ['carton x24', 'carton x48', 'carton x96'],
    unit: 'carton',
    basePrice: 9000,
  ),
  const _Spec(
    category: 'Boissons alcoolisées',
    brands: [
      'Castel',
      'Beaufort',
      '33 Export',
      'Guinness',
      'Heineken',
      'Kadji',
    ],
    items: ['Casier bière', 'Carton vin'],
    sizes: ['x12', 'x24', 'x24 grand'],
    variants: ['blonde', 'brune', 'sans alcool'],
    unit: 'casier',
    basePrice: 8500,
  ),
];

List<_Spec> _groceryStreet() => [
  const _Spec(
    category: 'Boissons',
    brands: [
      'Coca-Cola',
      'Fanta',
      'Sprite',
      'Youki',
      'XXL',
      'Malta',
      'Vimto',
      'Top',
      'D’jino',
    ],
    items: ['Sachet', 'Canette', 'Bouteille'],
    variants: ['Original', 'Orange', 'Citron', 'Ananas'],
    sizes: ['20 cl', '25 cl', '33 cl', '50 cl'],
    unit: 'pièce',
    basePrice: 150,
  ),
  const _Spec(
    category: 'Snacks',
    brands: ['Bimbo', 'Lucky', 'Tuc', 'Prince', 'Bonjour', 'Choco', 'TomTom'],
    items: ['Biscuits', 'Bonbons', 'Cacahuètes', 'Chips'],
    sizes: ['sachet', 'pièce', 'pack x3'],
    unit: 'pièce',
    basePrice: 100,
  ),
  const _Spec(
    category: 'Télécom',
    brands: ['MTN', 'Orange', 'Camtel', 'Moov', 'Nexttel'],
    items: ['Crédit appel', 'Forfait data'],
    sizes: ['100 F', '200 F', '500 F', '1000 F', '2000 F', '5000 F'],
    unit: 'pièce',
    basePrice: 100,
    costRatio: 0.95,
  ),
  const _Spec(
    category: 'Tabac',
    brands: ['Fine', 'Rothmans', 'Dunhill', 'Excellence'],
    items: ['Cigarettes'],
    sizes: ['paquet', 'bâton'],
    unit: 'paquet',
    basePrice: 700,
  ),
  const _Spec(
    category: 'Épicerie',
    brands: ['Maggi', 'Jumbo', 'SSS', 'Kania', 'Mama'],
    items: ['Cube', 'Sachet tomate', 'Huile sachet', 'Sucre sachet'],
    sizes: ['unité', 'x3', 'x10'],
    unit: 'pièce',
    basePrice: 50,
  ),
  const _Spec(
    category: 'Pain',
    brands: ['Pain du coin', 'Boulanger', 'Local'],
    items: ['Pain', 'Beignet', 'Gâteau'],
    sizes: ['pièce', 'pack x4'],
    unit: 'pièce',
    basePrice: 100,
  ),
  const _Spec(
    category: 'Accessoires',
    brands: ['Oraimo', 'Baseus', 'Local', 'Remax'],
    items: ['Écouteurs', 'Câble', 'Chargeur', 'Powerbank'],
    sizes: ['unité', 'pack voyage'],
    variants: ['noir', 'blanc', 'rouge'],
    unit: 'pièce',
    basePrice: 1500,
  ),
];

List<_Spec> _hardware() => [
  const _Spec(
    category: 'Visserie',
    brands: ['Fix’It', 'ProFix', 'Sahel Tools', 'Master'],
    items: ['Vis à bois', 'Vis métaux', 'Boulon', 'Cheville', 'Clou'],
    variants: ['zingué', 'inox', 'noir'],
    sizes: [
      '3x20',
      '4x30',
      '5x40',
      '6x50',
      '8x60',
      '10x80',
      'boîte 100',
      'boîte 500',
    ],
    unit: 'boîte',
    basePrice: 350,
  ),
  const _Spec(
    category: 'Peinture',
    brands: ['Seigneurie', 'Tolibois', 'Coral', 'Crown', 'Sadolin'],
    items: ['Peinture murale', 'Laque', 'Vernis', 'Enduit'],
    variants: ['blanc', 'crème', 'bleu', 'vert', 'gris', 'ocre', 'rouge'],
    sizes: ['1 L', '4 L', '10 L', '20 L'],
    unit: 'pot',
    basePrice: 2500,
  ),
  const _Spec(
    category: 'Électricité',
    brands: ['Nexans', 'Legrand', 'Schneider', 'Local Cable', 'Philips'],
    items: ['Câble électrique', 'Ampoule LED', 'Prise', 'Interrupteur'],
    variants: ['1,5 mm²', '2,5 mm²', '4 mm²', '6 mm²', 'blanc', 'noir'],
    sizes: ['5 m', '10 m', '25 m', '50 m', '100 m', 'pièce'],
    unit: 'pièce',
    basePrice: 800,
  ),
  const _Spec(
    category: 'Plomberie',
    brands: ['Nicoll', 'SDEE', 'Aqua', 'ProPlomb'],
    items: ['Tube PVC', 'Coude PVC', 'Robinet', 'Flexible'],
    sizes: ['20 mm', '25 mm', '32 mm', '40 mm', '50 mm', '63 mm'],
    unit: 'pièce',
    basePrice: 600,
  ),
  const _Spec(
    category: 'Outils',
    brands: ['Stanley', 'Bosch', 'Total', 'Ingco', 'Makita', 'Local'],
    items: [
      'Marteau',
      'Tournevis',
      'Pince',
      'Mètre',
      'Scie',
      'Clé à molette',
      'Niveau',
    ],
    sizes: ['petit', 'standard', 'pro'],
    unit: 'pièce',
    basePrice: 1500,
  ),
  const _Spec(
    category: 'Maçonnerie',
    brands: ['Dangote', 'Cimencam', 'Lafarge', 'Local'],
    items: ['Ciment', 'Fer à béton', 'Bétonnière location'],
    sizes: ['25 kg', '50 kg', 'bar 6 mm', 'bar 8 mm', 'bar 10 mm', 'bar 12 mm'],
    unit: 'sac',
    basePrice: 4500,
  ),
  const _Spec(
    category: 'Carrelage',
    brands: ['Ceramica', 'R.A.K', 'Local Tile', 'Italgres'],
    items: ['Carreau sol', 'Carreau mur', 'Faïence'],
    variants: ['blanc', 'gris', 'beige', 'bois', 'marbre'],
    sizes: ['30x30', '40x40', '60x60'],
    unit: 'm²',
    basePrice: 4500,
  ),
];

List<_Spec> _printShop() => [
  const _Spec(
    category: 'Papier',
    brands: ['Clairefontaine', 'Double A', 'Navigator', 'Local Paper', 'Mondi'],
    items: ['Ramette'],
    variants: ['blanc', 'ivoire', 'couleur'],
    sizes: ['A4 80g', 'A4 90g', 'A3 80g', 'A5 80g', 'A4 120g', 'A4 160g'],
    unit: 'ramette',
    basePrice: 3500,
  ),
  const _Spec(
    category: 'Impression',
    brands: [''],
    items: [
      'Impression N&B',
      'Impression couleur',
      'Photocopie',
      'Flyer',
      'Affiche',
      'Bannière',
    ],
    sizes: ['A6', 'A5', 'A4', 'A3', 'A2', 'A1'],
    variants: ['x50', 'x100', 'x250', 'x500'],
    unit: 'commande',
    basePrice: 1500,
    isService: true,
    costRatio: 0.35,
  ),
  const _Spec(
    category: 'Cartouches',
    brands: ['HP', 'Canon', 'Epson', 'Brother', 'Lexmark'],
    items: ['Cartouche noire', 'Cartouche couleur', 'Toner'],
    variants: ['original', 'compatible'],
    sizes: ['petit', 'standard', 'XL'],
    unit: 'pièce',
    basePrice: 4500,
  ),
  const _Spec(
    category: 'Papeterie',
    brands: ['Bic', 'Pilot', 'Staedtler', 'Maped', 'Local'],
    items: ['Stylo', 'Cahier', 'Enveloppe', 'Classeur', 'Agrafeuse'],
    variants: ['bleu', 'noir', 'rouge', 'vert'],
    sizes: ['unité', 'pack x10', 'pack x50'],
    unit: 'pièce',
    basePrice: 150,
  ),
  const _Spec(
    category: 'Finition',
    brands: ['GBC', 'Fellowes', 'Local Bind'],
    items: ['Reliure spirale', 'Plastification', 'Massicot'],
    sizes: ['A4', 'A3', 'A5'],
    variants: ['fine', 'épaisse', 'brillante', 'mate'],
    unit: 'pièce',
    isService: true,
    basePrice: 500,
    costRatio: 0.4,
  ),
  const _Spec(
    category: 'Identité',
    brands: [''],
    items: ['Carte de visite', 'Tampon encreur', 'Cachet', 'Badge'],
    sizes: ['x100', 'x250', 'x500', 'x1000'],
    variants: ['mat', 'brillant', 'vernis sélectif'],
    unit: 'commande',
    isService: true,
    basePrice: 5000,
    costRatio: 0.4,
  ),
  const _Spec(
    category: 'Grand format',
    brands: ['Local Print', 'ProPrint'],
    items: ['Kakemono', 'Bâche', 'Panneau', 'Roll-up', 'Autocollant'],
    sizes: ['80x200', '100x200', '120x200', '2x1 m', '3x2 m'],
    variants: ['mat', 'brillant'],
    unit: 'commande',
    isService: true,
    basePrice: 12000,
    costRatio: 0.4,
  ),
];

List<_Spec> _salon() => [
  const _Spec(
    category: 'Soins capillaires',
    brands: [
      'Dark and Lovely',
      'Cantu',
      'ORS',
      'SoftSheen',
      'Olive Oil',
      'Mizani',
      'Shea Moisture',
      'Dove',
      'Garnier',
      'Loreal',
    ],
    items: [
      'Shampooing',
      'Après-shampoing',
      'Masque',
      'Huile capillaire',
      'Sérum',
    ],
    sizes: ['100 ml', '250 ml', '400 ml', '1 L'],
    unit: 'flacon',
    basePrice: 1500,
  ),
  const _Spec(
    category: 'Coiffure',
    brands: [
      'Dark and Lovely',
      'ORS',
      'Olive Oil',
      'Mizani',
      'Cantu',
      'SoftSheen',
    ],
    items: ['Défrisant', 'Gel', 'Spray', 'Cire', 'Tresse kanekalon'],
    sizes: ['kit', '250 ml', 'pack x1', 'pack x3'],
    unit: 'pièce',
    basePrice: 2000,
  ),
  const _Spec(
    category: 'Services coiffure',
    brands: [''],
    items: [
      'Coupe homme',
      'Coupe femme',
      'Tresses',
      'Tissages',
      'Locks',
      'Lissage',
      'Coloration',
      'Brushing',
    ],
    variants: ['court', 'mi-long', 'long'],
    sizes: ['simple', 'avec soin', 'premium'],
    unit: 'prestation',
    isService: true,
    basePrice: 2500,
    costRatio: 0.25,
  ),
  const _Spec(
    category: 'Onglerie',
    brands: ['Essie', 'OPI', 'Kiko', 'Local Nail'],
    items: ['Vernis', 'Gel UV', 'Faux ongles', 'Manucure', 'Pédicure'],
    variants: ['nude', 'rouge', 'noir', 'french', 'paillettes'],
    sizes: ['simple', 'pose complète'],
    unit: 'prestation',
    isService: true,
    basePrice: 2000,
    costRatio: 0.3,
  ),
  const _Spec(
    category: 'Extensions',
    brands: ['X-Pression', 'Darling', 'Sensationnel', 'Outre'],
    items: ['Mèches', 'Closure', 'Frontal', 'Perruque'],
    variants: ['1B', '30', '27', 'ombre', 'gris'],
    sizes: ['10 pouces', '14 pouces', '18 pouces', '22 pouces'],
    unit: 'paquet',
    basePrice: 2500,
  ),
];

List<_Spec> _services() => [
  const _Spec(
    category: 'Réparation téléphone',
    brands: [
      'Samsung',
      'Tecno',
      'Infinix',
      'Itel',
      'iPhone',
      'Redmi',
      'Huawei',
      'Oppo',
      'Nokia',
      'Vivo',
    ],
    items: ['Écran', 'Batterie', 'Connecteur charge', 'Caméra', 'Diagnostic'],
    variants: ['A14', 'A24', 'Spark 10', 'Hot 30', 'Note 12', '12', '13', '14'],
    unit: 'prestation',
    isService: true,
    basePrice: 8000,
    costRatio: 0.45,
  ),
  const _Spec(
    category: 'Accessoires',
    brands: [
      'Samsung',
      'Tecno',
      'Infinix',
      'Itel',
      'iPhone',
      'Redmi',
      'Oraimo',
      'Baseus',
    ],
    items: ['Coque', 'Verre trempé', 'Chargeur', 'Écouteurs', 'Câble USB'],
    variants: ['noir', 'transparent', 'bleu', 'rouge'],
    sizes: ['standard', 'renforcé'],
    unit: 'pièce',
    basePrice: 1500,
  ),
  const _Spec(
    category: 'Informatique',
    brands: ['HP', 'Dell', 'Lenovo', 'Asus', 'Acer'],
    items: [
      'Nettoyage PC',
      'Installation Windows',
      'Changement disque',
      'Clavier',
      'RAM',
    ],
    sizes: ['4 Go', '8 Go', '256 Go', '512 Go', 'prestation'],
    unit: 'prestation',
    isService: true,
    basePrice: 7500,
    costRatio: 0.4,
  ),
  const _Spec(
    category: 'Électroménager',
    brands: ['Binatone', 'Nasco', 'Hisense', 'LG', 'Samsung'],
    items: ['Réparation fer', 'Réparation ventilateur', 'Réparation frigo'],
    sizes: ['diagnostic', 'pièce + main d’œuvre'],
    unit: 'prestation',
    isService: true,
    basePrice: 5000,
    costRatio: 0.4,
  ),
  const _Spec(
    category: 'Moto & vélo',
    brands: ['Honda', 'Yamaha', 'TVS', 'Local Bike'],
    items: ['Chambre à air', 'Pneu', 'Bougie', 'Câble frein', 'Huile moteur'],
    sizes: ['unité', 'paire'],
    variants: ['125', '110', 'VTT'],
    unit: 'pièce',
    basePrice: 2500,
  ),
];
