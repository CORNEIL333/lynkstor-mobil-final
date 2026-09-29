import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../l10n/app_strings.dart';

/// Résultat d'une initiation de paiement Mobile Money (PawaPay, modèle push).
class PaymentInitiation {
  PaymentInitiation({
    required this.intentId,
    required this.status,
    required this.message,
    this.amount,
    this.currency,
  });

  final String intentId;

  /// `pending_customer` = une demande a été poussée sur le téléphone du client,
  /// en attente de sa confirmation. `failed` = refus immédiat (voir [message]).
  final String status;
  final String message;
  final num? amount;
  final String? currency;

  bool get isPending => status == 'pending_customer' || status == 'processing';
  bool get isFailed => status == 'failed';
}

/// Statut normalisé d'une intention de paiement.
enum PaymentOutcome { pending, succeeded, failed, unknown }

/// Client des routes de paiement du gateway Neon.
///
/// Principe de sécurité : l'app ne parle QU'AU gateway Lynkstor. Elle ne
/// contacte jamais PawaPay directement, ne transporte aucun secret agrégateur
/// et ne décide jamais du montant (résolu côté serveur). La confirmation
/// Mobile Money se fait sur le téléphone du payeur ; le code secret opérateur
/// ne transite jamais par Lynkstor.
class SubscriptionPaymentService {
  SubscriptionPaymentService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _auth(String syncToken) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $syncToken',
  };

  Future<PaymentInitiation> initiate({
    required String syncToken,
    required String channel,
    required String phone,
    String? planId,
  }) async {
    late http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(AppConfig.cloudPaymentInitiateUrl),
            headers: _auth(syncToken),
            body: jsonEncode({
              'channel': channel,
              'phone': phone,
              if (planId != null && planId.isNotEmpty) 'planId': planId,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      AppLogger.w('payment initiate network: $e');
      throw Exception(
        S.tr(
          'Paiement impossible (réseau). Vérifiez votre connexion Internet.',
          'Payment failed (network). Check your internet connection.',
        ),
      );
    }

    Map<String, dynamic> json = {};
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final msg =
        json['message']?.toString() ??
        S.tr(
          'Le paiement a été refusé (${res.statusCode}).',
          'Payment was refused (${res.statusCode}).',
        );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(msg);
    }

    return PaymentInitiation(
      intentId: data['intentId']?.toString() ?? '',
      status: data['status']?.toString() ?? 'unknown',
      message: msg,
      amount: data['amount'] is num ? data['amount'] as num : null,
      currency: data['currency']?.toString(),
    );
  }

  /// Interroge le statut d'une intention. Ne throw pas sur erreur réseau :
  /// renvoie [PaymentOutcome.pending] pour que le polling continue (le gateway
  /// ré-interroge PawaPay ; un écart réseau ne doit jamais conclure en échec).
  Future<PaymentOutcome> checkStatus({
    required String syncToken,
    required String intentId,
  }) async {
    if (intentId.isEmpty) return PaymentOutcome.unknown;
    try {
      final res = await _client
          .get(
            Uri.parse(AppConfig.cloudPaymentStatusUrl(intentId)),
            headers: _auth(syncToken),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        AppLogger.w('payment status http ${res.statusCode}');
        return PaymentOutcome.pending;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>? ?? {};
      switch (data['status']?.toString()) {
        case 'succeeded':
          return PaymentOutcome.succeeded;
        case 'failed':
        case 'expired':
          return PaymentOutcome.failed;
        case 'pending_customer':
        case 'processing':
        case 'created':
          return PaymentOutcome.pending;
        default:
          return PaymentOutcome.pending;
      }
    } catch (e) {
      AppLogger.w('payment status network: $e');
      return PaymentOutcome.pending;
    }
  }

  /// Boucle de polling : interroge toutes les [interval] jusqu'à un statut
  /// final ou [timeout]. [onTick] est appelé à chaque relevé pour animer l'UI.
  /// Retourne le dernier statut observé (succeeded / failed / pending au delai).
  Future<PaymentOutcome> pollUntilFinal({
    required String syncToken,
    required String intentId,
    Duration interval = const Duration(seconds: 4),
    Duration timeout = const Duration(minutes: 3),
    void Function(PaymentOutcome outcome)? onTick,
    bool Function()? isCancelled,
  }) async {
    final deadline = DateTime.now().add(timeout);
    PaymentOutcome last = PaymentOutcome.pending;
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() == true) return last;
      await Future<void>.delayed(interval);
      if (isCancelled?.call() == true) return last;
      last = await checkStatus(syncToken: syncToken, intentId: intentId);
      onTick?.call(last);
      if (last == PaymentOutcome.succeeded || last == PaymentOutcome.failed) {
        return last;
      }
    }
    return last;
  }

  void dispose() => _client.close();
}
