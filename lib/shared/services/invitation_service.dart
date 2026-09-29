import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/utils/id_generator.dart';
import '../../core/logging/app_logger.dart';

/// Invitations locales mode équipe (code à usage unique sur l’appareil hôte).
/// Pour multi-appareils distants, le même flux s’appuie sur la file de sync.
class InvitationService {
  InvitationService({
    required this.db,
    required this.secure,
    required this.sync,
  });

  final AppDatabase db;
  final SecureStorageService secure;
  final SyncEngine sync;

  static const _keyPrefix = 'invite_';

  Future<String> createInvitation({
    required String businessId,
    required String role,
    String? createdBy,
  }) async {
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
    final raw = await secure.read('$_keyPrefix${code.trim().toUpperCase()}');
    if (raw == null) {
      throw const AuthException('Code d’invitation invalide ou expiré.');
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

  Future<User> acceptInvitation({
    required String code,
    required String fullName,
    required String pin,
    String? phone,
  }) async {
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
