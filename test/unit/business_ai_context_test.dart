import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/features/ai_assistant/domain/business_ai_context.dart';

void main() {
  group('BusinessAiContextBuilder.firstNameOf', () {
    test('returns first token of full name', () {
      expect(BusinessAiContextBuilder.firstNameOf('Kouamé Jean'), 'Kouamé');
      expect(BusinessAiContextBuilder.firstNameOf('Aminata'), 'Aminata');
    });

    test('handles empty and null', () {
      expect(BusinessAiContextBuilder.firstNameOf(null), '');
      expect(BusinessAiContextBuilder.firstNameOf(''), '');
      expect(BusinessAiContextBuilder.firstNameOf('   '), '');
    });

    test('strips prompt-sensitive characters', () {
      expect(BusinessAiContextBuilder.firstNameOf('<script>Jean'), '‹script›Jean');
    });
  });
}
