import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/config/app_config.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/security/secure_storage_service.dart';
import 'package:kumba_business/core/utils/id_generator.dart';
import 'package:kumba_business/shared/services/analytics_local_store.dart';
import 'package:kumba_business/shared/services/analytics_service.dart';
import 'package:path/path.dart' as p;

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
}

void main() {
  late AppDatabase db;
  late AnalyticsService analytics;
  late _MemorySecureStorage secure;
  late String businessId;
  late Directory folder;

  setUp(() async {
    db = createTestDatabase();
    secure = _MemorySecureStorage();
    folder = await Directory.systemTemp.createTemp('lynkstor_analytics_');
    analytics = AnalyticsService(
      db: db,
      secure: secure,
      localStore: AnalyticsLocalStore(
        documentsDirectoryProvider: () async => folder,
        externalDirectoryProvider: () async => null,
        publicFileWriter: (name, sourcePath) async {
          final dest = File(p.join(folder.path, 'public', name));
          await dest.parent.create(recursive: true);
          await File(sourcePath).copy(dest.path);
          return dest.path;
        },
        publicFolderPathProvider: () async => p.join(folder.path, 'public'),
      ),
    );
    AppAnalytics.bind(analytics);
    businessId = IdGenerator.uuid();
    final now = DateTime.now();
    await db.insertBusiness(
      BusinessesCompanion.insert(
        id: businessId,
        name: 'Panel',
        ownerName: 'Test',
        phone: '690000000',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await secure.setCurrentBusinessId(businessId);
    await secure.setDeviceId('install-test');
  });

  tearDown(() async {
    AppAnalytics.unbind();
    analytics.dispose();
    await db.close();
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
  });

  test('tracks events locally', () async {
    await analytics.track('app.opened');
    await analytics.track('sale.completed', properties: {'total': 1500});
    expect(await analytics.pendingCount(), 2);
    final counts = await db.analyticsEventCounts();
    expect(
      counts.map((e) => e['name']),
      containsAll(['app.opened', 'sale.completed']),
    );
  });

  test('snapshot counts catalog activations', () async {
    await db.insertProduct(
      ProductsCompanion.insert(
        id: IdGenerator.uuid(),
        businessId: businessId,
        name: 'Riz',
        sku: const Value('CAT-boutique-00001'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    final snap = await analytics.captureSnapshot(persist: false);
    expect(snap.productsCount, 1);
    expect(snap.catalogActivatedCount, 1);
    expect(snap.sector, 'boutique');
  });

  test('unknown events are ignored', () async {
    await analytics.track('hack.secret');
    expect(await analytics.pendingCount(), 0);
  });

  test('structured payload has Drive columns', () {
    final payload = analytics.structuredPayload(
      installId: 'install-test',
      businessId: 'biz-1',
      snapshot: const TrialSnapshot(
        salesCount: 3,
        soldFcfa: 12000,
        productsCount: 10,
        catalogActivatedCount: 8,
        customersCount: 2,
        expensesCount: 1,
        eventCount: 5,
        pendingCount: 5,
        openDays: 2,
        sector: 'boutique',
      ),
      events: [
        {
          'id': 'e1',
          'name': 'sale.completed',
          'properties': {'total': 4000},
          'createdAt': '2026-08-29T10:00:00.000Z',
        },
      ],
    );
    expect(payload['schema'], 'lynkstor.trial.v1');
    expect(payload['folderId'], AppConfig.analyticsDriveFolderId);
    final boutique = payload['boutique'] as Map<String, Object?>;
    expect(boutique['ventes'], 3);
    expect(boutique['ca_fcfa'], 12000);
    expect(boutique['secteur'], 'boutique');
    final evenements = payload['evenements'] as List;
    expect(evenements, hasLength(1));
    expect(evenements.first['event_name'], 'sale.completed');
  });

  test('AppAnalytics facade records when bound', () async {
    AppAnalytics.track('catalog.opened');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(await analytics.pendingCount(), 1);
  });

  test('persistToDeviceFolder writes analytics files', () async {
    await analytics.track('app.opened');
    await analytics.track('screen.viewed', properties: {'path': '/pos'});
    await analytics.track('sale.completed', properties: {'total': 2500});
    final result = await analytics.persistToDeviceFolder(force: true);
    expect(result != null, isTrue);
    final dir = Directory(
      p.join(folder.path, AppConfig.analyticsLocalFolderName),
    );
    expect(await dir.exists(), isTrue);
    Future<String> read(String name) =>
        File(p.join(dir.path, name)).readAsString();
    expect(await File(p.join(dir.path, 'LISEZMOI.txt')).exists(), isTrue);
    expect(await File(p.join(dir.path, 'boutique.json')).exists(), isTrue);
    expect(await File(p.join(dir.path, 'evenements.csv')).exists(), isTrue);
    expect(await File(p.join(dir.path, 'resume.csv')).exists(), isTrue);
    expect(await File(p.join(dir.path, 'quotidien.csv')).exists(), isTrue);
    final resume = await read('resume.csv');
    expect(resume, contains('install_id'));
    expect(resume, contains('install-test'));
    expect(resume, contains('ventes'));
    final events = await read('evenements.csv');
    expect(events, contains('app.opened'));
    expect(events, contains('sale.completed'));
    final boutique = await read('boutique.json');
    expect(boutique, contains('lynkstor.trial.v1'));
    expect(result!.publicFolderPath, p.join(folder.path, 'public'));
    expect(
      await File(p.join(folder.path, 'public', 'resume.csv')).exists(),
      isTrue,
    );
  });
}
