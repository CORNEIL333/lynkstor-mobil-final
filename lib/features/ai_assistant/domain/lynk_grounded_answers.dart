import '../../../core/database/app_database.dart';
import '../../../shared/services/report_service.dart';

/// Fiche produit compacte pour la recherche d'entité (« il reste du ciment ? »).
class LynkProductFact {
  const LynkProductFact({
    required this.name,
    required this.qty,
    required this.unit,
    required this.salePrice,
    required this.threshold,
    required this.tracked,
  });

  final String name;
  final double qty;
  final String unit;
  final double salePrice;
  final double threshold;
  final bool tracked;
}

/// Débiteur indexé pour la recherche d'entité (« qui est Paul ? »).
class LynkDebtorFact {
  const LynkDebtorFact({required this.name, required this.balance});

  final String name;
  final double balance;
}

/// Instantané chiffré du commerce, calculé 100 % localement.
///
/// Les fenêtres hier/semaine/mois et les index d'entités sont facultatifs :
/// absents (hasTrendData=false), le moteur renvoie null sur ces questions et
/// le cerveau cloud prend le relais — jamais de chiffre inventé.
class LynkShopSnapshot {
  const LynkShopSnapshot({
    required this.businessName,
    required this.currency,
    required this.salesCount,
    required this.sold,
    required this.collected,
    required this.credit,
    required this.expenses,
    required this.profit,
    required this.topProduct,
    required this.stockCost,
    required this.stockSale,
    required this.outCount,
    required this.lowCount,
    required this.totalDebt,
    required this.lowStock,
    required this.debtors,
    this.hasTrendData = false,
    this.yesterdaySold = 0,
    this.yesterdayProfit = 0,
    this.weekSold = 0,
    this.weekProfit = 0,
    this.monthSold = 0,
    this.monthProfit = 0,
    this.monthExpenses = 0,
    this.monthSalesCount = 0,
    this.debtorCount = 0,
    this.customerCount = 0,
    this.productCount = 0,
    this.returnsCount = 0,
    this.returnsTotal = 0,
    this.partialPaymentsCount = 0,
    this.topProducts = const [],
    this.dormantProducts = const [],
    this.expenseCategories = const {},
    this.debtorsByName = const {},
    this.productsByName = const {},
  });

  final String businessName;
  final String currency;
  final int salesCount;
  final double sold;
  final double collected;
  final double credit;
  final double expenses;
  final double profit;
  final String? topProduct;
  final double stockCost;
  final double stockSale;
  final int outCount;
  final int lowCount;
  final double totalDebt;
  final List<String> lowStock;
  final List<String> debtors;

  /// Fenêtres hiér / 7 jours / 30 jours fournies par le builder de contexte.
  final bool hasTrendData;
  final double yesterdaySold;
  final double yesterdayProfit;
  final double weekSold;
  final double weekProfit;
  final double monthSold;
  final double monthProfit;
  final double monthExpenses;
  final int monthSalesCount;

  final int debtorCount;
  final int customerCount;
  final int productCount;
  final int returnsCount;
  final double returnsTotal;
  final int partialPaymentsCount;

  /// « Riz 25kg — 12 pièces » (top 3 du jour, quantités vendues).
  final List<String> topProducts;

  /// Produits suivis vendus à zéro depuis 30 jours.
  final List<String> dormantProducts;

  /// Poste de dépense → montant, cumuls du mois.
  final Map<String, double> expenseCategories;

  final Map<String, LynkDebtorFact> debtorsByName;
  final Map<String, LynkProductFact> productsByName;
}

/// Cerveau hors-ligne de Lynk : comprend ~20 familles de questions métier et
/// répond avec des chiffres calculés sur la base locale — instantané, exact,
/// sans réseau. Les conseils (« comment améliorer… ») et l'inconnu remontent
/// au cerveau cloud.
class LynkGroundedAnswers {
  static String money(double value) => '${value.toStringAsFixed(0)} FCFA';

