import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/logging/app_telemetry_service.dart';
import 'package:kumba_business/core/network/mobile_money_service.dart';
import 'package:kumba_business/core/sync/http_sync_client.dart';
import 'package:kumba_business/core/utils/esc_pos_printer_service.dart';
import 'package:kumba_business/core/utils/thermal_receipt_service.dart';
import 'package:kumba_business/l10n/app_strings.dart';
import 'package:kumba_business/l10n/app_strings_en.dart';

void main() {
  group('ThermalReceiptService Tests', () {
    test(
      'generateReceiptPdf produces valid PDF bytes for thermal 80mm',
      () async {
        final bytes = await ThermalReceiptService.generateReceiptPdf(
          businessName: 'Boutique Test',
          saleId: 'SALE-1001',
          items: [
            {'name': 'Sac de Riz 50kg', 'qty': 2, 'price': 22500.0},
            {'name': 'Huile 5L', 'qty': 1, 'price': 6500.0},
          ],
          totalAmount: 51500.0,
          paymentMethod: 'Espèces',
          paperSize: ReceiptPaperSize.roll80,
        );

        expect(bytes, isNotEmpty);
        expect(bytes.length, greaterThan(100));
      },
    );
  });

  group('i18n Multilingual Tests', () {
    test('S class toggles between French and English', () {
      S.currentLanguage = 'fr';
      expect(S.tagline, contains('Votre commerce'));

      S.currentLanguage = 'en';
      expect(S.tagline, contains('Your business'));
      expect(SEn.sales, 'Sales');

      S.currentLanguage = 'fr';
    });
  });

  group('HttpSyncClient Tests', () {
    test(
      'HttpSyncClient handles invalid endpoint gracefully without throwing',
      () async {
        final client = HttpSyncClient();
        final success = await client.pushItem(
          endpointUrl: 'http://invalid-test-domain-12345.local/sync',
          itemId: 'sync-1',
          businessId: 'biz-1',
          entityType: 'sale',
          entityId: 'sale-1',
          operation: 'create',
          payload: {'test': true},
        );

        expect(success, isFalse);
      },
    );
  });

  group('EscPosPrinterService & MobileMoney & Telemetry Tests', () {
    test('EscPosPrinterService builds raw ESC/POS byte commands', () {
      final rawBytes = EscPosPrinterService.buildRawReceipt(
        businessName: 'Supermarché Kumba',
        saleId: 'REF-8899',
        items: [
          {'name': 'Lait Concentré', 'qty': 3, 'price': 800.0},
        ],
        totalAmount: 2400.0,
        paymentMethod: 'Orange Money',
      );

      expect(rawBytes, isNotEmpty);
      expect(rawBytes.length, greaterThan(20));
    });

    test('MobileMoneyService is explicitly marked as coming soon', () async {
      final service = MobileMoneyService(sandboxMode: true);
      final result = await service.initiatePayment(
        phone: '+2250707070707',
        amount: 15000.0,
        provider: MobileMoneyProvider.orangeMoney,
        businessId: 'biz-1',
      );

      expect(result.status, MobileMoneyStatus.comingSoon);
      expect(result.amount, 15000.0);
      expect(result.errorMessage, contains('venir'));
    });

    test('AppTelemetryService captures and queues error events', () {
      AppTelemetryService.captureException(Exception('Test error logging'));
      expect(AppTelemetryService.pendingCount, greaterThan(0));
    });
  });
}
