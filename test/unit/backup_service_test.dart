import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/errors/app_exception.dart';
import 'package:kumba_business/core/security/secure_storage_service.dart';
import 'package:kumba_business/core/sync/sync_engine.dart';
import 'package:kumba_business/shared/services/backup_service.dart';
import 'package:kumba_business/shared/services/business_service.dart';
import 'package:kumba_business/shared/services/restore_onboarding_service.dart';

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

class _FailingBackupService extends BackupService {
  _FailingBackupService({
    required super.db,
    required super.secure,
    required super.documentsDirectoryProvider,
  });

  @override
  Future<void> importPayload(String businessId, Map<String, dynamic> payload) {
    throw const BackupException('Échec simulé après création du commerce.');
  }
}

Future<void> _insertBusiness(
  AppDatabase db, {
  required String businessId,
  required String ownerId,
  required String name,
}) async {
  final now = DateTime.utc(2026, 7, 31, 10);
  await db
      .into(db.businesses)
      .insert(
        BusinessesCompanion.insert(
          id: businessId,
          name: name,
          ownerName: 'Awa Diallo',
          phone: '690000000',
          city: const Value('Douala'),
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          id: ownerId,
          businessId: businessId,
          fullName: 'Awa Diallo',
          role: const Value('owner'),
          isOwner: const Value(true),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late AppDatabase sourceDb;
  late AppDatabase targetDb;
  late _MemorySecureStorage secure;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('kumba_backup_test_');
    sourceDb = createTestDatabase();
    targetDb = createTestDatabase();
    secure = _MemorySecureStorage();
  });

  tearDown(() async {
    await sourceDb.close();
    await targetDb.close();
    if (await documents.exists()) {
      await documents.delete(recursive: true);
    }
  });

  test(
    'backup v3 round-trip restores profile, users, settings, inventory and attendance',
    () async {
      const sourceBusinessId = 'business-source';
      const sourceOwnerId = 'owner-source';
      const targetBusinessId = 'business-target';
      const targetOwnerId = 'owner-target';
      final now = DateTime.utc(2026, 7, 31, 11);
      final media = File('${documents.path}${Platform.pathSeparator}proof.jpg');
      await media.writeAsBytes([1, 2, 3, 4], flush: true);

      await _insertBusiness(
        sourceDb,
        businessId: sourceBusinessId,
        ownerId: sourceOwnerId,
        name: 'Kumba Market',
      );
      await _insertBusiness(
        targetDb,
        businessId: targetBusinessId,
        ownerId: targetOwnerId,
        name: 'Commerce vide',
      );
      await sourceDb
          .into(sourceDb.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'receipt_footer_$sourceBusinessId',
              value: 'Merci et à bientôt',
              businessId: const Value(sourceBusinessId),
              updatedAt: now,
            ),
          );
      await sourceDb
          .into(sourceDb.products)
          .insert(
            ProductsCompanion.insert(
              id: 'product-1',
              businessId: sourceBusinessId,
              name: 'Café du Cameroun',
              stockQty: const Value(12),
              photoPath: Value(media.path),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await sourceDb
          .into(sourceDb.inventorySessions)
          .insert(
            InventorySessionsCompanion.insert(
              id: 'inventory-1',
              businessId: sourceBusinessId,
              name: 'Inventaire juillet',
              userId: const Value(sourceOwnerId),
              startedAt: now,
            ),
          );
      await sourceDb
          .into(sourceDb.inventoryLines)
          .insert(
            InventoryLinesCompanion.insert(
              id: 'inventory-line-1',
              sessionId: 'inventory-1',
              productId: 'product-1',
              expectedQty: 12,
              countedQty: const Value(11),
              photoPath: Value(media.path),
            ),
          );
      await sourceDb
          .into(sourceDb.attendanceRecords)
          .insert(
            AttendanceRecordsCompanion.insert(
              id: 'attendance-1',
              businessId: sourceBusinessId,
              userId: sourceOwnerId,
              type: 'check_in',
              photoPath: Value(media.path),
              recordedAt: now,
            ),
          );

      final sourceService = BackupService(
        db: sourceDb,
        secure: secure,
        documentsDirectoryProvider: () async => documents,
      );
      final targetService = BackupService(
        db: targetDb,
        secure: secure,
        documentsDirectoryProvider: () async => documents,
      );

      final backup = await sourceService.createBackup(
        businessId: sourceBusinessId,
        includeTransferKey: true,
        transferPassword: 'mot-de-passe-solide',
      );
      final metadata = await sourceService.inspectBackup(backup.filePath);
      expect(metadata['version'], 3);

      await targetService.restoreBackup(
        backup.filePath,
        businessId: targetBusinessId,
        transferPassword: 'mot-de-passe-solide',
      );

      final restoredBusiness = await targetDb.getBusiness(targetBusinessId);
      final restoredProduct = await targetDb.getProduct('product-1');
      final restoredUsers = await (targetDb.select(
        targetDb.users,
      )..where((row) => row.businessId.equals(targetBusinessId))).get();
      final restoredSettings = await (targetDb.select(
        targetDb.appSettings,
      )..where((row) => row.businessId.equals(targetBusinessId))).get();
      final restoredInventories = await targetDb
          .select(targetDb.inventorySessions)
          .get();
      final restoredLines = await targetDb
          .select(targetDb.inventoryLines)
          .get();
      final restoredAttendance = await targetDb
          .select(targetDb.attendanceRecords)
          .get();

      expect(restoredBusiness?.name, 'Kumba Market');
      expect(restoredUsers.where((user) => user.isOwner), hasLength(1));
      expect(
        restoredUsers.singleWhere((user) => user.isOwner).id,
        targetOwnerId,
      );
      expect(restoredSettings.single.value, 'Merci et à bientôt');
      expect(restoredInventories.single.userId, targetOwnerId);
      expect(restoredLines.single.countedQty, 11);
      expect(restoredAttendance.single.userId, targetOwnerId);
      expect(restoredProduct?.stockQty, 12);
      expect(restoredProduct?.photoPath, isNot(media.path));
      expect(await File(restoredProduct!.photoPath!).readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
    },
  );

  test('backup authentication rejects a modified encrypted payload', () async {
    await _insertBusiness(
      sourceDb,
      businessId: 'business-source',
      ownerId: 'owner-source',
      name: 'Kumba Market',
    );
    await _insertBusiness(
      targetDb,
      businessId: 'business-target',
      ownerId: 'owner-target',
      name: 'Commerce vide',
    );
    final sourceService = BackupService(
      db: sourceDb,
      secure: secure,
      documentsDirectoryProvider: () async => documents,
    );
    final targetService = BackupService(
      db: targetDb,
      secure: secure,
      documentsDirectoryProvider: () async => documents,
    );
    final backup = await sourceService.createBackup(
      businessId: 'business-source',
      includeTransferKey: true,
      transferPassword: 'mot-de-passe-solide',
    );
    final file = File(backup.filePath);
    final envelope =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final encrypted = envelope['data'] as String;
    envelope['data'] =
        '${encrypted[0] == 'A' ? 'B' : 'A'}${encrypted.substring(1)}';
    await file.writeAsString(jsonEncode(envelope), flush: true);

    expect(
      () => targetService.restoreBackup(
        file.path,
        businessId: 'business-target',
        transferPassword: 'mot-de-passe-solide',
      ),
      throwsA(isA<BackupException>()),
    );
  });

  test('first-launch restore works without an activation code', () async {
    const sourceBusinessId = 'business-source';
    final now = DateTime.utc(2026, 7, 31);
    await _insertBusiness(
      sourceDb,
      businessId: sourceBusinessId,
      ownerId: 'owner-source',
      name: 'Marché restauré',
    );
    await sourceDb
        .into(sourceDb.products)
        .insert(
          ProductsCompanion.insert(
            id: 'product-restored',
            businessId: sourceBusinessId,
            name: 'Cacao',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final sourceService = BackupService(
      db: sourceDb,
      secure: secure,
      documentsDirectoryProvider: () async => documents,
    );
    final backup = await sourceService.createBackup(
      businessId: sourceBusinessId,
      includeTransferKey: true,
      transferPassword: 'mot-de-passe-solide',
    );
    final sync = SyncEngine(targetDb);
    addTearDown(sync.dispose);
    final targetBackupService = BackupService(
      db: targetDb,
      secure: secure,
      documentsDirectoryProvider: () async => documents,
    );
    final restore = RestoreOnboardingService(
      db: targetDb,
      secure: secure,
      businessService: BusinessService(
        db: targetDb,
        secure: secure,
        sync: sync,
      ),
      backupService: targetBackupService,
    );

    final restored = await restore.restoreFromFile(
      filePath: backup.filePath,
      password: 'mot-de-passe-solide',
      pin: '4321',
      ownerName: 'Nouvelle propriétaire',
    );

    expect(restored.name, 'Marché restauré');
    expect(await targetDb.getProduct('product-restored'), isA<Product>());
    expect(await secure.getCurrentBusinessId(), restored.id);
    expect(await secure.isOnboardingDone(), isTrue);
    expect(await secure.verifyPin('4321'), isTrue);
  });

  test('failed first-launch import rolls back the host business', () async {
    await _insertBusiness(
      sourceDb,
      businessId: 'business-source',
      ownerId: 'owner-source',
      name: 'Marché restauré',
    );
    final sourceService = BackupService(
      db: sourceDb,
      secure: secure,
      documentsDirectoryProvider: () async => documents,
    );
    final backup = await sourceService.createBackup(
      businessId: 'business-source',
      includeTransferKey: true,
      transferPassword: 'mot-de-passe-solide',
    );
    final sync = SyncEngine(targetDb);
    addTearDown(sync.dispose);
    final restore = RestoreOnboardingService(
      db: targetDb,
      secure: secure,
      businessService: BusinessService(
        db: targetDb,
        secure: secure,
        sync: sync,
      ),
      backupService: _FailingBackupService(
        db: targetDb,
        secure: secure,
        documentsDirectoryProvider: () async => documents,
      ),
    );

    expect(
      () => restore.restoreFromFile(
        filePath: backup.filePath,
        password: 'mot-de-passe-solide',
        pin: '4321',
      ),
      throwsA(isA<BackupException>()),
    );

    expect(await targetDb.select(targetDb.businesses).get(), isEmpty);
    expect(await targetDb.select(targetDb.users).get(), isEmpty);
    expect(await secure.getCurrentBusinessId(), equals(null));
    expect(await secure.isOnboardingDone(), isFalse);
  });

  test('automatic backups respect the interval and retention', () async {
    await _insertBusiness(
      sourceDb,
      businessId: 'business-source',
      ownerId: 'owner-source',
      name: 'Kumba Market',
    );
    final service = BackupService(
      db: sourceDb,
      secure: secure,
      documentsDirectoryProvider: () async => documents,
    );

    final first = await service.createAutomaticBackupIfDue(
      businessId: 'business-source',
      retentionCount: 2,
    );
    final skipped = await service.createAutomaticBackupIfDue(
      businessId: 'business-source',
      retentionCount: 2,
    );
    expect(first, isA<BackupRecord>());
    expect(skipped, equals(null));

    await service.createAutomaticBackupIfDue(
      businessId: 'business-source',
      interval: Duration.zero,
      retentionCount: 2,
    );
    await service.createAutomaticBackupIfDue(
      businessId: 'business-source',
      interval: Duration.zero,
      retentionCount: 2,
    );

    final automatic = (await service.list(
      'business-source',
    )).where((record) => record.type == 'auto').toList();
    expect(automatic, hasLength(2));
    for (final record in automatic) {
      expect(await File(record.filePath).exists(), isTrue);
    }
    final backupFiles = await Directory(
      '${documents.path}${Platform.pathSeparator}backups',
    ).list().where((entry) => entry is File).toList();
    expect(backupFiles, hasLength(2));
  });

  test('backup refuses an attachment larger than 15 MB', () async {
    const businessId = 'business-source';
    final now = DateTime.utc(2026, 7, 31);
    await _insertBusiness(
      sourceDb,
      businessId: businessId,
      ownerId: 'owner-source',
      name: 'Kumba Market',
    );
    final oversized = File(
      '${documents.path}${Platform.pathSeparator}oversized.jpg',
    );
    final writer = await oversized.open(mode: FileMode.write);
    await writer.setPosition(15 * 1024 * 1024);
    await writer.writeByte(0);
    await writer.close();
    await sourceDb
        .into(sourceDb.products)
        .insert(
          ProductsCompanion.insert(
            id: 'product-large-photo',
            businessId: businessId,
            name: 'Produit',
            photoPath: Value(oversized.path),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final service = BackupService(
      db: sourceDb,
      secure: secure,
      documentsDirectoryProvider: () async => documents,
    );

    expect(
      () => service.createBackup(businessId: businessId),
      throwsA(isA<BackupException>()),
    );
  });

  test(
    'backup v3 does not truncate businesses with more than 5000 sales',
    () async {
      const count = 5001;
      final now = DateTime.utc(2026, 7, 31, 12);
      await _insertBusiness(
        sourceDb,
        businessId: 'business-source',
        ownerId: 'owner-source',
        name: 'Grand commerce',
      );
      await _insertBusiness(
        targetDb,
        businessId: 'business-target',
        ownerId: 'owner-target',
        name: 'Commerce vide',
      );
      await sourceDb.batch((batch) {
        batch.insertAll(
          sourceDb.sales,
          List.generate(
            count,
            (index) => SalesCompanion.insert(
              id: 'sale-$index',
              businessId: 'business-source',
              reference: 'V-${index.toString().padLeft(6, '0')}',
              soldAt: now.add(Duration(seconds: index)),
              createdAt: now.add(Duration(seconds: index)),
              updatedAt: now.add(Duration(seconds: index)),
              idempotencyKey: 'sale-key-$index',
            ),
          ),
        );
      });
      final sourceService = BackupService(
        db: sourceDb,
        secure: secure,
        documentsDirectoryProvider: () async => documents,
      );
      final targetService = BackupService(
        db: targetDb,
        secure: secure,
        documentsDirectoryProvider: () async => documents,
      );
      final backup = await sourceService.createBackup(
        businessId: 'business-source',
        includeTransferKey: true,
        transferPassword: 'mot-de-passe-solide',
      );

      await targetService.restoreBackup(
        backup.filePath,
        businessId: 'business-target',
        transferPassword: 'mot-de-passe-solide',
      );

      final restoredSales = await (targetDb.select(
        targetDb.sales,
      )..where((row) => row.businessId.equals('business-target'))).get();
      expect(restoredSales, hasLength(count));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
