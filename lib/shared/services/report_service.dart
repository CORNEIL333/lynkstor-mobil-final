import '../../core/database/app_database.dart';

class DailyReport {
  DailyReport({
    required this.sold,
    required this.collected,
    required this.credit,
    required this.expenses,
    required this.profitEstimate,
    required this.salesCount,
    required this.expectedCash,
    /// Nombre de ventes partiellement payées du jour (paiement mixte ou
    /// montant réglé inférieur au total). Permet d'afficher un indicateur
    /// d'acomptes réel sur le tableau de bord.
    this.partialPaymentsCount = 0,
    this.topProduct,
  });

  final double sold;
  final double collected;
  final double credit;
  final double expenses;
  final double profitEstimate;
  final int salesCount;
  final double expectedCash;
  final int partialPaymentsCount;
  final String? topProduct;
}

class ReportService {
  ReportService({required this.db});

  final AppDatabase db;

  Future<DailyReport> daily(String businessId, {DateTime? day}) async {
    final d = day ?? DateTime.now();
    final start = DateTime(d.year, d.month, d.day);
    final end = start.add(const Duration(days: 1));

    final sales = await db.getSales(
      businessId,
      from: start,
      to: end,
      limit: 10000,
    );
    final completed = sales.where((s) => s.status == 'completed').toList();

    double sold = 0, collected = 0, credit = 0;
    int partialPaymentsCount = 0;
    final productQty = <String, double>{};

    for (final s in completed) {
      sold += s.total;
      collected += s.amountPaid;
      credit += s.amountDue;
      // Une vente est un "acompte" (paiement partiel) si le montant réglé est
      // strictement supérieur à 0 mais inférieur au total (paiement mixte ou
      // crédit avec avance). Cela correspond à ce que l'utilisateur appelle
      // "acompte" dans le langage de l'application.
      if (s.amountPaid > 0 && s.amountDue > 0) {
        partialPaymentsCount++;
      }
      final items = await db.getSaleItems(s.id);
      for (final i in items) {
        productQty[i.productName] =
            (productQty[i.productName] ?? 0) + i.quantity;
      }
    }

    final expensesList = await db.getExpenses(businessId, from: start, to: end);
    double expenses = 0;
    for (final e in expensesList.where((e) => e.status == 'confirmed')) {
      expenses += e.amount;
    }

    String? top;
    double topQty = 0;
    productQty.forEach((name, qty) {
      if (qty > topQty) {
        topQty = qty;
        top = name;
      }
    });

    return DailyReport(
      sold: sold,
      collected: collected,
      credit: credit,
      expenses: expenses,
      profitEstimate: collected - expenses,
      salesCount: completed.length,
      expectedCash: collected - expenses,
      partialPaymentsCount: partialPaymentsCount,
      topProduct: top,
    );
  }

  Future<Map<String, double>> stockValue(String businessId) async {
    final products = await db.getProducts(businessId);
    double costValue = 0;
    double saleValue = 0;
    int low = 0;
    int out = 0;
    for (final p in products.where((p) => p.trackStock && !p.isDeleted)) {
      costValue += p.stockQty * p.costPrice;
      saleValue += p.stockQty * p.salePrice;
      if (p.stockQty <= 0) {
        out++;
      } else if (p.stockQty <= p.lowStockThreshold) {
        low++;
      }
    }
    return {
      'cost_value': costValue,
      'sale_value': saleValue,
      'low_count': low.toDouble(),
      'out_count': out.toDouble(),
      'product_count': products.length.toDouble(),
    };
  }
}
