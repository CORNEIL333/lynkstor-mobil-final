import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kumba_business/core/config/runtime_config.dart';

void main() {
  group('compareVersions', () {
    test('champ par champ, numérique', () {
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(compareVersions('1.2.0', '1.2.0'), 0);
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('2.0', '1.9.9'), greaterThan(0));
    });

    test('longueurs différentes = zéros implicites', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.1', '1.2'), greaterThan(0));
    });
  });

  group('RuntimeConfig', () {
    test('safeDefault ne restreint rien (offline-first)', () {
      const c = RuntimeConfig.safeDefault;
      expect(c.maintenance, isFalse);
      expect(c.killModules, isEmpty);
      expect(c.updateRequiredFor('1.2.0'), isFalse);
      expect(c.isModuleKilled('ai'), isFalse);
    });

    test('fromJson décrypte la charge utile et normalise killModules', () {
      final c = RuntimeConfig.fromJson({
        'minSupportedVersion': '9.9.9',
        'latestVersion': '10.0.0',
        'maintenance': true,
        'killModules': ['AI', ' Scanner ', ''],
        'maxOfflineDays': 3,
        'requireAgentActivationCode': true,
        'updateMessage': 'update now',
      });
      expect(c.minSupportedVersion, '9.9.9');
      expect(c.maintenance, isTrue);
      expect(c.killModules, {'ai', 'scanner'});
      expect(c.maxOfflineDays, 3);
      expect(c.requireAgentActivationCode, isTrue);
      expect(c.updateRequiredFor('1.2.0'), isTrue);
      expect(c.isModuleKilled('AI'), isTrue);
    });

    test('version manquante => min 0.0.0 (jamais de blocage abusif)', () {
      final c = RuntimeConfig.fromJson({'maintenance': false});
      expect(c.minSupportedVersion, '0.0.0');
      expect(c.updateRequiredFor('1.2.0'), isFalse);
    });
  });

  group('RuntimeConfigService.fetch', () {
    test('enveloppe { status, data } dépaquetée', () async {
      final service = RuntimeConfigService(
        configUrl: 'https://example.invalid/v1/config',
        client: MockClient((req) async {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {'minSupportedVersion': '5.0.0', 'maintenance': false},
            }),
            200,
          );
        }),
      );
      final c = await service.fetch();
      expect(c.minSupportedVersion, '5.0.0');
      expect(c.fetchedAt, isNotNull);
    });

    test('HTTP != 200 => fallback sûr', () async {
      final service = RuntimeConfigService(
        configUrl: 'https://example.invalid/v1/config',
        client: MockClient((req) async => http.Response('nope', 400)),
      );
      final c = await service.fetch();
      expect(c, same(RuntimeConfig.safeDefault));
    });

    test('exception réseau => fallback sûr (ne lève jamais)', () async {
      final service = RuntimeConfigService(
        configUrl: 'https://example.invalid/v1/config',
        client: MockClient((req) async => throw http.ClientException('boom')),
      );
      final c = await service.fetch();
      expect(c.maintenance, isFalse);
      expect(c.updateRequiredFor('1.2.0'), isFalse);
    });
  });
}
