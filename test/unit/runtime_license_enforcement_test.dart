import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kumba_business/core/config/app_config.dart';
import 'package:kumba_business/core/config/runtime_config.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/security/secure_storage_service.dart';
import 'package:kumba_business/shared/services/session_service.dart';

/// Cache de séchage synchrone, sans keystorage natif.
class _MemorySecureStorage extends SecureStorageService {
  final Map<String, String> values = {};

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> deleteAll() async => values.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ActivationPolicy.reset();
    RuntimeConfig.lastRequireAgentActivationCode = null;
  });

  group('ActivationPolicy (verrou piloté par le serveur, sans rebuild)', () {
    test('defaults to the compile-time value when nothing fetched yet', () {
      expect(
        ActivationPolicy.requireAgentActivationCode,
        AppConfig.requireAgentActivationCode,
      );
    });

    test('a server value of true wins over the compile-time false', () {
      // C'est le scénario go-live : la binaire en circulation reste la même,
      // seul le serveur bascule `requireAgentActivationCode`.
      ActivationPolicy.sync(true);
      expect(ActivationPolicy.requireAgentActivationCode, isTrue);
    });

    test('null (config pas encore connue) ne décrète rien', () {
      ActivationPolicy.sync(true);
      ActivationPolicy.sync(null);
      expect(ActivationPolicy.requireAgentActivationCode, isTrue);
    });

    test('requireAgentActivationCodeOr falls back on the compile-time const',
        () {
      expect(RuntimeConfig.requireAgentActivationCodeOr(true), isTrue);
      expect(RuntimeConfig.requireAgentActivationCodeOr(false), isFalse);
      RuntimeConfig.lastRequireAgentActivationCode = false;
      expect(RuntimeConfig.requireAgentActivationCodeOr(true), isFalse);
    });
  });

  group('SessionService greffe la politique runtime sur la licence', () {
    late AppDatabase db;
    late _MemorySecureStorage secure;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = createTestDatabase();
      secure = _MemorySecureStorage();
      // Business local forgé, déjà en cache : c'est exactement ce qu'un
      // appareil roots peut fabriquer sans passer par le cloud.
      await secure.setCurrentBusinessId('biz-test');
      await secure.setSubscriptionCache(
        planName: 'LOCAL',
        status: 'active',
        licenseActive: true,
        source: 'local',
      );
    });

    tearDown(() async => db.close());

    test('policy=true closes the forged `local` bypass', () async {
      final service = SessionService(
        db: db,
        secure: secure,
        enforceLicensePolicy: () async => true,
      );

      final info = await service.loadSubscriptionLocal();

      expect(info.enforceLicense, isTrue);
      expect(info.signedLicenseVerified, isFalse);
      expect(info.allowsSales, isFalse);
    });

    test('policy=false keeps the historic offline-first behaviour', () async {
      final service = SessionService(
        db: db,
        secure: secure,
        enforceLicensePolicy: () async => false,
      );

      final info = await service.loadSubscriptionLocal();

      expect(info.enforceLicense, isFalse);
      expect(info.allowsSales, isTrue);
    });

    test('policy is resolved asynchronously (late runtime config arrival)',
        () async {
      final service = SessionService(
        db: db,
        secure: secure,
        enforceLicensePolicy: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return true;
        },
      );

      expect((await service.loadSubscriptionLocal()).allowsSales, isFalse);
    });

    test('a failing policy never silently unlocks: falls back on the const',
        () async {
      final service = SessionService(
        db: db,
        secure: secure,
        enforceLicensePolicy: () async => throw StateError('offline config'),
      );

      final info = await service.loadSubscriptionLocal();

      expect(info.enforceLicense, AppConfig.requireAgentActivationCode);
    });

    test('an unwired policy (tests, hors Riverpod) uses the const', () async {
      final service = SessionService(db: db, secure: secure);

      final info = await service.loadSubscriptionLocal();

      expect(info.enforceLicense, AppConfig.requireAgentActivationCode);
    });
  });
}
