/// Vérificateur Ed25519 réel des licences signées par le backend Lynkstor.
///
/// Remplace le no-op [DenyAllLicenseVerifier] dès que la clé publique de
/// signature est provisionnée (ce qui est le cas depuis le déploiement Neon).
///
/// Le backend (`functions/api/index.ts`) produit un jeton de la forme
/// `b64url(header).b64url(claims).b64url(sig)` où la **signature porte sur
/// `utf8("b64url(header).b64url(claims)")`**. [SignedLicense.parseAndVerify]
/// nous transmet exactement cette chaîne comme [signedPayload] : on reconstitue
/// donc le message signé sans jamais retenter un encodage, ce qui garantit
/// l'interop bit-à-bit avec le serveur.
///
/// Sécurité : la clé PUBLIQUE est embarquée (ce n'est pas un secret) ; seule la
/// clé PRIVÉE reste côté serveur. Une licence n'est approuvée que si la
/// signature Ed25519 vérifie sous la clé identifiée par `claims.keyId`, ce qui
/// rend impossible la forgade d'une licence « active » côté appareil.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'license_contract.dart';

class Ed25519LicenseVerifier implements LicenseSignatureVerifier {
  const Ed25519LicenseVerifier({this.publicKeys = productionKeys});

  /// Table `keyId -> clé publique Ed25519 brute (32 octets) en base64url`.
  /// Plusieurs entrées => rotation de clés sans casser les jetons déjà émis.
  final Map<String, String> publicKeys;

  /// Clé publique du backend Neon en production (imprimée par
  /// `tool/gen_neon_secrets.mjs`). À faire évoluer ici lors d'une rotation.
  static const Map<String, String> productionKeys = {
    'neon-2026-09': 'mCjVvBo2MH4jPxeWXcwHODoQyk2zT_4T1nesPV_otkM',
  };

  @override
  Future<bool> verify({
    required String signedPayload,
    required List<int> signature,
    required LicenseClaims claims,
  }) async {
    final encoded = publicKeys[claims.keyId];
    if (encoded == null) return false; // clé inconnue => on refuse.
    try {
      final pubBytes = _b64urlDecode(encoded);
      if (pubBytes.length != 32) return false;
      if (signature.length != 64) return false; // Ed25519 = 64 octets.
      final publicKey = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);
      final sig = Signature(signature, publicKey: publicKey);
      return await Ed25519().verify(
        utf8.encode(signedPayload),
        signature: sig,
      );
    } catch (_) {
      return false;
    }
  }

  static List<int> _b64urlDecode(String segment) {
    var normalized = segment.replaceAll('-', '+').replaceAll('_', '/');
    switch (normalized.length % 4) {
      case 2:
        normalized += '==';
      case 3:
        normalized += '=';
      case 1:
        throw const FormatException('invalid base64url length');
      default:
        break;
    }
    return base64.decode(normalized);
  }
}
