import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/security/secure_storage_service.dart';
import 'package:kumba_business/core/sync/sync_engine.dart';
import 'package:kumba_business/shared/services/business_service.dart';
import 'package:kumba_business/shared/services/session_service.dart';

class _MemorySecureStorage extends SecureStorageService {
  final Map<String, String> values = {};

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    values.clear();
  }

  @override
  Future<void> setPassword(String password) => write('test_password', password);

  @override
  Future<bool> verifyPassword(String password) async =>
      values['test_password'] == password;

  @override
  Future<void> setPin(String pin) => write('test_pin', pin);

  @override
  Future<bool> verifyPin(String pin) async => values['test_pin'] == pin;

  @override
  Future<void> resetPinFailures() async {}

  @override
  Future<Duration?> pinLockRemaining() async => null;

  @override
  Future<void> recordPinFailure() async {}
}

BusinessCreationInput _demoInput() {
  return BusinessCreationInput(
    name: 'Commerce test',
    ownerName: 'Propriétaire test',
    phone: '690000000',
    password: 'motdepasse',
    pin: '1234',
    isDemo: true,
  );
}

Future<void> _insertBusinessAndOwner(
  AppDatabase db, {
  required String businessId,
  required String userId,
}) async {
  final now = DateTime.now();
  await db.insertBusiness(
    BusinessesCompanion.insert(
      id: businessId,
      name: 'Ancien commerce',
      ownerName: 'Ancien propriétaire',
      phone: '600000000',
      createdAt: now,
      updatedAt: now,
    ),
  );
  await db.insertUser(
    UsersCompanion.insert(
      id: userId,
      businessId: businessId,
      fullName: 'Ancien propriétaire',
      isOwner: const Value(true),
      createdAt: now,
      updatedAt: now,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _MemorySecureStorage secure;
  late SyncEngine sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    secure = _MemorySecureStorage();
    sync = SyncEngine(db);
  });

  tearDown(() async {
    await sync.dispose();
    await db.close();
  });

  group('BusinessService recovery', () {
    test('reassigns an existing device id without a UNIQUE failure', () async {
      const oldBusinessId = 'old-business';
      const oldUserId = 'old-user';
      const deviceId = 'stable-device';
      await _insertBusinessAndOwner(
        db,
        businessId: oldBusinessId,
        userId: oldUserId,
      );
      await db
          .into(db.devices)
          .insert(
            DevicesCompanion.insert(
              id: deviceId,
              businessId: oldBusinessId,
              userId: const Value(oldUserId),
              name: 'Ancien appareil',
              createdAt: DateTime.now(),
            ),
          );
      await secure.setDeviceId(deviceId);

      final created = await BusinessService(
        db: db,
        secure: secure,
        sync: sync,
      ).createBusiness(_demoInput());

      final devices = await db.select(db.devices).get();
      expect(devices, hasLength(1));
      expect(devices.single.id, deviceId);
      expect(devices.single.businessId, created.id);
      expect(devices.single.userId, await secure.getCurrentUserId());

      final integrity = await db
          .customSelect('PRAGMA integrity_check')
          .getSingle();
      expect(integrity.data.values.single, 'ok');
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });

    test(
      'coalesces concurrent creation attempts into one transaction',
      () async {
        final service = BusinessService(db: db, secure: secure, sync: sync);

        final first = service.createBusiness(_demoInput());
        final second = service.createBusiness(_demoInput());

        expect(identical(first, second), isTrue);
        final results = await Future.wait([first, second]);
        expect(results[0].id, results[1].id);
        expect(await db.select(db.businesses).get(), hasLength(1));
        expect(await db.select(db.users).get(), hasLength(1));
        expect(await db.select(db.devices).get(), hasLength(1));
      },
    );
  });

  group('SessionService recovery', () {
    test('repairs a stale current user from the business owner', () async {
      const businessId = 'business';
      const ownerId = 'owner';
      await _insertBusinessAndOwner(
        db,
        businessId: businessId,
        userId: ownerId,
      );
      await secure.setOnboardingDone(true);
      await secure.setCurrentBusinessId(businessId);
      await secure.setCurrentUserId('missing-user');
      await secure.setSessionToken('session');

      final result = await SessionService(db: db, secure: secure).bootstrap();

      expect(result.needsOnboarding, isFalse);
      expect(result.isAuthenticated, isTrue);
      expect(result.user?.id, ownerId);
      expect(await secure.getCurrentUserId(), ownerId);
    });

    test('rejects login when the stored user no longer exists', () async {
      await secure.setPin('1234');
      await secure.setCurrentUserId('missing-user');
      await secure.setCurrentBusinessId('missing-business');

      final loggedIn = await SessionService(
        db: db,
        secure: secure,
      ).loginWithPin('1234');

      expect(loggedIn, isFalse);
      expect(await secure.getSessionToken(), equals(null));
    });
  });
}
