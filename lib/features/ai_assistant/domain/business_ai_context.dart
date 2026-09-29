import '../../../core/database/app_database.dart';
import '../../../shared/services/report_service.dart';
import 'lynk_grounded_answers.dart';

class AiPromptBundle {
  const AiPromptBundle({required this.systemPrompt, required this.snapshot});

  final String systemPrompt;
  final LynkShopSnapshot snapshot;
}

class BusinessAiContextBuilder {
  BusinessAiContextBuilder({required this.db, required this.reports});

  final AppDatabase db;
  final ReportService reports;

  /// Construit le prompt système pour le Qwen embarqué.
  Future<String> build(
    Business business, {
    String? userDisplayName,
    String languageCode = 'fr',
  }) async {
    final bundle = await buildBundle(
      business,
      userDisplayName: userDisplayName,
      languageCode: languageCode,
    );
    return bundle.systemPrompt;
  }

  Future<AiPromptBundle> buildBundle(
    Business business, {
    String? userDisplayName,
    String languageCode = 'fr',
  }) async {
    final report = await reports.daily(business.id);
    final stock = await reports.stockValue(business.id);
    final lowStock = await db.getProducts(business.id, lowStock: true);
    final debtors = await db.getDebtors(business.id);

    // Fenêtres hiér / 7 jours / 30 jours + enrichissements : une seule
    // requête de ventes couvre tout (locale, quelques millisecondes).
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final weekStart = startOfToday.subtract(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);
    final last30 = startOfToday.subtract(const Duration(days: 29));
    final windowFrom =
        last30.isBefore(monthStart) ? last30 : monthStart;

    final yesterday = await reports.daily(
      business.id,
      day: startOfToday.subtract(const Duration(days: 1)),
    );
    final salesWindow = await db.getSales(
      business.id,
      from: windowFrom,
      to: now,
      limit: 8000,
    );
    final completed = salesWindow.where((s) => s.status == 'completed');
    final weekSales =
        completed.where((s) => !s.soldAt.isBefore(weekStart)).toList();
    final monthSales =
        completed.where((s) => !s.soldAt.isBefore(monthStart)).toList();
    final todaySoldIds = {
      for (final s in completed)
        if (!s.soldAt.isBefore(startOfToday)) s.id,
    };

    final expensesMonth = await db.getExpenses(
      business.id,
      from: monthStart,
      to: now,
    );
    final confirmedMonthExpenses =
        expensesMonth.where((e) => e.status == 'confirmed').toList();

    // Articles vendus : sert au top 3 du jour ET à la liste des invendus.
    final qtyToday = <String, double>{};
    final unitOf = <String, String>{};
    final soldNames30 = <String>{};
    for (final s in completed) {
      final isToday = todaySoldIds.contains(s.id);
      for (final i in await db.getSaleItems(s.id)) {
        soldNames30.add(i.productName.toLowerCase());
        if (isToday) {
          qtyToday[i.productName] =
              (qtyToday[i.productName] ?? 0) + i.quantity;
          unitOf.putIfAbsent(i.productName, () => i.unit);
        }
      }
    }
    final ranked = qtyToday.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topProducts = [
      for (final e in ranked.take(3))
        '- ${e.key} — ${e.value.toStringAsFixed(0)} ${unitOf[e.key] ?? ''}'.trim(),
    ];

    final allProducts = await db.getProducts(business.id);
    final dormantProducts = [
      for (final p in allProducts)
        if (p.trackStock && !p.isDeleted && !soldNames30.contains(p.name.toLowerCase()))
          '- ${p.name} (${p.stockQty.toStringAsFixed(0)} ${p.unit} en stock)',
    ];

    final expenseCategories = <String, double>{};
    for (final e in confirmedMonthExpenses) {
      final key = (e.categoryName == null || e.categoryName!.trim().isEmpty)
          ? 'Divers'
          : e.categoryName!.trim();
      expenseCategories[key] = (expenseCategories[key] ?? 0) + e.amount;
    }

    final returnsToday = await db.getSaleReturns(
      business.id,
      from: startOfToday,
      to: now,
    );
    final customers = await db.getCustomers(business.id);

    double sum(List<Sale> xs) =>
        xs.fold<double>(0, (a, s) => a + s.total);
    double collected(List<Sale> xs) =>
        xs.fold<double>(0, (a, s) => a + s.amountPaid);
    final monthExpenseTotal = confirmedMonthExpenses.fold<double>(
      0,
      (a, e) => a + e.amount,
    );

    final snapshot = LynkGroundedAnswers.fromReports(
      business: business,
      report: report,
      stock: stock,
      lowStock: lowStock,
      debtors: debtors,
      hasTrendData: true,
      yesterdaySold: yesterday.sold,
      yesterdayProfit: yesterday.profitEstimate,
      weekSold: sum(weekSales),
      weekProfit: collected(weekSales) -
          confirmedMonthExpenses
              .where((e) => !e.expenseDate.isBefore(weekStart))
              .fold<double>(0, (a, e) => a + e.amount),
      monthSold: sum(monthSales),
      monthProfit:
          collected(monthSales) - monthExpenseTotal,
      monthExpenses: monthExpenseTotal,
      monthSalesCount: monthSales.length,
      customerCount: customers.length,
      productCount: allProducts.where((p) => !p.isDeleted).length,
      returnsCount: returnsToday.length,
      returnsTotal: returnsToday.fold<double>(0, (a, r) => a + r.total),
      topProducts: topProducts,
      dormantProducts: dormantProducts,
      expenseCategories: expenseCategories,
      allProducts: allProducts,
    );
    final totalDebt = snapshot.totalDebt;

    final lowLines = lowStock
        .take(8)
        .map(
          (product) =>
              '- ${_safe(product.name)}: ${product.stockQty.toStringAsFixed(2)} '
              '${_safe(product.unit)}, seuil ${product.lowStockThreshold.toStringAsFixed(2)}',
        );
    final debtLines = debtors
        .take(6)
        .map(
          (customer) =>
              '- ${_safe(customer.name)}: ${customer.balance.toStringAsFixed(0)} FCFA',
        );
    final trendLines =
        'CA hier: ${yesterday.sold.toStringAsFixed(0)} FCFA · '
        'bénéfice hier: ${yesterday.profitEstimate.toStringAsFixed(0)} FCFA · '
        'CA 7 jours: ${snapshot.weekSold.toStringAsFixed(0)} FCFA · '
        'CA du mois: ${snapshot.monthSold.toStringAsFixed(0)} FCFA · '
        'dépenses du mois: ${monthExpenseTotal.toStringAsFixed(0)} FCFA · '
        'bénéfice du mois: ${snapshot.monthProfit.toStringAsFixed(0)} FCFA\n'
        'Top ventes du jour: ${topProducts.isEmpty ? 'aucune' : topProducts.join(' | ')}\n'
        'Postes de dépenses (mois): ${expenseCategories.isEmpty ? 'aucun' : expenseCategories.entries.map((e) => '${_safe(e.key)} ${e.value.toStringAsFixed(0)}').join(', ')}\n'
        'Retours du jour: ${returnsToday.length} (${returnsToday.fold<double>(0, (a, r) => a + r.total).toStringAsFixed(0)} FCFA) · '
        'Produits: ${allProducts.where((p) => !p.isDeleted).length} · '
        'Clients: ${customers.length} · Invendus 30j: ${dormantProducts.length}';

    final isEn = languageCode == 'en';
    final firstName = firstNameOf(userDisplayName);
    final addressAs = firstName.isEmpty
        ? (isEn ? 'the merchant' : "le commerçant")
        : firstName;
    final languageLine = isEn
        ? 'Always answer in natural, clear English.'
        : 'Réponds toujours en français naturel et clair.';

    final persona = isEn
        ? '''
You are Lynk, the on-device shop assistant for « ${_safe(business.name)} ».
Speak to $addressAs. Be direct. Answer with the numbers in <local_data> only.
Rules:
- Start with the answer, not a greeting or a menu.
- Never invent a figure.
- 2 to 5 short sentences. Bullets only for lists.
- Read-only: you cannot change stock, sales or debts.
$languageLine
'''
        : '''
Tu es Lynk, l’assistant du magasin « ${_safe(business.name)} » sur cet appareil.
Tu t’adresses à $addressAs. Sois direct. Utilise uniquement les chiffres de <donnees_locales>.
Règles :
- Commence par la réponse, pas par un bonjour ni un menu.
- N’invente aucun chiffre.
- 2 à 5 phrases courtes. Puces seulement pour les listes.
- Lecture seule : tu ne modifies ni stock, ni vente, ni dette.
$languageLine
''';

    final dataBlock = isEn
        ? '''
<local_data>
Local date: ${DateTime.now().toIso8601String()}
User first name: ${_safe(firstName.isEmpty ? 'unknown' : firstName)}
Currency: ${_safe(business.currency)}
Sales today (count): ${report.salesCount}
Revenue today: ${report.sold.toStringAsFixed(0)} FCFA
Collected today: ${report.collected.toStringAsFixed(0)} FCFA
Credit sales today: ${report.credit.toStringAsFixed(0)} FCFA
Expenses today: ${report.expenses.toStringAsFixed(0)} FCFA
Estimated profit today: ${report.profitEstimate.toStringAsFixed(0)} FCFA
Top product: ${_safe(report.topProduct ?? 'none')}
Stock value at cost: ${(stock['cost_value'] ?? 0).toStringAsFixed(0)} FCFA
Stock value at sale price: ${(stock['sale_value'] ?? 0).toStringAsFixed(0)} FCFA
Out-of-stock products: ${(stock['out_count'] ?? 0).toStringAsFixed(0)}
Below-threshold products: ${(stock['low_count'] ?? 0).toStringAsFixed(0)}
Stock to watch:
${lowLines.isEmpty ? '- none' : lowLines.join('\n')}
Total customer debt: ${totalDebt.toStringAsFixed(0)} FCFA
Main debtors:
${debtLines.isEmpty ? '- none' : debtLines.join('\n')}
$trendLines
</local_data>
'''
        : '''
<donnees_locales>
Date locale: ${DateTime.now().toIso8601String()}
Prénom utilisateur: ${_safe(firstName.isEmpty ? 'inconnu' : firstName)}
Devise: ${_safe(business.currency)}
Ventes du jour: ${report.salesCount}
Chiffre d’affaires du jour: ${report.sold.toStringAsFixed(0)} FCFA
Encaissé du jour: ${report.collected.toStringAsFixed(0)} FCFA
Crédit du jour: ${report.credit.toStringAsFixed(0)} FCFA
Dépenses du jour: ${report.expenses.toStringAsFixed(0)} FCFA
Bénéfice estimé du jour: ${report.profitEstimate.toStringAsFixed(0)} FCFA
Meilleur produit: ${_safe(report.topProduct ?? 'aucun')}
Valeur stock au coût: ${(stock['cost_value'] ?? 0).toStringAsFixed(0)} FCFA
Valeur stock à la vente: ${(stock['sale_value'] ?? 0).toStringAsFixed(0)} FCFA
Produits en rupture: ${(stock['out_count'] ?? 0).toStringAsFixed(0)}
Produits sous le seuil: ${(stock['low_count'] ?? 0).toStringAsFixed(0)}
Stock à surveiller:
${lowLines.isEmpty ? '- aucun' : lowLines.join('\n')}
Dette clients totale: ${totalDebt.toStringAsFixed(0)} FCFA
Principaux débiteurs:
${debtLines.isEmpty ? '- aucun' : debtLines.join('\n')}
$trendLines
</donnees_locales>
''';

    return AiPromptBundle(
      systemPrompt: '$persona\n$dataBlock',
      snapshot: snapshot,
    );
  }

  /// Premier mot du nom (prénom), sans caractères dangereux pour le prompt.
  static String firstNameOf(String? fullName) {
    if (fullName == null) return '';
    final cleaned = fullName
        .replaceAll('<', '‹')
        .replaceAll('>', '›')
        .replaceAll('\n', ' ')
        .trim();
    if (cleaned.isEmpty) return '';
    return cleaned.split(RegExp(r'\s+')).first;
  }

  String _safe(String value) => value
      .replaceAll('<', '‹')
      .replaceAll('>', '›')
      .replaceAll('\n', ' ')
      .trim();
}
