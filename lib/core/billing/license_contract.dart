/// Contrat de licence signée côté serveur — correctif de fond de l'audit S1.
///
/// PROBLÈME D'ORIGINE (S1, critique) : la licence était stockée localement
/// (flutter_secure_storage) et [SubscriptionInfo.allowsSales] renvoyait `true`
/// pour `source == 'local'`. Un client pouvait donc utiliser l'app
/// indéfiniment sans jamais payer.
///
/// CORRECTIF : la seule source de vérité d'un droit d'exploitation commercial
/// est un **jeton signé par le backend** ([SignedLicense]), porteur de claims
/// explicites (business, plan, expiration, nonce) et vérifié par une clé que
/// l'app NE POSSÈDE PAS en clair. Sans jeton valide et non expiré, la vente
/// est bloquée — même hors ligne, dans la limite de la grâce offline.
///
/// Le format (JWT-like, canonique) est fixé ici pour que client et serveur
/// partagent le même contrat. La vérification cryptographique réelle est
/// déléguée à [LicenseSignatureVerifier] (implémentation serveur/Edge, ou
/// clé publique embarquée côté client), afin de ne pas lier ce modèle à une
/// librairie crypto particulière.
library;

import 'dart:convert';

/// Claims d'une licence. Sérialisés en base64url(JSON) dans la partie
/// "payload" du jeton, suivis de "." + signature.
class LicenseClaims {
  const LicenseClaims({
    required this.businessId,
    required this.plan,
    required this.issuedAt,
    required this.expiresAt,
    required this.nonce,
    required this.keyId,
    this.graceDays = 7,
  });

  final String businessId;
  final String plan; // STARTER / PRO / ENTERPRISE
  final DateTime issuedAt;
  final DateTime expiresAt;

  /// Anti-rejeu : identifiant unique du jeton, comparé au dernier vu en local.
  final String nonce;

  /// Identifiant de la clé de signature (permet la rotation de clés).
  final String keyId;

  /// Grâce offline : durée pendant laquelle un jeton expiré reste accepté
  /// sans reconnexion, pour ne pas bloquer une caisse en zone blanche.
  final int graceDays;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// true si le jeton est encore exploitable, grâce offline incluse.
  bool get withinGrace {
    if (!isExpired) return true;
    final allowed = expiresAt.add(Duration(days: graceDays));
    return !DateTime.now().isAfter(allowed);
  }

  Map<String, dynamic> toJson() => {
    'businessId': businessId,
    'plan': plan,
    'issuedAt': issuedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    'expiresAt': expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    'nonce': nonce,
    'keyId': keyId,
    'graceDays': graceDays,
  };

  /// Tolère le format du gateway Neon (camelCase + epoch-secondes) ET l'ancien
  /// format court (biz/kid/jti + ISO) pour ne casser aucun jeton déjà émis.
  factory LicenseClaims.fromJson(Map<String, dynamic> j) {
    DateTime readTime(Object? epoch, Object? iso) {
      if (epoch is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          epoch.toInt() * 1000,
          isUtc: true,
        );
      }
      if (epoch is String && epoch.isNotEmpty) {
        final n = num.tryParse(epoch);
        if (n != null) {
          return DateTime.fromMillisecondsSinceEpoch(
            n.toInt() * 1000,
            isUtc: true,
          );
        }
      }
      if (iso is String && iso.isNotEmpty) return DateTime.parse(iso);
      throw const FormatException('license claim missing a valid timestamp');
    }

    final biz = (j['businessId'] ?? j['biz']) as String?;
    if (biz == null) throw const FormatException('license claim missing biz');
    return LicenseClaims(
      businessId: biz,
      plan: (j['plan'] as String?) ?? 'PRO',
      issuedAt: readTime(j['issuedAt'], j['iat']),
      expiresAt: readTime(j['expiresAt'], j['exp']),
      nonce: ((j['nonce'] ?? j['jti']) as String?) ?? '',
      keyId: ((j['keyId'] ?? j['kid']) as String?) ?? 'default',
      graceDays: ((j['graceDays'] ?? j['grace']) as num?)?.toInt() ?? 7,
    );
  }
}

/// Vérification cryptographique : renvoie true uniquement si [signature] est
/// valide pour [signedPayload] sous la clé identifiée par claims.keyId.
/// L'app ne fait confiance à une licence que si ce vérificateur l'approuve.
abstract interface class LicenseSignatureVerifier {
  Future<bool> verify({
    required String signedPayload,
    required List<int> signature,
    required LicenseClaims claims,
  });
}

/// Représentation d'un jeton de licence "header.payload.signature" (base64url).
class SignedLicense {
  const SignedLicense._({
    required this.raw,
    required this.headerSegment,
    required this.payloadSegment,
    required this.signatureSegment,
    required this.claims,
  });

  final String raw;
  final String headerSegment;
  final String payloadSegment;
  final String signatureSegment;
  final LicenseClaims claims;

  /// Message réellement signé par le backend : `b64url(header).b64url(claims)`.
  String get signingInput => '$headerSegment.$payloadSegment';

  /// Parse un jeton sans vérifier la signature (ne JAMAIS considérer comme
  /// valide avant passage par [SignedLicense.parseAndVerify]).
  static SignedLicense? parse(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = _base64UrlDecode(parts[1]);
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final claims = LicenseClaims.fromJson(json);
      return SignedLicense._(
        raw: token,
        headerSegment: parts[0],
        payloadSegment: parts[1],
        signatureSegment: parts[2],
        claims: claims,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parse + vérifie la signature + contrôle business/expiration.
  /// Retourne null si le jeton est irrémédiablement invalide.
  static Future<SignedLicense?> parseAndVerify(
    String token,
    LicenseSignatureVerifier verifier, {
    required String expectedBusinessId,
  }) async {
    final license = parse(token);
    if (license == null) return null;
    if (license.claims.businessId != expectedBusinessId) return null;
    final signature = _base64UrlDecodeBytes(license.signatureSegment);
    final ok = await verifier.verify(
      signedPayload: license.signingInput,
      signature: signature,
      claims: license.claims,
    );
    if (!ok) return null;
    if (!license.claims.withinGrace) return null;
    return license;
  }

  static String _base64UrlDecode(String segment) =>
      utf8.decode(_base64UrlDecodeBytes(segment));

  static List<int> _base64UrlDecodeBytes(String segment) {
    var normalized = segment.replaceAll('-', '+').replaceAll('_', '/');
    switch (normalized.length % 4) {
      case 2:
        normalized += '==';
      case 3:
        normalized += '=';
      case 1:
        throw FormatException('invalid base64url length');
      default:
        break;
    }
    return base64.decode(normalized);
  }
}

/// Vérificateur NO-OP : ne fait confiance à aucune licence.
/// Utilisé tant que la clé publique de signature n'est pas provisionnée —
/// il force le blocage des ventes, ce qui est le comportement SÛR par défaut
/// (contraste avec l'ancien `return true` local).
class DenyAllLicenseVerifier implements LicenseSignatureVerifier {
  const DenyAllLicenseVerifier();

  @override
  Future<bool> verify({
    required String signedPayload,
    required List<int> signature,
    required LicenseClaims claims,
  }) async => false;
}
