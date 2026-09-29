import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart' as enc;

import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/security/key_derivation.dart';
import '../../core/utils/id_generator.dart';
import '../../core/logging/app_logger.dart';
import 'business_service.dart';
import 'backup_service.dart';

/// Restauration depuis l’onboarding (premier lancement) à partir d’un fichier .kumba.
class RestoreOnboardingService {
  RestoreOnboardingService({
    required this.db,
    required this.secure,
    required this.businessService,
    BackupService? backupService,
  }) : _backupService = backupService ?? BackupService(db: db, secure: secure);

  final AppDatabase db;
  final SecureStorageService secure;
  final BusinessService businessService;
  final BackupService _backupService;

  Future<Map<String, dynamic>> inspect(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const BackupException('Fichier de sauvegarde introuvable.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const BackupException('Fichier de sauvegarde vide.');
    }
    final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return {
      'version': raw['version'],
      'businessName': raw['businessName'] ?? 'Inconnu',
      'businessId': raw['businessId'],
      'createdAt': raw['createdAt'],
      'size': bytes.length,
      'checksum': sha256.convert(bytes).toString(),
      'app': raw['app'],
    };
  }

  /// Restaure un commerce complet sur un appareil neuf.
  Future<Business> restoreFromFile({
    required String filePath,
    required String password,
    required String pin,
    String? ownerName,
  }) async {
    final meta = await inspect(filePath);
    final file = File(filePath);
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    if (raw['data'] == null || raw['iv'] == null) {
      throw const BackupException('Format de sauvegarde invalide.');
    }

    // Clé de backup : on tente la clé locale, sinon on crée le commerce puis on importe
    // avec une clé dérivée si nécessaire. Pour first-launch, on recrée le commerce
    // puis on importe le payload en clair après déchiffrement avec la clé stockée
    // dans le fichier… En production KUMBA la clé est dans secure storage de l’appareil
    // d’origine. Pour le transfert, le payload peut inclure une clé d’export optionnelle.

    Map<String, dynamic> payload;
    try {
      payload = await _decryptPayload(raw, transferPassword: password);
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException(
        'Impossible de déchiffrer la sauvegarde. '
        'Utilisez une sauvegarde créée sur cet appareil, ou un export de transfert. ($e)',
      );
    }

    final sourceBusiness = payload['business'] is Map
        ? Map<String, dynamic>.from(payload['business'] as Map)
        : const <String, dynamic>{};
    final businessName =
        sourceBusiness['name'] as String? ??
        (meta['businessName'] as String?) ??
        'Commerce restauré';
    final now = DateTime.now();

    // Crée le commerce hôte
    final business = await businessService.createBusiness(
      BusinessCreationInput(
        name: businessName,
        ownerName: ownerName?.trim().isNotEmpty == true
            ? ownerName!.trim()
            : sourceBusiness['ownerName'] as String? ?? 'Propriétaire',
        phone: sourceBusiness['phone'] as String? ?? '000000000',
        password: password,
        pin: pin,
        city: sourceBusiness['city'] as String?,
        neighborhood: sourceBusiness['neighborhood'] as String?,
        sector: sourceBusiness['sector'] as String? ?? 'boutique',
        currency: sourceBusiness['currency'] as String? ?? 'FCFA',
        language: sourceBusiness['language'] as String? ?? 'fr',
        modules: _modules(sourceBusiness['modulesJson']),
        isRestore: true,
      ),
    );

    try {
      await _backupService.importPayload(business.id, payload);
    } catch (_) {
      await _rollbackHostBusiness(business.id);
      rethrow;
    }

    await db.insertAudit(
      AuditLogsCompanion.insert(
        id: IdGenerator.uuid(),
        businessId: business.id,
        action: 'backup.restored_onboarding',
        detailsJson: Value(
          jsonEncode({
            'sourceBusiness': meta['businessId'],
            'checksum': meta['checksum'],
            'at': now.toIso8601String(),
          }),
        ),
        createdAt: now,
      ),
    );

    AppLogger.audit('backup.restored_onboarding', entityId: business.id);
    return (await db.getBusiness(business.id))!;
  }

  List<String> _modules(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).map((value) => '$value').toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> _rollbackHostBusiness(String businessId) async {
    await db.transaction(() async {
      await (db.delete(
        db.syncQueue,
      )..where((row) => row.businessId.equals(businessId))).go();
      await (db.delete(
        db.auditLogs,
      )..where((row) => row.businessId.equals(businessId))).go();
      await (db.delete(
        db.expenseCategories,
      )..where((row) => row.businessId.equals(businessId))).go();
      await (db.delete(
        db.devices,
      )..where((row) => row.businessId.equals(businessId))).go();
      await (db.delete(
        db.users,
      )..where((row) => row.businessId.equals(businessId))).go();
      await (db.delete(
        db.businesses,
      )..where((row) => row.id.equals(businessId))).go();
    });
    await secure.clearAuth();
    await secure.clearCurrentBusiness();
    await secure.setOnboardingDone(false);
    await secure.clearSubscriptionCache();
  }

  Future<Map<String, dynamic>> _decryptPayload(
    Map<String, dynamic> raw, {
    required String transferPassword,
  }) async {
    // Support export de transfert : champ transferKey (base64) optionnel dans le fichier
    enc.Key key;
    if (raw['kdf'] == 'pbkdf2-sha256') {
      final salt = raw['salt'];
      if (salt is! String) {
        throw const BackupException('Sel de sauvegarde invalide.');
      }
      key = enc.Key(
        derivePbkdf2Sha256(
          password: transferPassword,
          salt: base64Decode(salt),
          iterations: (raw['iterations'] as num?)?.toInt() ?? 120000,
        ),
      );
    } else if (raw['transferKey'] is String) {
      key = enc.Key(base64Decode(raw['transferKey'] as String));
    } else {
      final stored = await secure.getBackupKey();
      if (stored == null) {
        throw const BackupException(
          'Clé de déchiffrement absente. '
          'Exportez une sauvegarde « transfert téléphone » depuis l’ancien appareil.',
        );
      }
      key = enc.Key(base64Decode(stored));
    }

    _verifyMac(raw, key);
    final iv = enc.IV(base64Decode(raw['iv'] as String));
    final encrypter = enc.Encrypter(enc.AES(key));
    final decrypted = encrypter.decrypt64(raw['data'] as String, iv: iv);
    return jsonDecode(decrypted) as Map<String, dynamic>;
  }

  void _verifyMac(Map<String, dynamic> raw, enc.Key key) {
    if ((raw['version'] as num?)?.toInt() == 1) return;
    final encodedMac = raw['mac'];
    if (encodedMac is! String) {
      throw const BackupException('Sauvegarde non authentifiée.');
    }
    final expected = base64Decode(encodedMac);
    final actual = Hmac(sha256, key.bytes)
        .convert(
          utf8.encode(
            jsonEncode([
              raw['version'],
              raw['businessId'],
              raw['createdAt'],
              raw['iv'],
              raw['data'],
              raw['type'],
              raw['kdf'],
              raw['iterations'],
              raw['salt'],
            ]),
          ),
        )
        .bytes;
    if (!constantTimeBytesEqual(expected, actual)) {
      throw const BackupException(
        'Sauvegarde altérée ou mot de passe de transfert incorrect.',
      );
    }
  }
}
