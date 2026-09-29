import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/billing/ed25519_license_verifier.dart';
import 'package:kumba_business/core/billing/license_contract.dart';

/// Jeton de licence signé par la VRAIE clé privée de production (Neon), écrit
/// par `tool/gen_golden_license.mjs` dans ce fixture. Schéma exact du gateway :
/// `header.payload.signature`, signing input = `b64url(header).b64url(claims)`,
/// claims camelCase en epoch-secondes. Lu depuis le disque pour éviter toute
/// corruption de recopie ; expiresAt ~2036 donc valable pour les tests.
late final String _golden;

String _b64urlEncode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> _b64urlDecode(String s) {
  var n = s.replaceAll('-', '+').replaceAll('_', '/');
  switch (n.length % 4) {
    case 2:
      n += '==';
    case 3:
      n += '=';
  }
  return base64.decode(n);
}

class _Minted {
  _Minted(this.token, this.publicRaw, this.keyId);
  final String token;
  final List<int> publicRaw;
  final String keyId;
}

/// Fabrique un jeton Ed25519 au format exact du gateway avec une clé
/// éphémère. Sert aux tests « expiré », « grâce », « clé inconnue ».
Future<_Minted> _mint({
  required List<int> seed,
  required String businessId,
  required String keyId,
  required DateTime expiresAt,
  int graceDays = 7,
}) async {
  final ed = Ed25519();
  final kp = await ed.newKeyPairFromSeed(seed);
  final pub = await kp.extractPublicKey();
  final header = {'alg': 'Ed25519', 'typ': 'JWT', 'kid': keyId};
  final claims = LicenseClaims(
    businessId: businessId,
    plan: 'PRO',
    issuedAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
    expiresAt: expiresAt.toUtc(),
    nonce: 'n-${DateTime.now().microsecondsSinceEpoch}',
    keyId: keyId,
    graceDays: graceDays,
  );
  final h = _b64urlEncode(utf8.encode(jsonEncode(header)));
  final p = _b64urlEncode(utf8.encode(jsonEncode(claims.toJson())));
  final signingInput = '$h.$p';
  final sig = await ed.sign(utf8.encode(signingInput), keyPair: kp);
  final token = '$signingInput.${_b64urlEncode(sig.bytes)}';
  return _Minted(token, pub.bytes, keyId);
}

void main() {
  setUpAll(() {
    _golden = File('test/fixtures/golden_license.txt').readAsStringSync().trim();
    expect(_golden.split('.').length, 3, reason: 'fixture jeton invalide');
  });

  group('Ed25519LicenseVerifier - interop avec le backend Neon', () {
    test('accepte un jeton réellement signé par la clé privée de prod', () async {
      final license = await SignedLicense.parseAndVerify(
        _golden,
        const Ed25519LicenseVerifier(),
        expectedBusinessId: 'biz-golden-0001',
      );
      expect(license, isNotNull);
      expect(license!.claims.businessId, 'biz-golden-0001');
      expect(license.claims.plan, 'PRO');
      expect(license.claims.keyId, 'neon-2026-09');
      expect(license.claims.graceDays, 7);
    });

    test('rejette un expectedBusinessId différent (anti-confusion)', () async {
      final license = await SignedLicense.parseAndVerify(
        _golden,
        const Ed25519LicenseVerifier(),
        expectedBusinessId: 'someone-else',
      );
      expect(license, isNull);
    });

    test('rejette une signature falsifiée (1 bit inversé)', () async {
      final parts = _golden.split('.');
      final sigBytes = _b64urlDecode(parts[2]);
      sigBytes[0] = sigBytes.first ^ 0x01;
      parts[2] = _b64urlEncode(sigBytes);
      final license = await SignedLicense.parseAndVerify(
        parts.join('.'),
        const Ed25519LicenseVerifier(),
        expectedBusinessId: 'biz-golden-0001',
      );
      expect(license, isNull);
    });

    test('rejette un payload altéré (businessId remplacé)', () async {
      final parts = _golden.split('.');
      final claims =
          jsonDecode(utf8.decode(_b64urlDecode(parts[1]))) as Map<String, dynamic>;
      claims['businessId'] = 'attacker-biz';
      parts[1] = _b64urlEncode(utf8.encode(jsonEncode(claims)));
      final license = await SignedLicense.parseAndVerify(
        parts.join('.'),
        const Ed25519LicenseVerifier(),
        expectedBusinessId: 'attacker-biz',
      );
      expect(license, isNull);
    });

    test('rejette un kid inconnu (table de clés restreinte)', () async {
      final license = await SignedLicense.parseAndVerify(
        _golden,
        const Ed25519LicenseVerifier(publicKeys: {}),
        expectedBusinessId: 'biz-golden-0001',
      );
      expect(license, isNull);
    });
  });

  group('Ed25519LicenseVerifier - cycles de vie (mint éphémère)', () {
    test('expiré au-delà de la grâce = rejeté', () async {
      final m = await _mint(
        seed: List<int>.generate(32, (i) => i + 1),
        businessId: 'biz-x',
        keyId: 'k1',
        expiresAt: DateTime.now().subtract(const Duration(days: 8)),
        graceDays: 7,
      );
      final verifier = Ed25519LicenseVerifier(
        publicKeys: {m.keyId: _b64urlEncode(m.publicRaw)},
      );
      final license = await SignedLicense.parseAndVerify(
        m.token,
        verifier,
        expectedBusinessId: 'biz-x',
      );
      expect(license, isNull);
    });

    test('expiré dans la grâce = accepté', () async {
      final m = await _mint(
        seed: List<int>.generate(32, (i) => i + 2),
        businessId: 'biz-y',
        keyId: 'k2',
        expiresAt: DateTime.now().subtract(const Duration(days: 3)),
        graceDays: 7,
      );
      final verifier = Ed25519LicenseVerifier(
        publicKeys: {m.keyId: _b64urlEncode(m.publicRaw)},
      );
      final license = await SignedLicense.parseAndVerify(
        m.token,
        verifier,
        expectedBusinessId: 'biz-y',
      );
      expect(license, isNotNull);
    });

    test('mauvaise clé publique liée au même kid = rejeté', () async {
      final m = await _mint(
        seed: List<int>.generate(32, (i) => i + 3),
        businessId: 'biz-z',
        keyId: 'k3',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      // Générer un second keypair et lier SA pubkey au même kid : le jeton ne
      // vérifiera pas sous cette clé.
      final otherKp = await Ed25519().newKeyPairFromSeed(
        List<int>.generate(32, (i) => i + 99),
      );
      final otherPub = await otherKp.extractPublicKey();
      final verifier = Ed25519LicenseVerifier(
        publicKeys: {m.keyId: _b64urlEncode(otherPub.bytes)},
      );
      final license = await SignedLicense.parseAndVerify(
        m.token,
        verifier,
        expectedBusinessId: 'biz-z',
      );
      expect(license, isNull);
    });

    test('rotation de clés : ancien kid toujours valable tant que présent', () async {
      final m = await _mint(
        seed: List<int>.generate(32, (i) => i + 4),
        businessId: 'biz-rot',
        keyId: 'old-key',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      final verifier = Ed25519LicenseVerifier(
        publicKeys: {
          m.keyId: _b64urlEncode(m.publicRaw),
          'new-key': _b64urlEncode(List<int>.filled(32, 7)), // autre entrée cohabite
        },
      );
      final license = await SignedLicense.parseAndVerify(
        m.token,
        verifier,
        expectedBusinessId: 'biz-rot',
      );
      expect(license, isNotNull);
    });
  });
}
