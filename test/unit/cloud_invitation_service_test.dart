import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/errors/app_exception.dart';
import 'package:kumba_business/core/security/secure_storage_service.dart';
import 'package:kumba_business/core/sync/sync_engine.dart';
import 'package:kumba_business/shared/services/cloud_invitation_service.dart';
import 'package:kumba_business/shared/services/invitation_service.dart';

/// Storage en mémoire (même pattern que business_session_recovery_test).
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

Map<String, dynamic> _envelope(Map<String, dynamic>? data) => {
  'status': 'ok',
  'data': data,
};

CloudInvitationService _service(MockClient client) =>
    CloudInvitationService(client: client);

void main() {
  group('CloudInvitationService.looksCloudCode', () {
    test('accepte INV-XXXX-XXXX, rejette les codes locaux', () {
      expect(CloudInvitationService.looksCloudCode('INV-A3K9-MP2X'), isTrue);
      expect(CloudInvitationService.looksCloudCode(' inv-a3k9-mp2x '), isTrue);
      expect(CloudInvitationService.looksCloudCode('A3K9MP2X'), isFalse);
      expect(CloudInvitationService.looksCloudCode('INV-A3K9'), isFalse);
    });
  });

  group('CloudInvitationService peek/accept', () {
    test('peek POSTe le code et parse la prévisualisation', () async {
      late http.Request captured;
      final service = _service(
        MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode(_envelope({
              'businessId': 'biz-1',
              'businessName': 'Boutique Awa',
              'sector': 'boutique',
              'role': 'seller',
            })),
            200,
          );
        }),
      );
      final peek = await service.peekInvitation('inv-a3k9-mp2x');
      expect(captured.url.path, '/api/v1/invitations/peek');
      expect(jsonDecode(captured.body)['code'], 'INV-A3K9-MP2X');
      expect(peek.businessId, 'biz-1');
      expect(peek.role, 'seller');
      service.dispose();
    });

    test('peek 404 -> AuthException (code inconnu)', () async {
      final service = _service(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'status': 'error', 'message': 'Code inconnu.'}),
            404,
          ),
        ),
      );
      expect(
        () => service.peekInvitation('INV-ZZZZ-ZZZZ'),
        throwsA(isA<AuthException>()),
      );
      service.dispose();
    });

    test('accept renvoie jeton + plan + snapshot boutique', () async {
      final service = _service(
        MockClient((req) async {
          expect(req.headers['Authorization'], isNull);
          return http.Response(
            jsonEncode(_envelope({
              'businessId': 'biz-1',
              'userId': 'user-2',
              'role': 'seller',
              'syncToken': 'lynk_abc',
              'syncEndpoint': 'https://cloud.invalid/api/v1/sync/push',
              'planName': 'STARTER',
              'expiresAt': '2026-10-15T00:00:00.000Z',
              'business': {'name': 'Boutique Awa', 'sector': 'boutique'},
            })),
            200,
          );
        }),
      );
      final join = await service.acceptInvitation(
        code: 'INV-A3K9-MP2X',
        deviceId: 'device-b',
        fullName: 'Kofi',
      );
      expect(join.syncToken, 'lynk_abc');
      expect(join.planName, 'STARTER');
      expect(join.businessName, 'Boutique Awa');
      service.dispose();
    });

    test('accept sans jeton -> SyncException (réponse invalide)', () async {
      final service = _service(
        MockClient(
          (_) async => http.Response(jsonEncode(_envelope({'role': 'seller'})), 200),
        ),
      );
      expect(
        () => service.acceptInvitation(
          code: 'INV-A3K9-MP2X',
          deviceId: 'device-b',
          fullName: 'Kofi',
        ),
        throwsA(isA<SyncException>()),
      );
      service.dispose();
    });

    test('erreur réseau -> OfflineException', () async {
      final service = _service(
        MockClient((_) async => throw http.ClientException('boom')),
      );
      expect(
        () => service.peekInvitation('INV-A3K9-MP2X'),
        throwsA(isA<OfflineException>()),
      );
      service.dispose();
    });
  });

  group('InvitationService routage cloud/local', () {
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

    test('createInvitation poste cloud -> gateway /invitations/create', () async {
      secure.values['kumba_cloud_sync_token'] = 'lynk_host_token';
      late http.Request captured;
      final service = InvitationService(
        db: db,
        secure: secure,
        sync: sync,
        cloud: _service(
          MockClient((req) async {
            captured = req;
            return http.Response(
              jsonEncode(_envelope({'code': 'INV-A3K9-MP2X'})),
              200,
            );
          }),
        ),
      );
      final code = await service.createInvitation(
        businessId: 'biz-1',
        role: 'seller',
        createdBy: 'user-1',
      );
      expect(code, 'INV-A3K9-MP2X');
      expect(captured.url.path, '/api/v1/invitations/create');
      expect(captured.headers['Authorization'], 'Bearer lynk_host_token');
      // Le chemin cloud ne doit PAS écrire de code local dans le storage.
      expect(secure.values.keys.where((k) => k.startsWith('invite_')), isEmpty);
    });

    test('createInvitation poste hors cloud -> code local 8 caractères', () async {
      final service = InvitationService(
        db: db,
        secure: secure,
        sync: sync,
        cloud: _service(MockClient((_) async => throw StateError('jamais appelé'))),
      );
      final code = await service.createInvitation(
        businessId: 'biz-1',
        role: 'seller',
      );
      expect(code.length, 8);
      expect(CloudInvitationService.looksCloudCode(code), isFalse);
      expect(secure.values['invite_$code'], isNotNull);
    });

    test('peek code INV -> passé par le cloud, vue du commerce distant', () async {
      final service = InvitationService(
        db: db,
        secure: secure,
        sync: sync,
        cloud: _service(
          MockClient((req) async {
            expect(req.url.path, '/api/v1/invitations/peek');
            return http.Response(
              jsonEncode(_envelope({
                'businessId': 'biz-remote',
                'businessName': 'Boutique distante',
                'sector': 'general',
                'role': 'manager',
              })),
              200,
            );
          }),
        ),
      );
      final info = await service.peekInvitation('INV-A3K9-MP2X');
      expect(info.business.id, 'biz-remote');
      expect(info.business.mode, 'team');
      expect(info.role, 'manager');
    });

    test('accept code INV -> commerce + utilisateur + jeton persistés', () async {
      final service = InvitationService(
        db: db,
        secure: secure,
        sync: sync,
        cloud: _service(
          MockClient((req) async {
            expect(req.url.path, '/api/v1/invitations/accept');
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['fullName'], 'Kofi');
            return http.Response(
              jsonEncode(_envelope({
                'businessId': 'biz-remote',
                'userId': 'user-kofi',
                'role': 'seller',
                'syncToken': 'lynk_join_token',
                'syncEndpoint': 'https://cloud.invalid/api/v1/sync/push',
                'planName': 'STARTER',
                'business': {
                  'name': 'Boutique distante',
                  'sector': 'general',
                  'ownerName': 'Awa',
                  'phone': '+2250700000001',
                },
              })),
              200,
            );
          }),
        ),
      );
      final user = await service.acceptInvitation(
        code: 'INV-A3K9-MP2X',
        fullName: 'Kofi',
        pin: '1234',
      );
      expect(user.id, 'user-kofi');
      expect(user.role, 'seller');
      // Le poste joint doit être persisté localement avec son jeton d'appareil.
      final business = await db.getBusiness('biz-remote');
      expect(business, isNotNull);
      expect(business!.name, 'Boutique distante');
      expect(secure.values['kumba_cloud_sync_token'], 'lynk_join_token');
      expect(secure.values['kumba_cloud_sync_endpoint'], contains('/sync/push'));
      expect(secure.values['kumba_current_business_id'], 'biz-remote');
      expect(secure.values['kumba_current_user_id'], 'user-kofi');
      expect(secure.values['test_pin'], '1234');
      // L'appareil est rattaché à la boutique rejointe.
      final deviceId = secure.values['kumba_device_id']!;
      final device = await (db.select(
        db.devices,
      )..where((t) => t.id.equals(deviceId))).getSingleOrNull();
      expect(device?.businessId, 'biz-remote');
    });

    test('accept code local inconnu -> AuthException via cloud 404', () async {
      final service = InvitationService(
        db: db,
        secure: secure,
        sync: sync,
        cloud: _service(
          MockClient(
            (_) async => http.Response(
              jsonEncode({'status': 'error', 'message': 'Code inconnu.'}),
              404,
            ),
          ),
        ),
      );
      expect(
        () => service.acceptInvitation(
          code: 'AAAABBBB',
          fullName: 'Quidam',
          pin: '1234',
        ),
        throwsA(isA<AuthException>()),
      );
    });
  });
}
