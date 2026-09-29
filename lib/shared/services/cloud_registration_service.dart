import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../l10n/app_strings.dart';

class CloudRegistrationResult {
  CloudRegistrationResult({
    required this.businessId,
    required this.userId,
    required this.syncToken,
    required this.syncEndpoint,
    this.planName,
    this.expiresAt,
  });

  final String businessId;
  final String userId;
  final String syncToken;
  final String syncEndpoint;
  final String? planName;
  final String? expiresAt;
}

class CloudCodeValidation {
  CloudCodeValidation({required this.planName, this.expiresAt});
  final String planName;
  final String? expiresAt;
}

class CloudSubscriptionStatus {
  CloudSubscriptionStatus({
    required this.businessId,
    required this.planName,
    required this.subscriptionStatus,
    required this.licenseActive,
    this.expiresAt,
    this.priceFcfa,
    this.businessName,
    this.checkedAt,
    this.licenseToken,
  });

  final String businessId;
  final String planName;
  final String subscriptionStatus;
  final bool licenseActive;
  final String? expiresAt;
  final num? priceFcfa;
  final String? businessName;
  final String? checkedAt;

  /// Jeton de licence Ed25519 brut (`header.payload.signature`) signé par le
  /// backend. Permet à l'app de vérifier la licence hors ligne et de garantir
  /// une grâce offline adossée à une preuve cryptographique, pas à un flag.
  final String? licenseToken;
}

/// Inscription cloud Supabase — code d'activation agent obligatoire.
class CloudRegistrationService {
  CloudRegistrationService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    // Le gateway Neon ne valide plus ces headers (la porte d'entrée réelle
    // est le code d'activation agent). Conservés pour compat rollback Supabase.
    if (AppConfig.cloudAnonKey.isNotEmpty) ...{
      'apikey': AppConfig.cloudAnonKey,
      'Authorization': 'Bearer ${AppConfig.cloudAnonKey}',
    },
  };

  /// Vérifie un code sans le consommer (étape 1 onboarding).
  Future<CloudCodeValidation> validateCode(String activationCode) async {
    final uri = Uri.parse('${AppConfig.cloudApiBase}/api/v1/register/validate');
    late http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'activationCode': activationCode.trim().toUpperCase(),
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      AppLogger.w('validateCode network: $e');
      throw Exception(
        S.tr(
          'Impossible de joindre le cloud Lynkstor. Vérifiez votre connexion Internet.',
          'Unable to reach Lynkstor cloud. Check your internet connection.',
        ),
      );
    }

    Map<String, dynamic> json = {};
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        json['message']?.toString() ??
            S.tr(
              'Code invalide (${res.statusCode})',
              'Invalid code (${res.statusCode})',
            ),
      );
    }

    final data = json['data'] as Map<String, dynamic>? ?? {};
    return CloudCodeValidation(
      planName: data['planName']?.toString() ?? 'STARTER',
      expiresAt: data['expiresAt']?.toString(),
    );
  }

  Future<CloudRegistrationResult> register({
    required String activationCode,
    required String businessId,
    required String userId,
    required String name,
    required String ownerName,
    required String phone,
    required String sector,
    String? city,
    String? neighborhood,
  }) async {
    final uri = Uri.parse(AppConfig.cloudRegisterUrl);
    late http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'activationCode': activationCode.trim().toUpperCase(),
              'business': {
                'id': businessId,
                'name': name,
                'ownerName': ownerName,
                'phone': phone,
                'sector': sector,
                'city': city,
                'neighborhood': neighborhood,
              },
              'user': {'id': userId, 'fullName': ownerName, 'phone': phone},
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      AppLogger.w('register network: $e');
      throw Exception(
        S.tr(
          'Inscription cloud impossible (réseau). Réessayez avec Internet actif.',
          'Cloud registration failed. Check your internet connection and try again.',
        ),
      );
    }

    Map<String, dynamic> json = {};
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg =
          json['message']?.toString() ??
          S.tr(
            'Inscription cloud échouée (${res.statusCode})',
            'Cloud registration failed (${res.statusCode})',
          );
      AppLogger.w('Cloud register failed: $msg body=${res.body}');
      throw Exception(msg);
    }

    final data = json['data'] as Map<String, dynamic>? ?? {};
    final syncToken = data['syncToken']?.toString();
    final syncEndpoint =
        data['syncEndpoint']?.toString() ?? AppConfig.cloudSyncPushUrl;
    final bid = data['businessId']?.toString() ?? businessId;
    final uid = data['userId']?.toString() ?? userId;

    if (syncToken == null || syncToken.isEmpty) {
      throw Exception(
        S.tr(
          'Réponse cloud invalide (jeton de synchronisation manquant).',
          'Invalid cloud response (missing synchronization token).',
        ),
      );
    }

    AppLogger.i('Cloud register OK business=$bid');
    return CloudRegistrationResult(
      businessId: bid,
      userId: uid,
      syncToken: syncToken,
      syncEndpoint: syncEndpoint,
      planName: data['planName']?.toString(),
      expiresAt: data['expiresAt']?.toString(),
    );
  }

  /// Statut abonnement cloud (jeton appareil).
  Future<CloudSubscriptionStatus> fetchSubscriptionStatus({
    required String syncToken,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.cloudApiBase}/api/v1/subscription/status',
    );
    late http.Response res;
    try {
      res = await _client
          .get(
            uri,
            headers: {..._headers, 'Authorization': 'Bearer $syncToken'},
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      AppLogger.w('subscription status network: $e');
      throw Exception(
        S.tr(
          'Impossible de vérifier l’abonnement (réseau).',
          'Unable to verify the subscription (network error).',
        ),
      );
    }

    Map<String, dynamic> json = {};
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        json['message']?.toString() ??
            S.tr(
              'Vérification abonnement échouée (${res.statusCode})',
              'Subscription verification failed (${res.statusCode})',
            ),
      );
    }

    final data = json['data'] as Map<String, dynamic>? ?? {};
    return CloudSubscriptionStatus(
      businessId: data['businessId']?.toString() ?? '',
      planName: data['planName']?.toString() ?? '—',
      subscriptionStatus: data['subscriptionStatus']?.toString() ?? 'missing',
      licenseActive: data['licenseActive'] == true,
      expiresAt: data['expiresAt']?.toString(),
      priceFcfa: data['priceFcfa'] is num ? data['priceFcfa'] as num : null,
      businessName: data['businessName']?.toString(),
      checkedAt:
          data['checkedAt']?.toString() ?? DateTime.now().toIso8601String(),
      licenseToken: data['licenseToken']?.toString(),
    );
  }

  void dispose() => _client.close();
}