  // ————— Normalisation —————

  static const _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'é': 'e', 'è': 'e',
    'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ò': 'o', 'ó': 'o',
    'ô': 'o', 'ö': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c',
    'ñ': 'n', '’': ' ',
  };

  /// minuscules, sans accents ni ponctuation, espaces comprimés, encadrés.
  static String normalize(String value) {
    var s = value.toLowerCase();
    _accents.forEach((from, to) => s = s.replaceAll(from, to));
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return ' $s ';
  }

  static bool _hasWord(String normalized, List<String> words) {
    for (final w in words) {
      if (RegExp('\\b$w\\b').hasMatch(normalized)) return true;
    }
    return false;
  }

  static bool _hasSub(String normalized, List<String> parts) {
    for (final p in parts) {
      if (normalized.contains(p)) return true;
    }
    return false;
  }

  // ————— Réponse principale —————

  static String? tryAnswer(
    String question,
    LynkShopSnapshot snap, {
    required bool isEn,
  }) {
    final n = normalize(question);

    // Garde : une demande de conseil raisonne, elle ne se calcule pas.
    if (_hasSub(n, ['comment amelior', 'conseil', 'suggestion', 'ide ', 'ids ', 'que faire pour', 'devrai je', 'how to improve', 'any idea']) &&
        !_hasSub(n, ['combien'])) {
      return null;
    }

    // Garde : le « pourquoi » explicatif est du ressort du cloud.
    if (_hasWord(n, ['pourquoi', 'why'])) return null;

    final aboutProfit =
        _hasSub(n, ['benefice', 'profit', 'marge', 'gain']) ||
        _hasWord(n, ['benefices']);
    final aboutSales =
        _hasSub(n, [
          'chiffre', 'affaires', 'vente', 'revenue', 'turnover', 'recette',
          'encaisse brut',
        ]) ||
        _hasWord(n, ['ca']);
    final aboutCollected =
        _hasSub(n, ['encaiss', 'argent rec', 'argent rent', 'collected', 'rentr']);
    final aboutExpenses =
        _hasWord(n, ['depense', 'depenses', 'charge', 'charges', 'spent']) ||
        _hasSub(n, ['sortie d argent', 'argent sorti', 'debours', 'expense']);
    final aboutDebt =
        _hasSub(n, ['dette', 'doit', 'doivent', 'creanc', 'impay', 'credit', 'debt', 'owe', 'prete']);
    final aboutStock =
        _hasSub(n, ['stock', 'rupture', 'reappro', 'restock', 'reorder', 'inventaire', 'seuil', 'il reste']);
    final aboutTop =
        _hasSub(n, ['top', 'meilleur', 'marche le mieux', 'se vend le mieux', 'mieux vendu', 'best sell', 'produit phare', 'star ']);
    final aboutDormant =
        _hasSub(n, ['invendu', 'ne se vend', 'marche mal', 'dorment', 'peu vendu', 'lentement', 'slow']);
    final aboutBasket =
        _hasSub(n, ['panier', 'ticket', 'moyenne par vente', 'average basket', 'par vente en moyenne']);
    final aboutReturns =
        _hasSub(n, ['retour', 'avoir', 'rendu', 'refund', 'rembourse']);
    final aboutAdvance =
        _hasSub(n, ['acompte', 'partiel', 'avance recue']);
    final aboutCounts =
        _hasSub(n, ['combien de produit', 'combien de reference', 'nombre de produit', 'combien de client', 'nombre de client', 'combien de debiteur', 'mon catalogue', 'combien de gens']);
    final aboutTrend =
        _hasSub(n, ['evolue', 'compar', 'hier', 'la semaine', '7 jours', 'ce mois', 'du mois', 'this month', 'yesterday', 'dynamique']);

    final wantsYesterday = _hasWord(n, ['hier']) || _hasSub(n, ['yesterday']);
    final wantsWeek =
        _hasSub(n, ['cette semaine', 'la semaine', '7 jours', 'sept jours', 'this week']);
    final wantsMonth =
        _hasSub(n, ['ce mois', 'du mois', 'dans le mois', 'this month', 'du mois ci']) ||
        _hasWord(n, ['mois']);

    // Résolution d'entités (débiteur ou produit nommé dans la question).
    final debtorHit = _findDebtor(n, snap);
    final productHit = _findProduct(n, snap);

    // ————— Priorités —————

    // « Comment évoluent mes ventes ? » → comparaison directe, pas un chiffre brut.
    if (aboutTrend &&
        snap.hasTrendData &&
        !wantsYesterday &&
        !wantsWeek &&
        !wantsMonth &&
        !aboutCollected &&
        !aboutExpenses &&
        !aboutDebt &&
        !aboutStock) {
      return _trendAnswer(snap, isEn);
    }

    if (aboutProfit && !aboutDebt) {
      return _windowedProfit(n, snap, isEn, wantsYesterday, wantsWeek, wantsMonth);
    }
    if (aboutSales && !aboutStock && !aboutDebt && !aboutTop && !aboutDormant) {
      return _windowedSales(snap, isEn, wantsYesterday, wantsWeek, wantsMonth);
    }
    if (aboutCollected && !aboutDebt) {
      return isEn
          ? 'Collected today: ${money(snap.collected)} '
                '(payments received across ${snap.salesCount} sale(s)).'
          : 'Encaissé aujourd’hui : ${money(snap.collected)} '
                '(paiements reçus sur ${snap.salesCount} vente(s)).';
    }
    if (aboutExpenses) {
      return _expensesAnswer(snap, isEn);
    }
    if (aboutDebt && !aboutStock) {
      if (debtorHit != null) return _debtorAnswer(debtorHit, snap, isEn);
      final list = snap.debtors.isEmpty
          ? (isEn
                ? 'No customer currently owes money.'
                : 'Aucun client n’a de dette en ce moment.')
          : snap.debtors.take(5).join('\n');
      return isEn
          ? 'Total customer debt: ${money(snap.totalDebt)}.\n$list'
          : 'Dette clients totale : ${money(snap.totalDebt)}.\n$list';
    }
    if (aboutStock) {
      if (productHit != null) return _productAnswer(productHit, isEn);
      final watch = snap.lowStock.isEmpty
          ? (isEn
                ? 'No stock alert right now.'
                : 'Aucune alerte stock pour le moment.')
          : snap.lowStock.take(8).join('\n');
      return isEn
          ? 'Stock value (sale price) ${money(snap.stockSale)}. Out of stock: ${snap.outCount}. Below threshold: ${snap.lowCount}.\n$watch'
          : 'Valeur stock (prix de vente) ${money(snap.stockSale)}. Ruptures : ${snap.outCount}. Sous le seuil : ${snap.lowCount}.\n$watch';
    }
    if (aboutTop) {
      if (snap.topProducts.isEmpty) {
        final top = snap.topProduct == null || snap.topProduct == 'aucun'
            ? (isEn ? 'no sale yet today' : 'aucune vente encore aujourd’hui')
            : snap.topProduct!;
        return isEn
            ? 'Best seller today: $top.'
            : 'Meilleure vente du jour : $top.';
      }
      return isEn
          ? 'Top sellers today:\n${snap.topProducts.take(3).join('\n')}'
          : 'Meilleures ventes du jour :\n${snap.topProducts.take(3).join('\n')}';
    }
    if (aboutDormant) {
      if (!snap.hasTrendData) return null;
      if (snap.dormantProducts.isEmpty) {
        return isEn
            ? 'Nothing dormant — every tracked product sold at least once in the last 30 days.'
            : 'Rien de dormant : tous les produits suivis se sont vendus au moins une fois en 30 jours.';
      }
      final list = snap.dormantProducts.take(8).join('\n');
      return isEn
          ? 'No sales in the last 30 days:\n$list'
          : 'Invendus (aucune vente depuis 30 jours) :\n$list';
    }
    if (aboutBasket) {
      if (snap.salesCount == 0) {
        return isEn
            ? 'No sale yet today, so no average basket.'
            : 'Aucune vente pour l’instant aujourd’hui, pas encore de panier moyen.';
      }
      final basket = snap.sold / snap.salesCount;
      return isEn
          ? 'Average basket today: ${money(basket)} '
                '(${money(snap.sold)} over ${snap.salesCount} sales).'
          : 'Panier moyen du jour : ${money(basket)} '
                '(${money(snap.sold)} répartis sur ${snap.salesCount} vente(s)).';
    }
    if (aboutReturns) {
      if (!snap.hasTrendData) return null;
      if (snap.returnsCount == 0) {
        return isEn
            ? 'No product returned today.'
            : 'Aucun produit retourné aujourd’hui.';
      }
      return isEn
          ? 'Returns today: ${snap.returnsCount} refund(s) totalling ${money(snap.returnsTotal)}.'
          : 'Retours du jour : ${snap.returnsCount} retour(s) pour ${money(snap.returnsTotal)}.';
    }
    if (aboutAdvance) {
      if (!snap.hasTrendData) return null;
      if (snap.partialPaymentsCount == 0) {
        return isEn
            ? 'No partially paid sale today.'
            : 'Aucune vente payée partiellement aujourd’hui.';
      }
      return isEn
          ? '${snap.partialPaymentsCount} sale(s) partially paid today (advance received, balance on credit).'
          : '${snap.partialPaymentsCount} vente(s) payée(s) partiellement aujourd’hui (acompte reçu, solde à crédit).';
    }
    if (aboutCounts) {
      if (snap.productCount == 0 && snap.customerCount == 0) return null;
      return isEn
          ? 'Catalogue: ${snap.productCount} product(s) (${snap.outCount} out of stock, ${snap.lowCount} below threshold). '
                'Customers: ${snap.customerCount}, of whom ${snap.debtorCount} currently owe money.'
          : 'Catalogue : ${snap.productCount} produit(s) (${snap.outCount} en rupture, ${snap.lowCount} sous le seuil). '
                'Clients : ${snap.customerCount}, dont ${snap.debtorCount} endettés en ce moment.';
    }
    if (aboutTrend && snap.hasTrendData) {
      return _trendAnswer(snap, isEn);
    }

    // Entité nommée sans thème précis : Paul → sa dette ; Ciment → sa fiche.
    if (debtorHit != null) return _debtorAnswer(debtorHit, snap, isEn);
    if (productHit != null) return _productAnswer(productHit, isEn);

    // Petit talk immédiatement hors-ligne.
    final smallTalk = _smallTalk(n, snap, isEn);
    if (smallTalk != null) return smallTalk;

    return null;
  }

  // ————— Sous-réponses —————

  static String? _windowedProfit(
    String n,
    LynkShopSnapshot snap,
    bool isEn,
    bool yesterday,
    bool week,
    bool month,
  ) {
    if ((yesterday || week || month) && !snap.hasTrendData) return null;
    if (week) {
      return isEn
          ? 'Estimated profit over the last 7 days: ${money(snap.weekProfit)}.'
          : 'Bénéfice estimé sur 7 jours : ${money(snap.weekProfit)}.';
    }
    if (month) {
      return isEn
          ? 'Estimated profit this month: ${money(snap.monthProfit)} '
                '(expenses ${money(snap.monthExpenses)}).'
          : 'Bénéfice estimé ce mois : ${money(snap.monthProfit)} '
                '(dépenses ${money(snap.monthExpenses)}).';
    }
    if (yesterday) {
      return isEn
          ? 'Yesterday’s estimated profit: ${money(snap.yesterdayProfit)}.'
          : 'Bénéfice estimé d’hier : ${money(snap.yesterdayProfit)}.';
    }
    return isEn
        ? 'Today’s estimated profit for ${snap.businessName} is ${money(snap.profit)} '
              '(collected ${money(snap.collected)} minus expenses ${money(snap.expenses)}).'
        : 'Bénéfice estimé aujourd’hui pour ${snap.businessName} : ${money(snap.profit)} '
              '(encaissé ${money(snap.collected)} − dépenses ${money(snap.expenses)}).';
  }

  static String? _windowedSales(
    LynkShopSnapshot snap,
    bool isEn,
    bool yesterday,
    bool week,
    bool month,
  ) {
    if ((yesterday || week || month) && !snap.hasTrendData) return null;
    if (week) {
      return isEn
          ? 'Revenue over the last 7 days: ${money(snap.weekSold)}.'
          : 'Chiffre d’affaires sur 7 jours : ${money(snap.weekSold)}.';
    }
    if (month) {
      return isEn
          ? 'Revenue this month: ${money(snap.monthSold)} '
                'across ${snap.monthSalesCount} sale(s).'
          : 'Chiffre d’affaires ce mois : ${money(snap.monthSold)} '
                '(${snap.monthSalesCount} vente(s)).';
    }
    if (yesterday) {
      return isEn
          ? 'Yesterday’s revenue: ${money(snap.yesterdaySold)}.'
          : 'Chiffre d’affaires d’hier : ${money(snap.yesterdaySold)}.';
    }
    final top = snap.topProduct == null || snap.topProduct == 'aucun'
        ? (isEn ? 'no top product yet' : 'pas encore de meilleur produit')
        : snap.topProduct!;
    return isEn
        ? 'Today: ${snap.salesCount} sales, revenue ${money(snap.sold)}, collected ${money(snap.collected)}, '
              'credit ${money(snap.credit)}. Top product: $top.'
        : 'Aujourd’hui : ${snap.salesCount} vente(s), CA ${money(snap.sold)}, encaissé ${money(snap.collected)}, '
              'crédit ${money(snap.credit)}. Meilleur produit : $top.';
  }

  static String _expensesAnswer(LynkShopSnapshot snap, bool isEn) {
    final cats = snap.expenseCategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = cats.isEmpty
        ? null
        : cats.take(3).map((e) => '- ${e.key} : ${money(e.value)}').join('\n');
    if (isEn) {
      return top == null
          ? 'Expenses today: ${money(snap.expenses)}.'
          : 'Expenses today: ${money(snap.expenses)}. '
                'Main categories this month:\n$top';
    }
    return top == null
        ? 'Dépenses du jour : ${money(snap.expenses)}.'
        : 'Dépenses du jour : ${money(snap.expenses)}. '
              'Principaux postes du mois : \n$top';
  }

  static String? _trendAnswer(LynkShopSnapshot snap, bool isEn) {
    final today = snap.sold;
    final yesterday = snap.yesterdaySold;
    final weekAvg = snap.weekSold / 7;
    final vsYesterday = today - yesterday;
    final momentum = isEn
        ? 'Today ${vsYesterday >= 0 ? 'is ahead of' : 'is behind'} yesterday by ${money(vsYesterday.abs())} '
              '(7-day average: ${money(weekAvg)} per day).'
        : 'Aujourd’hui ${vsYesterday >= 0 ? 'au-dessus' : 'en dessous'} d’hier de ${money(vsYesterday.abs())} '
              '(moyenne 7 jours : ${money(weekAvg)} par jour).';
    return isEn
        ? 'Revenue today ${money(today)}, yesterday ${money(yesterday)}, month to date ${money(snap.monthSold)}. $momentum'
        : 'CA du jour ${money(today)}, hier ${money(yesterday)}, mois en cours ${money(snap.monthSold)}. $momentum';
  }

  static String _debtorAnswer(
    LynkDebtorFact debtor,
    LynkShopSnapshot snap,
    bool isEn,
  ) {
    final ranked = snap.debtorRankingOf(debtor.name);
    return isEn
        ? '${debtor.name} owes you ${money(debtor.balance)}$ranked. '
              'Total customer debt: ${money(snap.totalDebt)}.'
        : '${debtor.name} vous doit ${money(debtor.balance)}$ranked. '
              'Dette totale des clients : ${money(snap.totalDebt)}.';
  }

  static String _productAnswer(LynkProductFact product, bool isEn) {
    if (!product.tracked) {
      return isEn
          ? '${product.name} is sold without stock tracking '
                '(sale price ${money(product.salePrice)}).'
          : '${product.name} est vendu sans suivi de stock '
                '(prix de vente ${money(product.salePrice)}).';
    }
    final String state;
    if (product.qty <= 0) {
      state = isEn ? 'OUT OF STOCK' : 'EN RUPTURE';
    } else if (product.qty <= product.threshold) {
      state = isEn ? 'below threshold' : 'sous le seuil';
    } else {
      state = isEn ? 'in stock' : 'en stock';
    }
    return isEn
        ? '${product.name}: ${product.qty.toStringAsFixed(2)} ${product.unit} — $state '
              '(threshold ${product.threshold.toStringAsFixed(2)}), sale price ${money(product.salePrice)}.'
        : '${product.name} : ${product.qty.toStringAsFixed(2)} ${product.unit} — $state '
              '(seuil ${product.threshold.toStringAsFixed(2)}), prix ${money(product.salePrice)}.';
  }

  static String? _smallTalk(String n, LynkShopSnapshot snap, bool isEn) {
    final greeting = _hasWord(n, [
      'bonjour', 'salut', 'coucou', 'hello', 'bonsoir', 'hey', 'yo',
    ]);
    final thanks = _hasWord(n, ['merci', 'thanks', 'thank']);
    final identity =
        _hasSub(n, ['tu es qui', 'qui es tu', 'ton nom', 'sais tu faire', 'tu sais faire', 'a quoi tu sers', 'what can you do', 'who are you']) ||
        _hasWord(n, ['aide']);
    if (identity) {
      return isEn
          ? 'I am Lynk, your shop brain. Anything numeric answers offline and '
                'instantly: sales, revenue, collections, expenses, profit, debts '
                '(customer by customer), stock and alerts, returns, average '
                'basket, yesterday/week/month figures, top and dormant products. '
                'Bigger advice is thought through online.'
          : 'Je suis Lynk, le cerveau de ta boutique. Tout ce qui est chiffre '
                'répond hors ligne et instantanément : ventes, CA, encaissements, '
                'dépenses, bénéfice, dettes client par client, stock et alertes, '
                'retours, panier moyen, chiffres hier / semaine / mois, top et '
                'invendus. Les conseils plus larges, je les réfléchis en ligne.';
    }
    if (greeting) {
      return isEn
          ? 'Hello! Today so far: ${snap.salesCount} sale(s), ${money(snap.sold)} in revenue. '
                'Ask me anything about sales, debts or stock — offline.'
          : 'Bonjour ! Aujourd’hui : ${snap.salesCount} vente(s), ${money(snap.sold)} de CA. '
                'Demande-moi ventes, dettes ou stock — ça répond hors ligne.';
    }
    if (thanks) {
      return isEn ? 'Anytime. I am one question away.' : 'Avec plaisir. Je suis là, pose ta prochaine question.';
    }
    return null;
  }

  // ————— Construction depuis la base locale —————

  static LynkShopSnapshot fromReports({
    required Business business,
    required DailyReport report,
    required Map<String, double> stock,
    required List<Product> lowStock,
    required List<Customer> debtors,
    bool hasTrendData = false,
    double yesterdaySold = 0,
    double yesterdayProfit = 0,
    double weekSold = 0,
    double weekProfit = 0,
    double monthSold = 0,
    double monthProfit = 0,
    double monthExpenses = 0,
    int monthSalesCount = 0,
    int customerCount = 0,
    int productCount = 0,
    int returnsCount = 0,
    double returnsTotal = 0,
    List<String> topProducts = const [],
    List<String> dormantProducts = const [],
    Map<String, double> expenseCategories = const {},
    List<Product> allProducts = const [],
  }) {
    final totalDebt = debtors.fold<double>(0, (sum, c) => sum + c.balance);
    return LynkShopSnapshot(
      businessName: business.name,
      currency: business.currency,
      salesCount: report.salesCount,
      sold: report.sold,
      collected: report.collected,
      credit: report.credit,
      expenses: report.expenses,
      profit: report.profitEstimate,
      topProduct: report.topProduct,
      stockCost: stock['cost_value'] ?? 0,
      stockSale: stock['sale_value'] ?? 0,
      outCount: (stock['out_count'] ?? 0).round(),
      lowCount: (stock['low_count'] ?? 0).round(),
      totalDebt: totalDebt,
      lowStock: [
        for (final p in lowStock.take(12))
          '- ${p.name}: ${p.stockQty.toStringAsFixed(2)} ${p.unit}',
      ],
      debtors: [
        for (final c in debtors.take(10))
          '- ${c.name}: ${c.balance.toStringAsFixed(0)} FCFA',
      ],
      hasTrendData: hasTrendData,
      yesterdaySold: yesterdaySold,
      yesterdayProfit: yesterdayProfit,
      weekSold: weekSold,
      weekProfit: weekProfit,
      monthSold: monthSold,
      monthProfit: monthProfit,
      monthExpenses: monthExpenses,
      monthSalesCount: monthSalesCount,
      debtorCount: debtors.length,
      customerCount: customerCount,
      productCount: productCount,
      returnsCount: returnsCount,
      returnsTotal: returnsTotal,
      partialPaymentsCount: report.partialPaymentsCount,
      topProducts: topProducts,
      dormantProducts: dormantProducts,
      expenseCategories: expenseCategories,
      debtorsByName: {
        for (final c in debtors.take(50))
          normalize(c.name).trim(): LynkDebtorFact(
            name: c.name,
            balance: c.balance,
          ),
      },
      productsByName: {
        for (final p in allProducts.take(400))
          if (!p.isDeleted)
            normalize(p.name).trim(): LynkProductFact(
              name: p.name,
              qty: p.stockQty,
              unit: p.unit,
              salePrice: p.salePrice,
              threshold: p.lowStockThreshold,
              tracked: p.trackStock,
            ),
      },
    );
  }

  // ————— Recherche d'entités —————

  static LynkDebtorFact? _findDebtor(String n, LynkShopSnapshot snap) {
    for (final entry in snap.debtorsByName.entries) {
      if (entry.key.length >= 3 && n.contains(' ${entry.key} ')) {
        return entry.value;
      }
    }
    return null;
  }

  static LynkProductFact? _findProduct(String n, LynkShopSnapshot snap) {
    LynkProductFact? best;
    int bestLen = 0;
    for (final entry in snap.productsByName.entries) {
      if (entry.key.length >= 4 && n.contains(' ${entry.key} ')) {
        // Le nom le plus long gagne (« riz 25kg » bat « riz »).
        if (entry.key.length > bestLen) {
          best = entry.value;
          bestLen = entry.key.length;
        }
      }
    }
    return best;
  }
}

extension _DebtorRanking on LynkShopSnapshot {
  /// « (rangement n/n) » discret pour la réponse individuelle.
  String debtorRankingOf(String name) {
    final sorted = debtorsByName.values.toList()
      ..sort((a, b) => b.balance.compareTo(a.balance));
    final index = sorted.indexWhere(
      (d) => d.name.toLowerCase() == name.toLowerCase(),
    );
    if (index < 0 || sorted.length < 2) return '';
    return ' (rank ${index + 1} of ${sorted.length})';
  }
}
