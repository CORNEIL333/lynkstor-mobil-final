import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/billing/billing_engine.dart';

void main() {
  group('BillingEngine & Accounting Tests', () {
    test('Computes exact receipt rounding without discrepancies', () {
      final invoice = BillingEngine.compute(
        lines: [
          BillingLineInput(
            productName: 'Haricot rouge',
            quantity: 7,
            unitPrice: 200, // TTC total should be 1400
            taxRate: 0.1925,
          ),
        ],
        globalDiscount: 0,
        payments: [
          BillingPaymentInput(method: 'cash', amount: 1400),
        ],
        pricesIncludeTax: true,
      );

      // Verify line details
      final line = invoice.lines.first;
      expect(line.lineTtc, 1400.0);
      
      // Since prices include tax:
      // HT = 1400 / 1.1925 = 1173.99999... = 1174 FCFA
      // Tax = 1400 - 1174 = 226 FCFA
      expect(line.lineHt, 1174.0);
      expect(line.taxAmount, 226.0);

      expect(invoice.totalTtc, 1400.0);
      expect(invoice.amountPaid, 1400.0);
      expect(invoice.amountDue, 0.0);
      expect(invoice.changeGiven, 0.0);
      
      // Verify ledger entries
      final ledger = invoice.ledger;
      expect(ledger.length, 3);
      
      final salesHt = ledger.firstWhere((e) => e.accountCode == '701');
      expect(salesHt.credit, 1174.0);
      
      final tva = ledger.firstWhere((e) => e.accountCode == '443');
      expect(tva.credit, 226.0);
      
      final cash = ledger.firstWhere((e) => e.accountCode == '570');
      expect(cash.debit, 1400.0);

      expect(invoice.isBalanced, true);
    });

    test('Computes partial payment and credit collection', () {
      final invoice = BillingEngine.compute(
        lines: [
          BillingLineInput(
            productName: 'Ciment',
            quantity: 2,
            unitPrice: 5000,
          ),
        ],
        payments: [
          BillingPaymentInput(method: 'cash', amount: 4000),
        ],
        pricesIncludeTax: true,
      );

      expect(invoice.totalTtc, 10000.0);
      expect(invoice.amountPaid, 4000.0);
      expect(invoice.amountDue, 6000.0);
      
      final ledger = invoice.ledger;
      
      final salesHt = ledger.firstWhere((e) => e.accountCode == '701');
      expect(salesHt.credit, 10000.0);
      
      final cash = ledger.firstWhere((e) => e.accountCode == '570');
      expect(cash.debit, 4000.0);
      
      final client = ledger.firstWhere((e) => e.accountCode == '411');
      expect(client.debit, 6000.0);
      
      expect(invoice.isBalanced, true);
    });

    test('Computes reversing for return/refund', () {
      final original = BillingEngine.buildLedger(
        totalHt: 10000,
        taxTotal: 1925,
        totalTtc: 11925,
        amountPaid: 11925,
        amountDue: 0,
        payments: [
          BillingPaymentInput(method: 'cash', amount: 11925),
        ],
      );

      final reversedFull = BillingEngine.reverseProportion(original: original, factor: 1.0);
      
      final salesHtRev = reversedFull.firstWhere((e) => e.accountCode == '701');
      expect(salesHtRev.debit, 10000.0);
      
      final tvaRev = reversedFull.firstWhere((e) => e.accountCode == '443');
      expect(tvaRev.debit, 1925.0);
      
      final cashRev = reversedFull.firstWhere((e) => e.accountCode == '570');
      expect(cashRev.credit, 11925.0);
    });
  });
}
