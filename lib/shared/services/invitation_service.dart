import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/config/sector_modules.dart';
import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/utils/id_generator.dart';
import '../../core/logging/app_logger.dart';
import 'cloud_invitation_service.dart';

/// Invitations équipe : locales (mode équipe sur le même appareil) ET cloud
/// multi-postes (codes INV-XXXX-XXXX, gateway Neon). Les codes cloud sont
/// détectés par leur format et routés vers [CloudInvitationService] ; un
/// appareil qui rejoint un commerce cloud reçoit son propre jeton d'appareil
/// et démarre la synchronisation.
class InvitationService {
  InvitationService({
    required this.db,
    required this.secure,
    required this.sync,
    CloudInvitationService? cloud,
  }) : _cloud = cloud ?? CloudInvitationService();

  final AppDatabase db;
  final SecureStorageService secure;
  final SyncEngine sync;
  final CloudInvitationService _cloud;

  static const _keyPrefix = 'invite_';

  Future<String> createInvitation({
    required String businessId,
    required String role,
    String? createdBy,
  }) async {
    // Poste connecté au cloud : l'invitation est émise côté serveur pour que
    // d'autres appareils physiques puissent la consommer.
    final syncToken = await secure.getCloudSyncToken();
    if (syncToken != null && syncToken.isNotEmpty) {
      try {
        final code = await _cloud.createInvitation(
          syncToken: syncToken,
          role: role,
          createdBy: createdBy,
        );
        await db.insertAudit(
          AuditLogsCompanion.insert(
            id: IdGenerator.uuid(),
            businessId: businessId,
            userId: Value(createdBy),
            action: 'invitation.created_cloud',
            detailsJson: Value(jsonEncode({'role': role, 'code': code})),
            createdAt: DateTime.now(),
          ),
        );
        AppLogger.audit(
          'invitation.created_cloud',
          userId: createdBy,
          entityId: businessId,
        );
        return code;
      } on OfflineException {
        AppLogger.w('invitation cloud indisponible, repli local');
      }
    }
    final code = _generateCode();
    final payload = jsonEncode({
      'businessId': businessId,
      'role': role,
      'createdBy': createdBy,
      'createdAt': DateTime.now().toIso8601String(),
      'expiresAt': DateTime.now()
          .add(const Duration(days: 7))
          .toIso8601String(),
      'used': false,
    });
    await secure.write('$_keyPrefix$code', payload);
    await db.insertAudit(
      AuditLogsCompanion.insert(
        id: IdGenerator.uuid(),
        businessId: businessId,
        userId: Value(createdBy),
        action: 'invitation.created',
        detailsJson: Value(jsonEncode({'role': role, 'code': code})),
        createdAt: DateTime.now(),
      ),
    );
    AppLogger.audit(
      'invitation.created',
      userId: createdBy,
      entityId: businessId,
    );
    return code;
  }

