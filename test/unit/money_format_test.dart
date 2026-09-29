import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/utils/money_format.dart';

void main() {
  group('MoneyFormat', () {
    test('formats FCFA amounts with spaces', () {
      final result = MoneyFormat.format(145000);
      expect(result.contains('145'), isTrue);
      expect(result.contains('FCFA'), isTrue);
    });

    test('parse handles spaces and commas', () {
      expect(MoneyFormat.parse('12 500'), 12500);
      expect(MoneyFormat.parse('1.500'), 1.5);
    });

    test('format without currency', () {
      final result = MoneyFormat.format(1000, showCurrency: false);
      expect(result.contains('FCFA'), isFalse);
    });
  });
}
