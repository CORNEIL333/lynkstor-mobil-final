/// Modules activés par profil sectoriel.
class SectorModules {
  SectorModules._();

  static const all = [
    'pos',
    'stock',
    'clients',
    'dettes',
    'depenses',
    'fournisseurs',
    'achats',
    'inventaire',
    'devis',
    'commandes',
    'factures',
    'livraisons',
    'employes',
    'pointage',
    'rapports',
    'sauvegardes',
    'ia',
  ];

  static List<String> forSector(String sector) {
    switch (sector) {
      case 'superette':
        return [
          'pos',
          'stock',
          'clients',
          'dettes',
          'depenses',
          'fournisseurs',
          'achats',
          'inventaire',
          'rapports',
          'sauvegardes',
          'ia',
        ];
      case 'grossiste':
        return [
          'pos',
          'stock',
          'clients',
          'dettes',
          'depenses',
          'fournisseurs',
          'achats',
          'devis',
          'commandes',
          'factures',
          'livraisons',
          'employes',
          'pointage',
          'rapports',
          'sauvegardes',
        ];
      case 'quincaillerie':
        return [
          'pos',
          'stock',
          'clients',
          'dettes',
          'depenses',
          'fournisseurs',
          'achats',
          'devis',
          'commandes',
          'factures',
          'livraisons',
          'employes',
          'pointage',
          'rapports',
          'sauvegardes',
          'ia',
        ];
      case 'imprimerie':
        return [
          'pos',
          'clients',
          'devis',
          'commandes',
          'factures',
          'depenses',
          'employes',
          'pointage',
          'rapports',
          'sauvegardes',
          'ia',
        ];
      case 'salon':
        return [
          'pos',
          'clients',
          'depenses',
          'employes',
          'pointage',
          'rapports',
          'sauvegardes',
          'ia',
        ];
      case 'ambulant':
        return [
          'pos',
          'stock',
          'clients',
          'dettes',
          'depenses',
          'rapports',
          'sauvegardes',
          'ia',
        ];
      case 'services':
        return [
          'pos',
          'clients',
          'devis',
          'factures',
          'depenses',
          'stock',
          'rapports',
          'sauvegardes',
          'ia',
        ];
      case 'boutique':
      default:
        return [
          'pos',
          'stock',
          'clients',
          'dettes',
          'depenses',
          'fournisseurs',
          'achats',
          'inventaire',
          'rapports',
          'sauvegardes',
          'ia',
        ];
    }
  }

  static bool isEnabled(List<String> active, String module) =>
      active.contains(module);

  /// Modules ajoutés aux commerces existants lors d'une évolution de profil.
  /// Aucun module déjà choisi par le propriétaire n'est retiré.
  static List<String> requiredForExistingSector(String sector) {
    switch (sector) {
      case 'grossiste':
      case 'imprimerie':
        return const ['pos', 'employes', 'pointage'];
      case 'quincaillerie':
        return const ['pos', 'employes', 'pointage'];
      case 'salon':
        return const ['pos', 'employes', 'pointage'];
      default:
        return const ['pos'];
    }
  }

  static List<String> repairExisting(String sector, List<String> active) {
    final merged = <String>[...active];
    for (final module in requiredForExistingSector(sector)) {
      if (!merged.contains(module)) merged.add(module);
    }
    return merged;
  }

  /// Route → module métier.
  static String? moduleForRoute(String path) {
    if (path.startsWith('/sale') || path == '/sales') return 'pos';
    if (path.startsWith('/stock') ||
        path.startsWith('/products') ||
        path.startsWith('/inventory')) {
      return path.startsWith('/inventory') ? 'inventaire' : 'stock';
    }
    if (path.startsWith('/customers')) return 'clients';
    if (path.startsWith('/debts')) return 'dettes';
    if (path.startsWith('/expenses')) return 'depenses';
    if (path.startsWith('/suppliers')) return 'fournisseurs';
    if (path.startsWith('/purchases')) return 'achats';
    if (path.startsWith('/quotes')) return 'devis';
    if (path.startsWith('/invoices')) return 'factures';
    if (path.startsWith('/deliveries')) return 'livraisons';
    if (path.startsWith('/employees')) return 'employes';
    if (path.startsWith('/attendance')) return 'pointage';
    if (path.startsWith('/reports')) return 'rapports';
    if (path.startsWith('/backup')) return 'sauvegardes';
    if (path.startsWith('/ai')) return 'ia';
    return null;
  }
}
