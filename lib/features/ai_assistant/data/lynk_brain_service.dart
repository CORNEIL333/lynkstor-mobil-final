import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/logging/app_logger.dart';

/// Un tour de conversation transmis au cerveau cloud.
class LynkChatTurn {
  const LynkChatTurn({required this.role, required this.text});

  final String role; // 'user' | 'assistant'
  final String text;
}

class LynkBrainAnswer {
  const LynkBrainAnswer({required this.text, required this.model});

  final String text;
  final String model;
}

/// Réseau coupé / serveur injoignable : l'appelant doit basculer en mode
/// local (réponses déterministes) et le dire à l'utilisateur.
class LynkBrainOfflineException implements Exception {
  const LynkBrainOfflineException([this.message = 'Cerveau cloud injoignable.']);
  final String message;

  @override
  String toString() => message;
}

/// Refus/erreur métier renvoyé par l'endpoint (clé, quota, validation).
class LynkBrainRejectException implements Exception {
  const LynkBrainRejectException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Cerveau hybride de Lynk.
///
/// - Questions métier fréquentes (CA, dettes, stock, bénéfice) : réponses
///   déterministes calculées sur la base locale (LynkGroundedAnswers),
///   jamais réseau — chiffres exacts, fonctionne hors ligne.
/// - Questions libres : Llama-3.2-3B via Cloudflare Workers AI (/ai/ask),
///   avec le résumé d'affaires local en contexte système.
class LynkBrainService {
  LynkBrainService({http.Client? client, String? endpoint, String? anonKey})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? AppConfig.aiAskUrl,
      _anonKey = anonKey ?? AppConfig.aiAccessAnonKey;

  final http.Client _client;
  final String _endpoint;
  final String _anonKey;

  bool get isConfigured => _endpoint.trim().isNotEmpty;

  Future<LynkBrainAnswer> ask({
    required String question,
    required String systemPrompt,
    List<LynkChatTurn> history = const [],
    Duration timeout = const Duration(seconds: 35),
  }) async {
    if (!isConfigured) {
      throw const LynkBrainOfflineException('Endpoint IA non configuré.');
    }
    final payload = jsonEncode({
      'question': question,
      'systemPrompt': systemPrompt,
      'history': [
        for (final turn in history.length > 6
                ? history.sublist(history.length - 6)
                : history)
          {'role': turn.role, 'content': turn.text},
      ],
    });
    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'x-lynkstor-anon': _anonKey,
            },
            body: payload,
          )
          .timeout(timeout);
      final decoded =
          (response.body.isEmpty
              ? null
              : jsonDecode(utf8.decode(response.bodyBytes)))
          as Map<String, dynamic>?;
      if (response.statusCode == 200 && decoded?['status'] == 'ok') {
        final data = decoded?['data'] as Map<String, dynamic>?;
        final text = (data?['answer'] ?? '').toString().trim();
        if (text.isNotEmpty) {
          return LynkBrainAnswer(
            text: text,
            model: (data?['model'] ?? 'cloud').toString(),
          );
        }
      }
      final message =
          (decoded?['message'] ?? 'Réponse vide du cerveau cloud.').toString();
      if (response.statusCode == 429 || response.statusCode == 503) {
        throw LynkBrainRejectException(message);
      }
      throw LynkBrainOfflineException(message);
    } on LynkBrainRejectException {
      rethrow;
    } on http.ClientException catch (error) {
      throw LynkBrainOfflineException(error.message);
    } on TimeoutException {
      throw const LynkBrainOfflineException('Le cerveau cloud a mis trop longtemps.');
    } on FormatException {
      throw const LynkBrainOfflineException('Réponse illisible du cerveau cloud.');
    }
  }

  /// Rédige/améliore un message fournisseur. En cas d'indisponibilité cloud,
  /// renvoie le brouillon local de l'utilisateur (jamais d'échec bloquant).
  Future<String> draftSupplierMessage({
    required String fallback,
    required String productName,
    required double stock,
    required double threshold,
    required double reorderQuantity,
    required String supplierName,
    required String language,
  }) async {
    final requestedLanguage = language == 'en' ? 'English' : 'French';
    try {
      final answer = await ask(
        question:
            'Rédige un message court et professionnel à ce fournisseur pour '
            'demander la quantité indiquée. Retourne uniquement le message, '
            'en $requestedLanguage. N\'invente jamais prix, date ou disponibilité.\n'
            'Fournisseur : $supplierName. Produit : $productName. '
            'Stock actuel : $stock. Seuil d\'alerte : $threshold. '
            'Quantité à commander : $reorderQuantity.',
        systemPrompt:
            'Tu écris des messages professionnels brefs à des fournisseurs. '
            'Tu réponds uniquement en $requestedLanguage.',
      );
      final result = answer.text.trim();
      return result.isEmpty ? fallback : result;
    } catch (error, stack) {
      AppLogger.w('Supplier draft fell back to local text', error, stack);
      return fallback;
    }
  }

  void dispose() => _client.close();
}
