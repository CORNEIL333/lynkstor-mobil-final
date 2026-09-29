import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kumba_business/core/config/app_config.dart';
import 'package:kumba_business/shared/services/subscription_payment_service.dart';

Map<String, dynamic> _envelope(Object? data, {String? message, String status = 'ok'}) =>
    {'status': status, if (data != null) 'data': data, if (message != null) 'message': message};

void main() {
  group('SubscriptionPaymentService.initiate', () {
    test('POSTe canal/phone + Bearer, renvoie pending_customer sur ACCEPTED', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode(_envelope({
            'intentId': 'a' * 36,
            'status': 'pending_customer',
            'amount': 15000,
            'currency': 'XAF',
          }, message: 'Confirmez sur votre téléphone.')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = SubscriptionPaymentService(client: client);

      final res = await service.initiate(
        syncToken: 'lynk_token',
        channel: 'mtn_momo',
        phone: '+237699112233',
      );

      expect(captured.method, 'POST');
      expect(captured.url.toString(),
          '${AppConfig.cloudApiBase}/api/v1/payments/initiate');
      expect(captured.headers['Authorization'], 'Bearer lynk_token');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['channel'], 'mtn_momo');
      expect(body['phone'], '+237699112233');
      expect(res.intentId, 'a' * 36);
      expect(res.isPending, isTrue);
      expect(res.amount, 15000);
      service.dispose();
    });

    test('REJECTED → isFailed avec message serveur', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode(_envelope({
            'intentId': 'b' * 36,
            'status': 'failed',
          }, message: 'Paiement refusé : solde insuffisant')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = SubscriptionPaymentService(client: client);
      final res = await service.initiate(
        syncToken: 't',
        channel: 'orange_money',
        phone: '699112233',
      );
      expect(res.isFailed, isTrue);
      expect(res.message, contains('refusé'));
      service.dispose();
    });

    test('HTTP 5xx lève une Exception (message localisé)', () async {
      final client = MockClient(
        (req) async => http.Response(jsonEncode(_envelope(null, message: 'PawaPay injoignable')), 502),
      );
      final service = SubscriptionPaymentService(client: client);
      expect(
        () => service.initiate(syncToken: 't', channel: 'mtn_momo', phone: '699'),
        throwsA(isA<Exception>()),
      );
      service.dispose();
    });
  });

  group('SubscriptionPaymentService.checkStatus', () {
    Future<PaymentOutcome> run(String remoteStatus) async {
      final client = MockClient((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, endsWith('/api/v1/payments/${'c' * 36}'));
        return http.Response(
          jsonEncode(_envelope({'intentId': 'c' * 36, 'status': remoteStatus})),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = SubscriptionPaymentService(client: client);
      final out = await service.checkStatus(syncToken: 't', intentId: 'c' * 36);
      service.dispose();
      return out;
    }

    test('succeeded', () async => expect(await run('succeeded'), PaymentOutcome.succeeded));
    test('failed', () async => expect(await run('failed'), PaymentOutcome.failed));
    test('expired → failed', () async => expect(await run('expired'), PaymentOutcome.failed));
    test('pending_customer', () async =>
        expect(await run('pending_customer'), PaymentOutcome.pending));

    test('erreur réseau → pending (ne conclut jamais en échec)', () async {
      final client = MockClient((req) async => throw Exception('offline'));
      final service = SubscriptionPaymentService(client: client);
      final out = await service.checkStatus(syncToken: 't', intentId: 'c' * 36);
      expect(out, PaymentOutcome.pending);
      service.dispose();
    });

    test('intentId vide → unknown', () async {
      final service = SubscriptionPaymentService(client: MockClient((_) async => http.Response('{}', 200)));
      expect(await service.checkStatus(syncToken: 't', intentId: ''), PaymentOutcome.unknown);
      service.dispose();
    });
  });

  group('pollUntilFinal', () {
    test('boucle jusquà succeeded', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        final status = calls < 2 ? 'pending_customer' : 'succeeded';
        return http.Response(
          jsonEncode(_envelope({'status': status})),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = SubscriptionPaymentService(client: client);
      final seen = <PaymentOutcome>[];
      final out = await service.pollUntilFinal(
        syncToken: 't',
        intentId: 'd' * 36,
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(seconds: 2),
        onTick: seen.add,
      );
      expect(out, PaymentOutcome.succeeded);
      expect(calls, greaterThanOrEqualTo(2));
      service.dispose();
    });

    test('respecte isCancelled', () async {
      final client = MockClient(
        (req) async => http.Response(jsonEncode(_envelope({'status': 'pending_customer'})), 200),
      );
      final service = SubscriptionPaymentService(client: client);
      final out = await service.pollUntilFinal(
        syncToken: 't',
        intentId: 'e' * 36,
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(seconds: 5),
        isCancelled: () => true,
      );
      expect(out, PaymentOutcome.pending);
      service.dispose();
    });
  });
}
