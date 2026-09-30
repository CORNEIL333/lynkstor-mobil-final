import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../l10n/app_strings.dart';

/// Prévisualisation publique d'une invitation cloud (résolue côté serveur).
class CloudInvitationPeek {
  CloudInvitationPeek({
    required this.businessId,
    required this.businessName,
    required this.sector,
    required this.role,
  });

  final String businessId;
  final String businessName;
  final String sector;
  final String role;
}

/// Résultat d'une jointure réussie : second jeton appareil + snapshot du
/// commerce pour recréer la ligne locale équivalente.
class CloudJoinResult {
  CloudJoinResult({
    required this.businessId,
    required this.userId,
    required this.role,
    required this.syncToken,
    required this.syncEndpoint,
    required this.businessName,
    required this.sector,
    this.ownerName,
    this.phone,
    this.planName,
    this.expiresAt,
  });

  final String businessId;
  final String userId;
  final String role;
  final String syncToken;
  final String syncEndpoint;
  final String businessName;
  final String sector;
  final String? ownerName;
  final String? phone;
  final String? planName;
  final String? expiresAt;
}

/// Invitations CLOUD multi-postes (gateway Neon /api/v1/invitations/*).
/// Codes au format INV-XXXX-XXXX, à usage unique, 7 jours, quota d'appareils
/// borné par le plan — contrairement aux invitations locales (mode équipe
/// sur le même appareil).
class CloudInvitationService {
  CloudInvitationService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static final RegExp codePattern = RegExp(r'^INV-[A-Z0-9]{4}-[A-Z0-9]{4}$');
  static bool looksCloudCode(String code) =>
      codePattern.hasMatch(code.trim().toUpperCase());

  String get _base => AppConfig.cloudApiBase;

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? syncToken,
  }) async {
    late http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$_base$path'),
            headers: {
              'Content-Type': 'application/json',
              if (syncToken != null && syncToken.isNotEmpty)
                'Authorization': 'Bearer $syncToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      AppLogger.w('invitation network $_base$path: $e');
      throw OfflineException(
        S.tr(
          'Impossible de joindre le cloud Lynkstor. Vérifiez votre connexion.',
          'Unable to reach Lynkstor cloud. Check your connection.',
        ),
      );
    }
    Map<String, dynamic> json = {};
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message =
          json['message']?.toString() ??
          S.tr(
            'Opération invitation échouée (${res.statusCode})',
            'Invitation operation failed (${res.statusCode})',
          );
      if (res.statusCode == 404 || res.statusCode == 409) {
        throw AuthException(message);
      }
      throw SyncException(message);
    }
    return (json['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Le poste hôte (authentifié par son jeton) génère un code pour un collègue.
  Future<String> createInvitation({
    required String syncToken,
    String role = 'seller',
    String? createdBy,
  }) async {
    final data = await _post('/api/v1/invitations/create', {
      'role': role,
      if (createdBy != null) 'createdBy': createdBy,
    }, syncToken: syncToken);
    final code = data['code']?.toString() ?? '';
    if (!looksCloudCode(code)) {
      throw SyncException(
        S.tr(
          'Réponse cloud invalide (code manquant).',
          'Invalid cloud response (missing code).',
        ),
      );
    }
    return code;
  }

  /// L'appareil qui rejoint vérifie le code avant de saisir son nom/PIN.
  Future<CloudInvitationPeek> peekInvitation(String code) async {
    final data = await _post('/api/v1/invitations/peek', {
      'code': code.trim().toUpperCase(),
    });
    return CloudInvitationPeek(
      businessId: data['businessId']?.toString() ?? '',
      businessName: data['businessName']?.toString() ?? '',
      sector: data['sector']?.toString() ?? 'general',
      role: data['role']?.toString() ?? 'seller',
    );
  }

  /// Joint cet appareil à la boutique existante : émet un second jeton
  /// d'appareil SANS consommer de code d'activation agent.
  Future<CloudJoinResult> acceptInvitation({
    required String code,
    required String deviceId,
    required String fullName,
    String? phone,
  }) async {
    final data = await _post('/api/v1/invitations/accept', {
      'code': code.trim().toUpperCase(),
      'deviceId': deviceId,
      'fullName': fullName.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    });
    final syncToken = data['syncToken']?.toString() ?? '';
    final business = (data['business'] as Map<String, dynamic>?) ?? {};
    if (syncToken.isEmpty || data['businessId'] == null) {
      throw SyncException(
        S.tr(
          'Réponse cloud invalide (jeton manquant).',
          'Invalid cloud response (missing token).',
        ),
      );
    }
    return CloudJoinResult(
      businessId: data['businessId'].toString(),
      userId: data['userId']?.toString() ?? '',
      role: data['role']?.toString() ?? 'seller',
      syncToken: syncToken,
      syncEndpoint:
          data['syncEndpoint']?.toString() ?? AppConfig.cloudSyncPushUrl,
      businessName: business['name']?.toString() ?? '',
      sector: business['sector']?.toString() ?? 'general',
      ownerName: business['ownerName']?.toString(),
      phone: business['phone']?.toString(),
      planName: data['planName']?.toString(),
      expiresAt: data['expiresAt']?.toString(),
    );
  }

  void dispose() => _client.close();
}
