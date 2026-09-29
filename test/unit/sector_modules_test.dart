import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/config/sector_modules.dart';

void main() {
  test('ambulant has reduced modules', () {
    final m = SectorModules.forSector('ambulant');
    expect(m.contains('pos'), isTrue);
    expect(m.contains('livraisons'), isFalse);
    expect(m.contains('sauvegardes'), isTrue);
  });

  test('grossiste includes livraisons and devis', () {
    final m = SectorModules.forSector('grossiste');
    expect(m.contains('livraisons'), isTrue);
    expect(m.contains('devis'), isTrue);
  });

  test('quincaillerie includes caisse, employees and attendance', () {
    final modules = SectorModules.forSector('quincaillerie');
    expect(modules, containsAll(['pos', 'employes', 'pointage']));
  });

  test(
    'existing quincaillerie profile is repaired without removing choices',
    () {
      final repaired = SectorModules.repairExisting('quincaillerie', [
        'stock',
        'fournisseurs',
      ]);
      expect(
        repaired,
        containsAll(['stock', 'fournisseurs', 'pos', 'employes', 'pointage']),
      );
      expect(repaired.where((module) => module == 'pos'), hasLength(1));
    },
  );

  test('moduleForRoute maps paths', () {
    expect(SectorModules.moduleForRoute('/sale/new'), 'pos');
    expect(SectorModules.moduleForRoute('/backup'), 'sauvegardes');
    expect(SectorModules.moduleForRoute('/debts'), 'dettes');
  });
}
