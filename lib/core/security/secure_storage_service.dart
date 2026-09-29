import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage sécurisé — jamais de secrets en clair dans SharedPreferences.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  static const _keyPinHash = 'kumba_pin_hash';
  static const _keyPinSalt = 'kumba_pin_salt';
  static const _keyPasswordHash = 'kumba_password_hash';
  static const _keyPasswordSalt = 'kumba_password_salt';
  static const _keySessionToken = 'kumba_session_token';
  static const _keyDeviceId = 'kumba_device_id';
  static const _keyBackupKey = 'kumba_backup_key';
  static const _keyDatabaseKey = 'kumba_database_key';
  static const _keyBiometricEnabled = 'kumba_biometric';
  static const _keyOnboardingDone = 'kumba_onboarding_done';
  static const _keyCurrentUserId = 'kumba_current_user_id';
  static const _keyCurrentBusinessId = 'kumba_current_business_id';
  static const _keyCloudSyncToken = 'kumba_cloud_sync_token';
  static const _keyCloudSyncEndpoint = 'kumba_cloud_sync_endpoint';
  static const _keyPendingCloudRegistration =
      'kumba_pending_cloud_registration';
  static const _keyPinFailedAttempts = 'kumba_pin_failed_attempts';
  static const _keyPinLockedUntil = 'kumba_pin_locked_until';
  // Abonnement Lynkstor (cache local validé côté cloud)
  static const _keySubPlan = 'kumba_sub_plan';
  static const _keySubStatus = 'kumba_sub_status';
  static const _keySubExpires = 'kumba_sub_expires';
  static const _keySubCheckedAt = 'kumba_sub_checked_at';
  static const _keySubLicenseActive = 'kumba_sub_license_active';
  static const _keySubSource = 'kumba_sub_source'; // cloud | demo | local
  // Jeton de licence Ed25519 brut renvoyé par le cloud, conservé pour la
  // grâce offline : revérifié à froid (signature) à chaque bootstrap.
  static const _keySubLicenseToken = 'kumba_sub_license_token';

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  Future<String?> read(String key) => _storage.read(key: key);
  Future<void> delete(String key) => _storage.delete(key: key);
  Future<void> deleteAll() => _storage.deleteAll();

  // ——— Hashing PIN / mot de passe ———

  String _legacyHash(String value, String salt) {
    final bytes = utf8.encode('$salt::$value');
    return sha256.convert(bytes).toString();
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static const int _pbkdf2Iterations = 120000;

  String _derive(
    String value,
    String salt, {
    int iterations = _pbkdf2Iterations,
  }) {
    final password = utf8.encode(value);
    final saltBytes = base64Url.decode(salt);
    final block = <int>[...saltBytes, 0, 0, 0, 1];
    var u = Hmac(sha256, password).convert(block).bytes;
    final out = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = Hmac(sha256, password).convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return 'pbkdf2-sha256\$$iterations\$${base64UrlEncode(out)}';
  }

  bool _constantTimeEquals(String a, String b) {
    final aa = utf8.encode(a);
    final bb = utf8.encode(b);
    var diff = aa.length ^ bb.length;
    final length = max(aa.length, bb.length);
    for (var i = 0; i < length; i++) {
      diff |= (i < aa.length ? aa[i] : 0) ^ (i < bb.length ? bb[i] : 0);
    }
    return diff == 0;
  }

  bool _verifyDerived(String value, String salt, String stored) {
    if (!stored.startsWith('pbkdf2-sha256\$')) {
      return _constantTimeEquals(_legacyHash(value, salt), stored);
    }
    final parts = stored.split('\$');
    final iterations = parts.length >= 3 ? int.tryParse(parts[1]) : null;
    if (iterations == null || iterations < 10000) return false;
    return _constantTimeEquals(
      _derive(value, salt, iterations: iterations),
      stored,
    );
  }

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    await write(_keyPinSalt, salt);
    await write(_keyPinHash, _derive(pin, salt));
    await resetPinFailures();
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await read(_keyPinSalt);
    final hash = await read(_keyPinHash);
    if (salt == null || hash == null) return false;
    final valid = _verifyDerived(pin, salt, hash);
    if (valid && !hash.startsWith('pbkdf2-sha256\$')) {
      await setPin(pin);
    }
    return valid;
  }

  Future<bool> hasPin() async => (await read(_keyPinHash)) != null;

  Future<void> setPassword(String password) async {
    final salt = _generateSalt();
    await write(_keyPasswordSalt, salt);
    await write(_keyPasswordHash, _derive(password, salt));
  }

  Future<bool> verifyPassword(String password) async {
    final salt = await read(_keyPasswordSalt);
    final hash = await read(_keyPasswordHash);
    if (salt == null || hash == null) return false;
    final valid = _verifyDerived(password, salt, hash);
    if (valid && !hash.startsWith('pbkdf2-sha256\$')) {
      await setPassword(password);
    }
    return valid;
  }

  Future<Duration?> pinLockRemaining() async {
    final raw = await read(_keyPinLockedUntil);
    final until = raw == null ? null : DateTime.tryParse(raw);
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      await resetPinFailures();
      return null;
    }
    return remaining;
  }

  Future<void> recordPinFailure() async {
    final current = int.tryParse(await read(_keyPinFailedAttempts) ?? '') ?? 0;
    final attempts = current + 1;
    await write(_keyPinFailedAttempts, attempts.toString());
    if (attempts >= 5) {
      await write(
        _keyPinLockedUntil,
        DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      );
    }
  }

  Future<void> resetPinFailures() async {
    await delete(_keyPinFailedAttempts);
    await delete(_keyPinLockedUntil);
  }

  Future<void> setSessionToken(String token) => write(_keySessionToken, token);
  Future<String?> getSessionToken() => read(_keySessionToken);
  Future<void> clearSession() => delete(_keySessionToken);

  Future<void> setDeviceId(String id) => write(_keyDeviceId, id);
  Future<String?> getDeviceId() => read(_keyDeviceId);

  Future<void> setBackupKey(String key) => write(_keyBackupKey, key);
  Future<String?> getBackupKey() => read(_keyBackupKey);

  Future<String> getOrCreateDatabaseKey() async {
    final existing = await read(_keyDatabaseKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final value = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await write(_keyDatabaseKey, value);
    return value;
  }

  Future<void> setBiometricEnabled(bool enabled) =>
      write(_keyBiometricEnabled, enabled ? '1' : '0');
  Future<bool> isBiometricEnabled() async =>
      (await read(_keyBiometricEnabled)) == '1';

  Future<void> setOnboardingDone(bool done) =>
      write(_keyOnboardingDone, done ? '1' : '0');
  Future<bool> isOnboardingDone() async =>
      (await read(_keyOnboardingDone)) == '1';

  Future<void> setCurrentUserId(String id) => write(_keyCurrentUserId, id);
  Future<String?> getCurrentUserId() => read(_keyCurrentUserId);

  Future<void> setCurrentBusinessId(String id) =>
      write(_keyCurrentBusinessId, id);
  Future<String?> getCurrentBusinessId() => read(_keyCurrentBusinessId);
  Future<void> clearCurrentBusiness() => delete(_keyCurrentBusinessId);

  Future<void> setCloudSyncToken(String token) =>
      write(_keyCloudSyncToken, token);
  Future<String?> getCloudSyncToken() => read(_keyCloudSyncToken);

  Future<void> setCloudSyncEndpoint(String url) =>
      write(_keyCloudSyncEndpoint, url);
  Future<String?> getCloudSyncEndpoint() => read(_keyCloudSyncEndpoint);

  Future<void> setPendingCloudRegistration({
    required String activationCode,
    required String businessId,
    required String userId,
  }) {
    return write(
      _keyPendingCloudRegistration,
      jsonEncode({
        'activationCode': activationCode.trim().toUpperCase(),
        'businessId': businessId,
        'userId': userId,
      }),
    );
  }

  Future<Map<String, String>?> getPendingCloudRegistration() async {
    final raw = await read(_keyPendingCloudRegistration);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final code = decoded['activationCode']?.toString();
      final businessId = decoded['businessId']?.toString();
      final userId = decoded['userId']?.toString();
      if (code == null ||
          code.isEmpty ||
          businessId == null ||
          businessId.isEmpty ||
          userId == null ||
          userId.isEmpty) {
        return null;
      }
      return {
        'activationCode': code,
        'businessId': businessId,
        'userId': userId,
      };
    } on FormatException {
      await clearPendingCloudRegistration();
      return null;
    }
  }

  Future<void> clearPendingCloudRegistration() =>
      delete(_keyPendingCloudRegistration);

  Future<void> setSubscriptionCache({
    required String planName,
    required String status,
    String? expiresAt,
    required bool licenseActive,
    required String source,
    String? checkedAt,
    String? licenseToken,
  }) async {
    await write(_keySubPlan, planName);
    await write(_keySubStatus, status);
    await write(_keySubLicenseActive, licenseActive ? '1' : '0');
    await write(_keySubSource, source);
    await write(
      _keySubCheckedAt,
      checkedAt ?? DateTime.now().toIso8601String(),
    );
    if (expiresAt != null && expiresAt.isNotEmpty) {
      await write(_keySubExpires, expiresAt);
    } else {
      await delete(_keySubExpires);
    }
    if (licenseToken != null && licenseToken.isNotEmpty) {
      await write(_keySubLicenseToken, licenseToken);
    } else if (licenseToken != null) {
      // Chaîne vide explicitement fournie => on purge le jeton mémorisé.
      await delete(_keySubLicenseToken);
    }
  }

  Future<Map<String, String?>> getSubscriptionCache() async {
    return {
      'planName': await read(_keySubPlan),
      'status': await read(_keySubStatus),
      'expiresAt': await read(_keySubExpires),
      'checkedAt': await read(_keySubCheckedAt),
      'licenseActive': await read(_keySubLicenseActive),
      'source': await read(_keySubSource),
      'licenseToken': await read(_keySubLicenseToken),
    };
  }

  Future<void> clearSubscriptionCache() async {
    await delete(_keySubPlan);
    await delete(_keySubStatus);
    await delete(_keySubExpires);
    await delete(_keySubCheckedAt);
    await delete(_keySubLicenseActive);
    await delete(_keySubSource);
    await delete(_keySubLicenseToken);
  }

  Future<void> clearAuth() async {
    await delete(_keySessionToken);
    await delete(_keyCurrentUserId);
  }
}
