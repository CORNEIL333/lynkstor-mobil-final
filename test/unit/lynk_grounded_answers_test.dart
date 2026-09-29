import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/features/ai_assistant/domain/lynk_grounded_answers.dart';

void main() {
  const snap = LynkShopSnapshot(
    businessName: 'Boutique Akwa',
    currency: 'FCFA',
    salesCount: 4,
    sold: 18500,
    collected: 15000,
    credit: 3500,
    expenses: 2000,
    profit: 13000,
    topProduct: 'Riz 25kg',
    stockCost: 80000,
    stockSale: 120000,
    outCount: 1,
    lowCount: 2,
    totalDebt: 12000,
    lowStock: ['- Huile: 1.00 L'],
    debtors: ['- Paul: 12000 FCFA'],
  );

  // Snapshot enrichi comme le produit BusinessAiContextBuilder en production.
  const rich = LynkShopSnapshot(
    businessName: 'Boutique Akwa',
    currency: 'FCFA',
    salesCount: 4,
    sold: 18500,
    collected: 15000,
    credit: 3500,
    expenses: 2000,
    profit: 13000,
    topProduct: 'Riz 25kg',
    stockCost: 80000,
    stockSale: 120000,
    outCount: 1,
    lowCount: 2,
    totalDebt: 17000,
    lowStock: ['- Huile: 1.00 L', '- Ciment: 0.00 sac'],
    debtors: ['- Paul: 12000 FCFA', '- Awa: 5000 FCFA'],
    hasTrendData: true,
    yesterdaySold: 21000,
    yesterdayProfit: 14000,
    weekSold: 130000,
    weekProfit: 88000,
    monthSold: 520000,
    monthProfit: 310000,
    monthExpenses: 90000,
    monthSalesCount: 87,
    debtorCount: 2,
    customerCount: 45,
    productCount: 120,
    returnsCount: 1,
    returnsTotal: 2500,
    partialPaymentsCount: 2,
    topProducts: ['- Riz 25kg — 12', '- Huile 1L — 8'],
    dormantProducts: ['- Antivol (3 en stock)'],
    expenseCategories: {'Loyer': 45000, 'Transport': 20000},
    debtorsByName: {
      'paul': LynkDebtorFact(name: 'Paul', balance: 12000),
      'awa': LynkDebtorFact(name: 'Awa', balance: 5000),
    },
    productsByName: {
      'huile': LynkProductFact(
        name: 'Huile', qty: 1, unit: 'L', salePrice: 1500,
        threshold: 2, tracked: true,
      ),
      'ciment': LynkProductFact(
        name: 'Ciment', qty: 0, unit: 'sac', salePrice: 6500,
        threshold: 5, tracked: true,
      ),
      'parfum x': LynkProductFact(
        name: 'Parfum X', qty: 7, unit: 'pièce', salePrice: 4000,
        threshold: 1, tracked: false,
      ),
    },
  );

  String? ask(String q, {bool isEn = false, LynkShopSnapshot? s}) =>
      LynkGroundedAnswers.tryAnswer(q, s ?? rich, isEn: isEn);

  group('contrats historiques préservés', () {
    test('ventes du jour', () {
      final a = ask(
        'Quel est mon chiffre d’affaires aujourd’hui ?',
        s: snap,
      );
      expect(a, contains('18500'));
      expect(a, contains('4 vente'));
    });
    test('dettes', () {
      final a = ask('Qui me doit le plus en ce moment ?', s: snap);
      expect(a, contains('12000'));
      expect(a, contains('Paul'));
    });
    test('stock', () {
      final a = ask('Que dois-je réapprovisionner en priorité ?', s: snap);
      expect(a, contains('Huile'));
      expect(a, contains('Ruptures'));
    });
    test('hors sujet → null', () {
      expect(ask('Quelle est la capitale du Cameroun ?', s: snap), isNull);
    });
  });

  group('fenêtres temporelles', () {
    test('CA d’hier', () {
      expect(ask('Quel était le chiffre d’affaires hier ?'), contains('21000'));
    });
    test('bénéfice du mois', () {
      final a = ask('Mon bénéfice ce mois-ci ?');
      expect(a, contains('310000'));
      expect(a, contains('90000'));
    });
    test('CA sur 7 jours', () {
      expect(ask('Chiffre d’affaires de la semaine ?'), contains('130000'));
    });
    test('tendance générale', () {
      final a = ask('Comment évoluent mes ventes ?');
      expect(a, allOf(contains('18500'), contains('21000'), contains('520000')));
    });
    test('fenêtre demandée sans données → null (le cloud prendra)', () {
      expect(ask('Chiffre d’affaires de la semaine ?', s: snap), isNull);
    });
  });

  group('nouvelles familles de questions', () {
    test('dépenses avec categories', () {
      final a = ask('Où sont passées mes dépenses ?');
      expect(a, contains('2000'));
      expect(a, contains('Loyer'));
    });
    test('encaissements', () {
      expect(ask('Combien j’ai encaissé aujourd’hui ?'), contains('15000'));
    });
    test('panier moyen', () {
      final a = ask('Quel est mon panier moyen ?');
      expect(a, contains('4625'));
    });
    test('retours', () {
      expect(ask('J’ai eu des retours aujourd’hui ?'), contains('2500'));
    });
    test('acomptes', () {
      expect(ask('Il y a des acomptes en attente ?'), contains('2 vente'));
    });
    test('comptes catalogue et clients', () {
      final a = ask('Combien de clients et de produits dans mon catalogue ?');
      expect(a, contains('120'));
      expect(a, contains('45'));
      expect(a, contains('2 endettés'));
    });
    test('top ventes du jour', () {
      final a = ask('Mes meilleurs ventes du jour ?');
      expect(a, contains('Riz 25kg'));
      expect(a, contains('Huile 1L'));
    });
    test('invendus', () {
      final a = ask('Quels produits ne se vendent pas ?');
      expect(a, contains('Antivol'));
    });
  });

  group('résolution d’entités nommées', () {
    test('dette d’un client nommé', () {
      final a = ask('Combien me doit Paul ?');
      expect(a, contains('Paul vous doit 12000'));
      expect(a, isNot(contains('Awa')));
    });
    test('client nommé sans thème → sa dette', () {
      expect(ask('Awa ?'), contains('Awa vous doit 5000'));
    });
    test('produit nommé → sa fiche stock', () {
      final a = ask('Il reste du ciment ?');
      expect(a, contains('Ciment : 0.00 sac'));
      expect(a, contains('RUPTURE'));
    });
    test('produit nommé avec thème stock', () {
      expect(ask('Le stock d’huile est-il suffisant ?'), contains('Huile : 1.00 L'));
    });
  });

  group('petit talk et gardes', () {
    test('salutation répond hors ligne', () {
      expect(ask('Bonjour !'), contains('Bonjour'));
    });
    test('remerciement', () {
      expect(ask('Merci Lynk'), isNot(null));
    });
    test('qui es tu / que sais tu faire', () {
      final a = ask('Que sais-tu faire ?');
      expect(a, contains('hors ligne'));
    });
    test('conseil → null pour le cloud', () {
      expect(ask('Comment améliorer mes marges ce mois-ci ?'), isNull);
    });
    test('pourquoi → null pour le cloud', () {
      expect(ask('Pourquoi mes ventes ont baissé ?'), isNull);
    });
    test('anglais basique', () {
      final a = ask('How much did Paul owe me?', isEn: true, s: rich);
      expect(a, contains('Paul owes you 12000'));
    });
  });
}
