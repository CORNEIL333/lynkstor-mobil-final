import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/security/key_derivation.dart';
import '../../core/utils/id_generator.dart';
import '../../core/logging/app_logger.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Sauvegarde / restauration chiffrée réelle (fichier vérifiable).
class BackupService {
  BackupService({
    required this.db,
    required this.secure,
    Future<Directory> Function()? documentsDirectoryProvider,
  }) : _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final AppDatabase db;
  final SecureStorageService secure;
  final Future<Directory> Function() _documentsDirectoryProvider;

  Future<enc.Key> _getOrCreateKey() async {
    var stored = await secure.getBackupKey();
    if (stored == null) {
      final key = enc.Key.fromSecureRandom(32);
      stored = base64Encode(key.bytes);
      await secure.setBackupKey(stored);
    }
    return enc.Key(base64Decode(stored));
  }

  Future<BackupRecord> createBackup({
    required String businessId,
    String type = 'manual',
    bool includeTransferKey = false,
    String? transferPassword,
  }) async {
    final business = await db.getBusiness(businessId);
    if (business == null) {
      throw const NotFoundException('Commerce introuvable.');
    }

    final payload = await _exportData(businessId);
    final jsonStr = jsonEncode(payload);
    if (includeTransferKey &&
        (transferPassword == null || transferPassword.length < 8)) {
      throw const BackupException(
        'Le mot de passe de transfert doit contenir au moins 8 caractères.',
      );
    }
    final salt = includeTransferKey
        ? List<int>.generate(16, (_) => Random.secure().nextInt(256))
        : <int>[];
    final key = includeTransferKey
        ? enc.Key(derivePbkdf2Sha256(password: transferPassword!, salt: salt))
        : await _getOrCreateKey();
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key));
    final encrypted = encrypter.encrypt(jsonStr, iv: iv);

    final dir = await _documentsDirectoryProvider();
    final backupDir = Directory(p.join(dir.path, 'backups'));
    if (!await backupDir.exists()) await backupDir.create(recursive: true);

    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final prefix = includeTransferKey ? 'kumba_transfer' : 'kumba_backup';
    final fileName =
        '${prefix}_${business.name.replaceAll(RegExp(r'[^\w]'), '_')}_$stamp.kumba';
    final filePath = p.join(backupDir.path, fileName);

    final createdAt = DateTime.now().toIso8601String();
    final envelope = <String, dynamic>{
      'version': 3,
      'app': 'KUMBA Business',
      'businessId': businessId,
      'businessName': business.name,
      'createdAt': createdAt,
      'iv': base64Encode(iv.bytes),
      'data': encrypted.base64,
      'type': includeTransferKey ? 'transfer' : type,
      if (includeTransferKey) ...{
        'kdf': 'pbkdf2-sha256',
        'iterations': 120000,
        'salt': base64Encode(salt),
      },
    };
    envelope['mac'] = _macFor(envelope, key);
    final fileContent = jsonEncode(envelope);

    final file = File(filePath);
    await file.writeAsString(fileContent);
    final bytes = await file.readAsBytes();
    final checksum = sha256.convert(bytes).toString();

    // Vérification immédiate
    if (!await file.exists() || bytes.isEmpty) {
      throw const BackupException(
        'La sauvegarde a échoué : fichier introuvable après écriture.',
      );
    }

    final id = IdGenerator.uuid();
    await db
        .into(db.backupRecords)
        .insert(
          BackupRecordsCompanion.insert(
            id: id,
            businessId: businessId,
            filePath: filePath,
            fileName: fileName,
            sizeBytes: Value(bytes.length),
            checksum: checksum,
            type: Value(type),
            destination: const Value('local'),
            isEncrypted: const Value(true),
            createdAt: DateTime.now(),
            status: const Value('success'),
          ),
        );

    await db.insertAudit(
      AuditLogsCompanion.insert(
        id: IdGenerator.uuid(),
        businessId: businessId,
        action: 'backup.created',
        entityType: const Value('backup'),
        entityId: Value(id),
        detailsJson: Value(
          jsonEncode({
            'file': fileName,
            'checksum': checksum,
            'size': bytes.length,
          }),
        ),
        createdAt: DateTime.now(),
      ),
    );

    AppLogger.audit(
      'backup.created',
      entityId: id,
      meta: {'checksum': checksum},
    );
    return (await (db.select(
      db.backupRecords,
    )..where((t) => t.id.equals(id))).getSingle());
  }

  Future<Map<String, dynamic>> inspectBackup(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const BackupException('Fichier de sauvegarde introuvable.');
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return {
      'version': raw['version'],
      'businessName': raw['businessName'],
      'businessId': raw['businessId'],
      'createdAt': raw['createdAt'],
      'size': await file.length(),
      'checksum': sha256.convert(await file.readAsBytes()).toString(),
      'type': raw['type'],
      'passwordProtected': raw['kdf'] == 'pbkdf2-sha256',
    };
  }

  Future<void> restoreBackup(
    String filePath, {
    required String businessId,
    String? transferPassword,
  }) async {
    final meta = await inspectBackup(filePath);
    final file = File(filePath);
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    final key = await _keyForEnvelope(raw, transferPassword: transferPassword);
    _verifyMac(raw, key);
    final iv = enc.IV(base64Decode(raw['iv'] as String));
    final encrypter = enc.Encrypter(enc.AES(key));
    final decrypted = encrypter.decrypt64(raw['data'] as String, iv: iv);
    final payload = jsonDecode(decrypted) as Map<String, dynamic>;

    await _validateInTemporaryDatabase(businessId, payload);

    // Sauvegarde de sécurité avant restauration
    await createBackup(businessId: businessId, type: 'pre_restore');

    // Restauration ciblée des entités principales
    await db.transaction(() async {
      await _deleteBusinessData(businessId);
      await importPayload(businessId, payload);
    });

    await db.insertAudit(
      AuditLogsCompanion.insert(
        id: IdGenerator.uuid(),
        businessId: businessId,
        action: 'backup.restored',
        entityType: const Value('backup'),
        detailsJson: Value(jsonEncode(meta)),
        createdAt: DateTime.now(),
      ),
    );

    AppLogger.audit('backup.restored', entityId: businessId);
  }

  Future<void> _validateInTemporaryDatabase(
    String businessId,
    Map<String, dynamic> payload,
  ) async {
    final root = await _documentsDirectoryProvider();
    final directory = Directory(
      p.join(root.path, 'restore_validation', IdGenerator.uuid()),
    );
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'validation.db'));
    final key = base64UrlEncode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final escapedKey = key.replaceAll("'", "''");
    final temporaryDb = AppDatabase(
      NativeDatabase(
        file,
        setup: (rawDb) {
          rawDb.execute("PRAGMA key = '$escapedKey';");
          rawDb.execute('PRAGMA foreign_keys = ON;');
        },
      ),
    );
    try {
      final temporaryService = BackupService(
        db: temporaryDb,
        secure: secure,
        documentsDirectoryProvider: () async => directory,
      );
      await temporaryService.importPayload(businessId, payload);
      final integrity = await temporaryDb
          .customSelect('PRAGMA integrity_check;')
          .get();
      if (integrity.length != 1 ||
          integrity.first.data.values.first.toString().toLowerCase() != 'ok') {
        throw const BackupException(
          'La base temporaire restaurée échoue au contrôle d’intégrité.',
        );
      }
      final foreignKeys = await temporaryDb
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      if (foreignKeys.isNotEmpty) {
        throw const BackupException(
          'La sauvegarde contient des relations de données invalides.',
        );
      }
      await _verifyManifestCounts(temporaryDb, payload);
    } finally {
      await temporaryDb.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  Future<void> _verifyManifestCounts(
    AppDatabase target,
    Map<String, dynamic> payload,
  ) async {
    final manifest = payload['manifest'];
    if (manifest is! Map) {
      throw const BackupException('Manifeste de sauvegarde absent.');
    }
    const tables = <String, String>{
      'users': 'users',
      'appSettings': 'app_settings',
      'categories': 'categories',
      'products': 'products',
      'stockMovements': 'stock_movements',
      'inventorySessions': 'inventory_sessions',
      'inventoryLines': 'inventory_lines',
      'customers': 'customers',
      'sales': 'sales',
      'saleItems': 'sale_items',
      'payments': 'payments',
      'debtMovements': 'debt_movements',
      'saleReturns': 'sale_returns',
      'saleReturnItems': 'sale_return_items',
      'expenseCategories': 'expense_categories',
      'expenses': 'expenses',
      'suppliers': 'suppliers',
      'purchases': 'purchases',
      'purchaseItems': 'purchase_items',
      'quotes': 'quotes',
      'quoteItems': 'quote_items',
      'invoices': 'invoices',
      'invoiceItems': 'invoice_items',
      'deliveries': 'deliveries',
      'attendanceRecords': 'attendance_records',
      'notifications': 'app_notifications',
      'automationRules': 'automation_rules',
      'automationRuns': 'automation_runs',
      'supplierProducts': 'supplier_products',
    };
    for (final entry in tables.entries) {
      final expected = (manifest[entry.key] as num?)?.toInt();
      if (expected == null) continue;
      final count = await target
          .customSelect('SELECT COUNT(*) AS amount FROM ${entry.value};')
          .getSingle();
      final actual = count.read<int>('amount');
      if (actual != expected) {
        throw BackupException(
          'Validation incomplète pour ${entry.key} ($actual/$expected).',
        );
      }
    }
  }

  Future<void> _deleteBusinessData(String businessId) async {
    Future<void> execute(String sql) => db.customStatement(sql, [businessId]);
    await execute(
      'DELETE FROM inventory_lines WHERE session_id IN '
      '(SELECT id FROM inventory_sessions WHERE business_id = ?)',
    );
    await execute(
      'DELETE FROM invoice_items WHERE invoice_id IN '
      '(SELECT id FROM invoices WHERE business_id = ?)',
    );
    await execute(
      'DELETE FROM quote_items WHERE quote_id IN '
      '(SELECT id FROM quotes WHERE business_id = ?)',
    );
    await execute(
      'DELETE FROM purchase_items WHERE purchase_id IN '
      '(SELECT id FROM purchases WHERE business_id = ?)',
    );
    await execute(
      'DELETE FROM sale_return_items WHERE return_id IN '
      '(SELECT id FROM sale_returns WHERE business_id = ?)',
    );
    await execute(
      'DELETE FROM sale_items WHERE sale_id IN '
      '(SELECT id FROM sales WHERE business_id = ?)',
    );
    await (db.delete(
      db.supplierProducts,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.automationRuns,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.automationRules,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.appNotifications,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.attendanceRecords,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.deliveries,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.invoices,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.quotes,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.purchases,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.expenses,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.expenseCategories,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.saleReturns,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.debtMovements,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.payments,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.sales,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.inventorySessions,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.stockMovements,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.suppliers,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.customers,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.products,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.categories,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(db.users)..where(
          (row) =>
              row.businessId.equals(businessId) & row.isOwner.equals(false),
        ))
        .go();
    await (db.delete(
      db.appSettings,
    )..where((row) => row.businessId.equals(businessId))).go();
    await (db.delete(
      db.syncQueue,
    )..where((row) => row.businessId.equals(businessId))).go();
  }

  Future<List<BackupRecord>> list(String businessId) =>
      (db.select(db.backupRecords)
            ..where((t) => t.businessId.equals(businessId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<BackupRecord?> createAutomaticBackupIfDue({
    required String businessId,
    Duration interval = const Duration(hours: 24),
    int retentionCount = 7,
  }) async {
    final latest =
        await (db.select(db.backupRecords)
              ..where(
                (row) =>
                    row.businessId.equals(businessId) &
                    row.type.equals('auto') &
                    row.status.equals('success'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (latest != null &&
        DateTime.now().difference(latest.createdAt) < interval) {
      return null;
    }
    final created = await createBackup(businessId: businessId, type: 'auto');
    await _pruneAutomaticBackups(
      businessId,
      retentionCount: retentionCount.clamp(1, 30),
    );
    return created;
  }

  Future<void> _pruneAutomaticBackups(
    String businessId, {
    required int retentionCount,
  }) async {
    final records =
        await (db.select(db.backupRecords)
              ..where(
                (row) =>
                    row.businessId.equals(businessId) & row.type.equals('auto'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    if (records.length <= retentionCount) return;
    final documents = await _documentsDirectoryProvider();
    final backupRoot = p.normalize(p.join(documents.path, 'backups'));
    for (final record in records.skip(retentionCount)) {
      final path = p.normalize(record.filePath);
      if (p.isWithin(backupRoot, path)) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      await (db.delete(
        db.backupRecords,
      )..where((row) => row.id.equals(record.id))).go();
    }
  }

  Future<enc.Key> _keyForEnvelope(
    Map<String, dynamic> envelope, {
    String? transferPassword,
  }) async {
    if (envelope['kdf'] == 'pbkdf2-sha256') {
      if (transferPassword == null || transferPassword.isEmpty) {
        throw const BackupException(
          'Le mot de passe de transfert est obligatoire.',
        );
      }
      final saltRaw = envelope['salt'];
      if (saltRaw is! String) {
        throw const BackupException('Sel de sauvegarde invalide.');
      }
      final iterations = (envelope['iterations'] as num?)?.toInt() ?? 120000;
      return enc.Key(
        derivePbkdf2Sha256(
          password: transferPassword,
          salt: base64Decode(saltRaw),
          iterations: iterations,
        ),
      );
    }
    if (envelope['transferKey'] is String) {
      return enc.Key(base64Decode(envelope['transferKey'] as String));
    }
    return _getOrCreateKey();
  }

  void _verifyMac(Map<String, dynamic> envelope, enc.Key key) {
    if ((envelope['version'] as num?)?.toInt() == 1) return;
    final encodedMac = envelope['mac'];
    if (encodedMac is! String) {
      throw const BackupException(
        'Sauvegarde non authentifiée ou format incomplet.',
      );
    }
    final expected = base64Decode(encodedMac);
    final actual = Hmac(
      sha256,
      key.bytes,
    ).convert(utf8.encode(_authenticatedFields(envelope))).bytes;
    if (!constantTimeBytesEqual(expected, actual)) {
      throw const BackupException(
        'Sauvegarde altérée ou mot de passe incorrect.',
      );
    }
  }

  String _macFor(Map<String, dynamic> envelope, enc.Key key) => base64Encode(
    Hmac(
      sha256,
      key.bytes,
    ).convert(utf8.encode(_authenticatedFields(envelope))).bytes,
  );

  String _authenticatedFields(Map<String, dynamic> envelope) => jsonEncode([
    envelope['version'],
    envelope['businessId'],
    envelope['createdAt'],
    envelope['iv'],
    envelope['data'],
    envelope['type'],
    envelope['kdf'],
    envelope['iterations'],
    envelope['salt'],
  ]);

  Future<Map<String, dynamic>> _exportData(String businessId) async {
    final business = await db.getBusiness(businessId);
    if (business == null) {
      throw const NotFoundException('Commerce introuvable.');
    }
    final users = await (db.select(
      db.users,
    )..where((t) => t.businessId.equals(businessId))).get();
    final settings = await (db.select(
      db.appSettings,
    )..where((t) => t.businessId.equals(businessId))).get();
    final categories = await (db.select(
      db.categories,
    )..where((t) => t.businessId.equals(businessId))).get();
    final products = await db.getProducts(businessId);
    final productIds = products.map((row) => row.id).toSet();
    final stockMovements = (await db.select(db.stockMovements).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final customers = await db.getCustomers(businessId);
    final sales =
        await (db.select(db.sales)
              ..where((t) => t.businessId.equals(businessId))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    final saleIds = sales.map((row) => row.id).toSet();
    final saleItems = (await db.select(db.saleItems).get())
        .where((row) => saleIds.contains(row.saleId))
        .toList();
    final payments = (await db.select(db.payments).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final debtMovements = (await db.select(db.debtMovements).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final returns = (await db.select(db.saleReturns).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final returnIds = returns.map((row) => row.id).toSet();
    final returnItems = (await db.select(db.saleReturnItems).get())
        .where((row) => returnIds.contains(row.returnId))
        .toList();
    final expenseCategories = (await db.select(db.expenseCategories).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final expenses = await db.getExpenses(businessId);
    final suppliers = await db.getSuppliers(businessId);
    final purchases = (await db.select(db.purchases).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final purchaseIds = purchases.map((row) => row.id).toSet();
    final purchaseItems = (await db.select(db.purchaseItems).get())
        .where((row) => purchaseIds.contains(row.purchaseId))
        .toList();
    final quotes = (await db.select(db.quotes).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final quoteIds = quotes.map((row) => row.id).toSet();
    final quoteItems = (await db.select(db.quoteItems).get())
        .where((row) => quoteIds.contains(row.quoteId))
        .toList();
    final invoices = (await db.select(db.invoices).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final invoiceIds = invoices.map((row) => row.id).toSet();
    final invoiceItems = (await db.select(db.invoiceItems).get())
        .where((row) => invoiceIds.contains(row.invoiceId))
        .toList();
    final deliveries = (await db.select(db.deliveries).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final notifications = (await db.select(db.appNotifications).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final automationRules = (await db.select(db.automationRules).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final automationRuns = (await db.select(db.automationRuns).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final supplierProducts = (await db.select(db.supplierProducts).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final inventorySessions = (await db.select(db.inventorySessions).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final inventorySessionIds = inventorySessions.map((row) => row.id).toSet();
    final inventoryLines = (await db.select(db.inventoryLines).get())
        .where((row) => inventorySessionIds.contains(row.sessionId))
        .toList();
    final attendanceRecords = (await db.select(db.attendanceRecords).get())
        .where((row) => row.businessId == businessId)
        .toList();
    final exportedAttachments = await _exportAttachments([
      business.logoPath,
      business.coverPath,
      ...users.map((row) => row.photoPath),
      ...products.map((row) => row.photoPath),
      ...customers.map((row) => row.photoPath),
      ...expenses.map((row) => row.photoPath),
      ...purchases.map((row) => row.invoicePhotoPath),
      ...deliveries.expand((row) => [row.photoPath, row.signaturePath]),
      ...inventoryLines.map((row) => row.photoPath),
      ...attendanceRecords.map((row) => row.photoPath),
    ]);
    final attachments = exportedAttachments.files;

    final data = <String, dynamic>{
      'format': 3,
      'schemaVersion': db.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'business': business.toJson(),
      'users': users.map((row) => row.toJson()).toList(),
      'appSettings': settings.map((row) => row.toJson()).toList(),
      'categories': categories.map((row) => row.toJson()).toList(),
      'products': products.map((row) => row.toJson()).toList(),
      'stockMovements': stockMovements
          .where((row) => productIds.contains(row.productId))
          .map((row) => row.toJson())
          .toList(),
      'customers': customers.map((row) => row.toJson()).toList(),
      'sales': sales.map((row) => row.toJson()).toList(),
      'saleItems': saleItems.map((row) => row.toJson()).toList(),
      'payments': payments.map((row) => row.toJson()).toList(),
      'debtMovements': debtMovements.map((row) => row.toJson()).toList(),
      'saleReturns': returns.map((row) => row.toJson()).toList(),
      'saleReturnItems': returnItems.map((row) => row.toJson()).toList(),
      'expenseCategories': expenseCategories
          .map((row) => row.toJson())
          .toList(),
      'expenses': expenses.map((row) => row.toJson()).toList(),
      'suppliers': suppliers.map((row) => row.toJson()).toList(),
      'purchases': purchases.map((row) => row.toJson()).toList(),
      'purchaseItems': purchaseItems.map((row) => row.toJson()).toList(),
      'quotes': quotes.map((row) => row.toJson()).toList(),
      'quoteItems': quoteItems.map((row) => row.toJson()).toList(),
      'invoices': invoices.map((row) => row.toJson()).toList(),
      'invoiceItems': invoiceItems.map((row) => row.toJson()).toList(),
      'deliveries': deliveries.map((row) => row.toJson()).toList(),
      'notifications': notifications.map((row) => row.toJson()).toList(),
      'automationRules': automationRules.map((row) => row.toJson()).toList(),
      'automationRuns': automationRuns.map((row) => row.toJson()).toList(),
      'supplierProducts': supplierProducts.map((row) => row.toJson()).toList(),
      'inventorySessions': inventorySessions
          .map((row) => row.toJson())
          .toList(),
      'inventoryLines': inventoryLines.map((row) => row.toJson()).toList(),
      'attendanceRecords': attendanceRecords
          .map((row) => row.toJson())
          .toList(),
      'attachments': attachments,
      'attachmentWarnings': exportedAttachments.warnings,
      'excludedTables': const [
        'devices',
        'auditLogs',
        'syncQueue',
        'backupRecords',
      ],
    };
    data['manifest'] = {
      for (final entry in data.entries)
        if (entry.value is List) entry.key: (entry.value as List).length,
      'attachments': attachments.length,
    };
    return data;
  }

  Future<void> importPayload(
    String businessId,
    Map<String, dynamic> payload,
  ) async {
    if ((payload['format'] as num?)?.toInt() case 2 || 3) {
      await _importCompleteData(businessId, payload);
      return;
    }
    // Import non destructif des produits manquants (évite double comptage stock).
    final products = (payload['products'] as List?) ?? [];
    for (final raw in products) {
      final m = raw as Map<String, dynamic>;
      final existing = await db.getProduct(m['id'] as String);
      if (existing != null) continue;
      final now = DateTime.now();
      await db.insertProduct(
        ProductsCompanion.insert(
          id: m['id'] as String,
          businessId: businessId,
          name: m['name'] as String,
          salePrice: Value((m['salePrice'] as num).toDouble()),
          costPrice: Value((m['costPrice'] as num?)?.toDouble() ?? 0),
          stockQty: Value((m['stockQty'] as num?)?.toDouble() ?? 0),
          barcode: Value(m['barcode'] as String?),
          unit: Value(m['unit'] as String? ?? 'pièce'),
          trackStock: Value(m['trackStock'] as bool? ?? true),
          isService: Value(m['isService'] as bool? ?? false),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    final customers = (payload['customers'] as List?) ?? [];
    for (final raw in customers) {
      final m = raw as Map<String, dynamic>;
      final existing = await db.getCustomer(m['id'] as String);
      if (existing != null) continue;
      final now = DateTime.now();
      await db.insertCustomer(
        CustomersCompanion.insert(
          id: m['id'] as String,
          businessId: businessId,
          name: m['name'] as String,
          phone: Value(m['phone'] as String?),
          balance: Value((m['balance'] as num?)?.toDouble() ?? 0),
          creditLimit: Value((m['creditLimit'] as num?)?.toDouble() ?? 0),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  Future<void> _importCompleteData(
    String businessId,
    Map<String, dynamic> payload,
  ) async {
    List<Map<String, dynamic>> rows(String key) =>
        ((payload[key] as List?) ?? const [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
    final restoredAttachments = await _restoreAttachments(businessId, payload);
    final restoredPaths = restoredAttachments.paths;
    void remap(Map<String, dynamic> value, String field) {
      final oldPath = value[field];
      if (oldPath is String && restoredPaths.containsKey(oldPath)) {
        value[field] = restoredPaths[oldPath];
      }
    }

    try {
      await db.transaction(() async {
        final targetUsers = await (db.select(
          db.users,
        )..where((t) => t.businessId.equals(businessId))).get();
        final targetOwner = targetUsers
            .where((user) => user.isOwner)
            .firstOrNull;
        final sourceUsers = rows('users');
        final sourceOwner = sourceUsers
            .where((user) => user['isOwner'] == true)
            .firstOrNull;
        final ownerIdMap = <String, String>{};
        if (targetOwner != null && sourceOwner?['id'] is String) {
          ownerIdMap[sourceOwner!['id'] as String] = targetOwner.id;
        }
        void remapUser(Map<String, dynamic> value) {
          final oldUserId = value['userId'];
          if (oldUserId is String && ownerIdMap.containsKey(oldUserId)) {
            value['userId'] = ownerIdMap[oldUserId];
          }
        }

        final businessValue = payload['business'];
        if (businessValue is Map) {
          final value = Map<String, dynamic>.from(businessValue);
          remap(value, 'logoPath');
          remap(value, 'coverPath');
          final row = Business.fromJson(value).copyWith(id: businessId);
          await db.into(db.businesses).insertOnConflictUpdate(row);
        }
        for (final value in sourceUsers) {
          remap(value, 'photoPath');
          final sourceId = value['id'];
          if (sourceId is String && ownerIdMap.containsKey(sourceId)) {
            value['id'] = ownerIdMap[sourceId];
          }
          final row = User.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.users).insertOnConflictUpdate(row);
        }
        for (final value in rows('appSettings')) {
          final row = AppSetting.fromJson(
            value,
          ).copyWith(businessId: Value(businessId));
          await db.into(db.appSettings).insertOnConflictUpdate(row);
        }
        for (final value in rows('categories')) {
          final row = Category.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.categories).insertOnConflictUpdate(row);
        }
        for (final value in rows('products')) {
          remap(value, 'photoPath');
          final row = Product.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.products).insertOnConflictUpdate(row);
        }
        for (final value in rows('stockMovements')) {
          remapUser(value);
          final row = StockMovement.fromJson(
            value,
          ).copyWith(businessId: businessId);
          await db.into(db.stockMovements).insertOnConflictUpdate(row);
        }
        for (final value in rows('inventorySessions')) {
          remapUser(value);
          final row = InventorySession.fromJson(
            value,
          ).copyWith(businessId: businessId);
          await db.into(db.inventorySessions).insertOnConflictUpdate(row);
        }
        for (final value in rows('inventoryLines')) {
          remap(value, 'photoPath');
          await db
              .into(db.inventoryLines)
              .insertOnConflictUpdate(InventoryLine.fromJson(value));
        }
        for (final value in rows('customers')) {
          remap(value, 'photoPath');
          final row = Customer.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.customers).insertOnConflictUpdate(row);
        }
        for (final value in rows('sales')) {
          remapUser(value);
          final row = Sale.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.sales).insertOnConflictUpdate(row);
        }
        for (final value in rows('saleItems')) {
          await db
              .into(db.saleItems)
              .insertOnConflictUpdate(SaleItem.fromJson(value));
        }
        for (final value in rows('payments')) {
          remapUser(value);
          final row = Payment.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.payments).insertOnConflictUpdate(row);
        }
        for (final value in rows('debtMovements')) {
          remapUser(value);
          final row = DebtMovement.fromJson(
            value,
          ).copyWith(businessId: businessId);
          await db.into(db.debtMovements).insertOnConflictUpdate(row);
        }
        for (final value in rows('saleReturns')) {
          remapUser(value);
          final row = SaleReturn.fromJson(
            value,
          ).copyWith(businessId: businessId);
          await db.into(db.saleReturns).insertOnConflictUpdate(row);
        }
        for (final value in rows('saleReturnItems')) {
          await db
              .into(db.saleReturnItems)
              .insertOnConflictUpdate(SaleReturnItem.fromJson(value));
        }
        for (final value in rows('expenseCategories')) {
          final row = ExpenseCategory.fromJson(
            value,
          ).copyWith(businessId: businessId);
          await db.into(db.expenseCategories).insertOnConflictUpdate(row);
        }
        for (final value in rows('expenses')) {
          remap(value, 'photoPath');
          remapUser(value);
          final row = Expense.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.expenses).insertOnConflictUpdate(row);
        }
        for (final value in rows('suppliers')) {
          final row = Supplier.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.suppliers).insertOnConflictUpdate(row);
        }
        for (final value in rows('purchases')) {
          remap(value, 'invoicePhotoPath');
          remapUser(value);
          final row = Purchase.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.purchases).insertOnConflictUpdate(row);
        }
        for (final value in rows('purchaseItems')) {
          await db
              .into(db.purchaseItems)
              .insertOnConflictUpdate(PurchaseItem.fromJson(value));
        }
        for (final value in rows('quotes')) {
          remapUser(value);
          final row = Quote.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.quotes).insertOnConflictUpdate(row);
        }
        for (final value in rows('quoteItems')) {
          await db
              .into(db.quoteItems)
              .insertOnConflictUpdate(QuoteItem.fromJson(value));
        }
        for (final value in rows('invoices')) {
          remapUser(value);
          final row = Invoice.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.invoices).insertOnConflictUpdate(row);
        }
        for (final value in rows('invoiceItems')) {
          await db
              .into(db.invoiceItems)
              .insertOnConflictUpdate(InvoiceItem.fromJson(value));
        }
        for (final value in rows('deliveries')) {
          remap(value, 'photoPath');
          remap(value, 'signaturePath');
          remapUser(value);
          final row = Delivery.fromJson(value).copyWith(businessId: businessId);
          await db.into(db.deliveries).insertOnConflictUpdate(row);
        }
        for (final value in rows('attendanceRecords')) {
          remap(value, 'photoPath');
          remapUser(value);
          final row = AttendanceRecord.fromJson(
            value,
          ).copyWith(businessId: businessId);
          await db.into(db.attendanceRecords).insertOnConflictUpdate(row);
        }
        for (final value in rows('notifications')) {
          final row = AppNotification.fromJson(
            value,
          ).copyWith(businessId: businessId);
          await db.into(db.appNotifications).insertOnConflictUpdate(row);
        }
        for (final value in rows('automationRules')) {
          final row = AutomationRule.fromJson(
            value,
          ).copyWith(businessId: businessId);
          await db.into(db.automationRules).insertOnConflictUpdate(row);
        }
        for (final value in rows('automationRuns')) {
          final row = AutomationRun.fromJson(
            value,
          ).copyWith(businessId: businessId);
          await db.into(db.automationRuns).insertOnConflictUpdate(row);
        }
        for (final value in rows('supplierProducts')) {
          final row = SupplierProduct.fromJson(
            value,
          ).copyWith(businessId: businessId);
          await db.into(db.supplierProducts).insertOnConflictUpdate(row);
        }
      });
    } catch (_) {
      final directory = restoredAttachments.directory;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<_ExportedAttachments> _exportAttachments(
    Iterable<String?> paths,
  ) async {
    final documents = await _documentsDirectoryProvider();
    final root = p.normalize(documents.path);
    final result = <String, dynamic>{};
    final warnings = <String>[];
    for (final rawPath in paths.whereType<String>().toSet()) {
      final normalized = p.normalize(rawPath);
      if (!p.isWithin(root, normalized)) {
        warnings.add('outside_documents:$rawPath');
        continue;
      }
      final file = File(normalized);
      if (!await file.exists()) {
        warnings.add('missing:$rawPath');
        continue;
      }
      final length = await file.length();
      if (length <= 0) {
        warnings.add('empty:$rawPath');
        continue;
      }
      if (length > 15 * 1024 * 1024) {
        throw BackupException(
          'La pièce jointe « ${p.basename(rawPath)} » dépasse la limite de 15 Mo.',
        );
      }
      final bytes = await file.readAsBytes();
      result[rawPath] = {
        'extension': _safeMediaExtension(p.extension(normalized)),
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'data': base64Encode(bytes),
      };
    }
    return _ExportedAttachments(files: result, warnings: warnings);
  }

  Future<_RestoredAttachments> _restoreAttachments(
    String businessId,
    Map<String, dynamic> payload,
  ) async {
    final rawAttachments = payload['attachments'];
    if (rawAttachments is! Map) {
      return const _RestoredAttachments(paths: {}, directory: null);
    }
    final documents = await _documentsDirectoryProvider();
    final directory = Directory(
      p.join(documents.path, 'restored_media', businessId, IdGenerator.uuid()),
    );
    await directory.create(recursive: true);
    final result = <String, String>{};

    for (final entry in rawAttachments.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      final metadata = Map<String, dynamic>.from(entry.value as Map);
      final encoded = metadata['data'];
      if (encoded is! String) continue;
      try {
        final bytes = base64Decode(encoded);
        if (bytes.isEmpty || bytes.length > 15 * 1024 * 1024) continue;
        final declaredSize = (metadata['size'] as num?)?.toInt();
        final declaredHash = metadata['sha256'];
        if ((declaredSize != null && declaredSize != bytes.length) ||
            (declaredHash is String &&
                declaredHash != sha256.convert(bytes).toString())) {
          throw const BackupException(
            'Une pièce jointe de la sauvegarde est altérée.',
          );
        }
        final extension = _safeMediaExtension(
          metadata['extension'] as String? ?? '',
        );
        final file = File(
          p.join(directory.path, '${IdGenerator.uuid()}$extension'),
        );
        await file.writeAsBytes(bytes, flush: true);
        result[entry.key as String] = file.path;
      } on FormatException {
        throw const BackupException(
          'Une pièce jointe de la sauvegarde est corrompue.',
        );
      }
    }
    return _RestoredAttachments(paths: result, directory: directory);
  }

  String _safeMediaExtension(String extension) {
    final normalized = extension.toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp', '.pdf'}.contains(normalized)
        ? normalized
        : '.bin';
  }
}

class _RestoredAttachments {
  const _RestoredAttachments({required this.paths, required this.directory});

  final Map<String, String> paths;
  final Directory? directory;
}

class _ExportedAttachments {
  const _ExportedAttachments({required this.files, required this.warnings});

  final Map<String, dynamic> files;
  final List<String> warnings;
}