  Future<({Business business, String role})> peekInvitation(String code) async {
    final normalized = code.trim().toUpperCase();
    if (CloudInvitationService.looksCloudCode(normalized)) {
      return _peekCloud(normalized);
    }
    final raw = await secure.read('$_keyPrefix$normalized');
    if (raw == null) {
      // Code court inconnu localement : dernière chance côté cloud (le poste
      // peut avoir été réinstallé et ne plus connaître l'invitation locale).
      return _peekCloud(normalized);
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    if (map['used'] == true) {
      throw const AuthException('Ce code a déjà été utilisé.');
    }
    final expires = DateTime.tryParse(map['expiresAt'] as String? ?? '');
    if (expires != null && expires.isBefore(DateTime.now())) {
      throw const AuthException('Ce code d’invitation a expiré.');
    }
    final business = await db.getBusiness(map['businessId'] as String);
    if (business == null) {
      throw const NotFoundException(
        'Commerce de l’invitation introuvable sur cet appareil.',
      );
    }
    return (business: business, role: map['role'] as String? ?? 'seller');
  }

  /// Prévisualisation cloud : reconstruit une vue locale du commerce distant
  /// (pas encore enregistré sur cet appareil) pour l'affichage de confirmation.
  Future<({Business business, String role})> _peekCloud(String code) async {
    final peek = await _cloud.peekInvitation(code);
    if (peek.businessId.isEmpty) {
      throw const AuthException('Code d’invitation invalide ou expiré.');
    }
    final now = DateTime.now();
    final business = Business(
      id: peek.businessId,
      name: peek.businessName,
      ownerName: '',
      phone: '',
      sector: peek.sector,
      currency: 'FCFA',
      currencyCode: 'XOF',
      language: 'fr',
      mode: 'team',
      modulesJson: jsonEncode(SectorModules.forSector(peek.sector)),
      isDemo: false,
      createdAt: now,
      updatedAt: now,
      version: 1,
      isDeleted: false,
    );
    return (business: business, role: peek.role);
  }

  Future<User> acceptInvitation({
    required String code,
    required String fullName,
    required String pin,
    String? phone,
  }) async {
    final normalized = code.trim().toUpperCase();
    if (CloudInvitationService.looksCloudCode(normalized)) {
      return _acceptCloud(normalized, fullName: fullName, pin: pin, phone: phone);
    }
    if (await secure.read('$_keyPrefix$normalized') == null) {
      // Jamais vue localement : tenter le cloud avant de conclure à une
      // invitation locale consommée/expirée.
      return _acceptCloud(normalized, fullName: fullName, pin: pin, phone: phone);
    }
    final info = await peekInvitation(code);
    final now = DateTime.now();
    final userId = IdGenerator.uuid();

    await db.insertUser(
      UsersCompanion.insert(
        id: userId,
        businessId: info.business.id,
        fullName: fullName.trim(),
        phone: Value(phone),
        role: Value(info.role),
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Marquer invitation utilisée
    final raw = await secure.read('$_keyPrefix${code.trim().toUpperCase()}');
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map['used'] = true;
      map['usedBy'] = userId;
      await secure.write(
        '$_keyPrefix${code.trim().toUpperCase()}',
        jsonEncode(map),
      );
    }

    // PIN employé stocké avec clé user-specific
    await secure.write('pin_hash_$userId', _hashPin(pin, userId));
    await secure.setCurrentBusinessId(info.business.id);
    await secure.setCurrentUserId(userId);
    await secure.setOnboardingDone(true);
    await secure.setSessionToken('local_${now.millisecondsSinceEpoch}');
    // Conserver un PIN global pour le lock rapide de l'utilisateur courant
    await secure.setPin(pin);

    await db.insertAudit(
      AuditLogsCompanion.insert(
        id: IdGenerator.uuid(),
        businessId: info.business.id,
        userId: Value(userId),
        action: 'invitation.accepted',
        entityType: const Value('user'),
        entityId: Value(userId),
        createdAt: now,
      ),
    );

    final user = (await db.getUser(userId))!;
    await sync.enqueue(
      businessId: info.business.id,
      entityType: 'user',
      entityId: userId,
      operation: 'create',
      payload: user.toJson(),
      userId: userId,
    );
    return user;
  }

  /// Joint un commerce cloud via code INV-XXXX-XXXX : émet le commerce côté
  /// local, enregistre l'employé, persiste le jeton d'appareil reçu et
  /// démarre la synchronisation — même pattern que l'inscription BusinessService.
  Future<User> _acceptCloud(
    String code, {
    required String fullName,
    required String pin,
    String? phone,
  }) async {
    final deviceId = await _ensureDeviceId();
    final join = await _cloud.acceptInvitation(
      code: code,
      deviceId: deviceId,
      fullName: fullName,
      phone: phone,
    );
    final now = DateTime.now();
    final modules = SectorModules.forSector(join.sector);

    await db.transaction(() async {
      await db.insertBusiness(
        BusinessesCompanion.insert(
          id: join.businessId,
          name: join.businessName,
          ownerName: join.ownerName ?? '',
          phone: join.phone ?? '',
          sector: Value(join.sector),
          mode: const Value('team'),
          modulesJson: Value(jsonEncode(modules)),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.insertUser(
        UsersCompanion.insert(
          id: join.userId,
          businessId: join.businessId,
          fullName: fullName.trim(),
          phone: Value(phone),
          role: Value(join.role),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.upsertDevice(
        DevicesCompanion.insert(
          id: deviceId,
          businessId: join.businessId,
          userId: Value(join.userId),
          name: 'Poste joint',
          createdAt: now,
        ),
      );
      await db.insertAudit(
        AuditLogsCompanion.insert(
          id: IdGenerator.uuid(),
          businessId: join.businessId,
          userId: Value(join.userId),
          deviceId: Value(deviceId),
          action: 'invitation.accepted_cloud',
          entityType: const Value('user'),
          entityId: Value(join.userId),
          createdAt: now,
        ),
      );
    });

    await secure.setCloudSyncToken(join.syncToken);
    await secure.setCloudSyncEndpoint(join.syncEndpoint);
    await secure.setSubscriptionCache(
      planName: join.planName ?? 'STARTER',
      status: 'active',
      expiresAt: join.expiresAt,
      licenseActive: true,
      source: 'cloud',
    );
    // PIN employé stocké avec clé user-specific + PIN global pour le lock.
    await secure.write('pin_hash_${join.userId}', _hashPin(pin, join.userId));
    await secure.setPin(pin);
    await secure.setCurrentBusinessId(join.businessId);
    await secure.setCurrentUserId(join.userId);
    await secure.setOnboardingDone(true);
    await secure.setSessionToken('local_${now.millisecondsSinceEpoch}');

    try {
      await sync.start(
        endpoint: join.syncEndpoint,
        authToken: join.syncToken,
        businessId: join.businessId,
        deviceId: deviceId,
      );
    } catch (error, stack) {
      AppLogger.w('Cloud sync start deferred after join', error, stack);
    }
    AppLogger.audit(
      'invitation.accepted_cloud',
      userId: join.userId,
      entityId: join.businessId,
    );
    return (await db.getUser(join.userId))!;
  }

  Future<String> _ensureDeviceId() async {
    final existing = await secure.getDeviceId();
    if (existing != null) return existing;
    final id = IdGenerator.uuid();
    await secure.setDeviceId(id);
    return id;
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _hashPin(String pin, String userId) {
    // Délègue au même principe que SecureStorage — hash simple local
    return '${userId}_${pin.length}_${pin.codeUnits.fold<int>(0, (a, b) => a + b * 17)}';
  }
}
