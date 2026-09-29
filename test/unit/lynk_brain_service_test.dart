import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kumba_business/features/ai_assistant/data/lynk_brain_service.dart';

const _testEndpoint = 'https://example.test/ai/ask';
const _testKey = 'test-anon-key';

LynkBrainService _service(
  Future<http.Response> Function(http.Request request) handler,
) {
  return LynkBrainService(
    client: MockClient(handler),
    endpoint: _testEndpoint,
    anonKey: _testKey,
  );
}

void main() {
  group('LynkBrainService.ask', () {
    test('parse une réponse cloud valide et renvoie modèle + texte', () async {
      late http.Request captured;
      final service = _service((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'data': {'answer': '  Vos marges sont saines.  ', 'model': '@cf/meta/llama-3.2-3b-instruct'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final answer = await service.ask(
        question: 'Comment améliorer mes marges ?',
        systemPrompt: 'Tu es Lynk.',
        history: const [LynkChatTurn(role: 'user', text: 'Bonjour')],
      );

      expect(answer.text, 'Vos marges sont saines.');
      expect(answer.model, '@cf/meta/llama-3.2-3b-instruct');
      expect(captured.headers['x-lynkstor-anon'], _testKey);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['question'], 'Comment améliorer mes marges ?');
      expect((body['history'] as List).length, 1);
    });

    test('borne l\'historique aux 6 derniers tours', () async {
      late http.Request captured;
      final service = _service((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'data': {'answer': 'ok', 'model': 'm'},
          }),
          200,
        );
      });

      await service.ask(
        question: 'q',
        systemPrompt: 's',
        history: List.generate(
          10,
          (i) => LynkChatTurn(role: i.isEven ? 'user' : 'assistant', text: 't$i'),
        ),
      );

      final history = jsonDecode(captured.body)['history'] as List;
      expect(history.length, 6);
      expect(history.first['content'], 't4');
      expect(history.last['content'], 't9');
    });

    test('429 -> LynkBrainRejectException avec le message serveur', () async {
      final service = _service(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({'status': 'error', 'message': 'Trop de requêtes.'}),
          ),
          429,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );

      expect(
        () => service.ask(question: 'q', systemPrompt: 's'),
        throwsA(
          isA<LynkBrainRejectException>().having(
            (e) => e.message,
            'message',
            'Trop de requêtes.',
          ),
        ),
      );
    });

    test('503 -> LynkBrainRejectException (modèles indisponibles)', () async {
      final service = _service(
        (_) async => http.Response(
          jsonEncode({'status': 'error', 'message': 'IA indisponible.'}),
          503,
        ),
      );

      expect(
        () => service.ask(question: 'q', systemPrompt: 's'),
        throwsA(isA<LynkBrainRejectException>()),
      );
    });

    test('autre erreur HTTP -> LynkBrainOfflineException', () async {
      final service = _service(
        (_) async => http.Response('{"status":"error","message":"clef?"}', 401),
      );

      expect(
        () => service.ask(question: 'q', systemPrompt: 's'),
        throwsA(isA<LynkBrainOfflineException>()),
      );
    });

    test('corps illisible -> LynkBrainOfflineException', () async {
      final service = _service((_) async => http.Response('<html>', 200));

      expect(
        () => service.ask(question: 'q', systemPrompt: 's'),
        throwsA(isA<LynkBrainOfflineException>()),
      );
    });

    test('endpoint vide -> LynkBrainOfflineException sans appel réseau', () {
      final service = LynkBrainService(
        client: MockClient((_) async => throw StateError('jamais appelé')),
        endpoint: '  ',
        anonKey: _testKey,
      );

      expect(service.isConfigured, isFalse);
      expect(
        () => service.ask(question: 'q', systemPrompt: 's'),
        throwsA(isA<LynkBrainOfflineException>()),
      );
    });
  });

  group('LynkBrainService.draftSupplierMessage', () {
    test('renvoie le texte cloud quand l\'IA répond', () async {
      final service = _service(
        (_) async => http.Response(
          jsonEncode({
            'status': 'ok',
            'data': {'answer': 'Bonjour, merci de livrer 10 sacs.', 'model': 'm'},
          }),
          200,
        ),
      );

      final draft = await service.draftSupplierMessage(
        fallback: 'brouillon local',
        productName: 'Ciment',
        stock: 3,
        threshold: 5,
        reorderQuantity: 10,
        supplierName: 'Atlas',
        language: 'fr',
      );

      expect(draft, 'Bonjour, merci de livrer 10 sacs.');
    });

    test('jamais bloquant : renvoie le fallback si le cloud est injoignable', () async {
      final service = _service(
        (_) async => throw http.ClientException('SocketException'),
      );

      final draft = await service.draftSupplierMessage(
        fallback: 'brouillon local',
        productName: 'Ciment',
        stock: 3,
        threshold: 5,
        reorderQuantity: 10,
        supplierName: 'Atlas',
        language: 'fr',
      );

      expect(draft, 'brouillon local');
    });
  });
}
