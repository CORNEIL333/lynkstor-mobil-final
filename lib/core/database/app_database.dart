import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../security/secure_storage_service.dart';
import '../utils/id_generator.dart';
import 'tables/automation_tables.dart';
import 'tables/catalog_tables.dart';
import 'tables/core_tables.dart';
import 'tables/ops_tables.dart';
import 'tables/sales_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Businesses,
    Users,
    Devices,
    AuditLogs,
    SyncQueue,
    AppSettings,
    Categories,
    Products,
    StockMovements,
    InventorySessions,
    InventoryLines,
    Customers,
    Sales,
    SaleItems,
    Payments,
    DebtMovements,
    SaleReturns,
    SaleReturnItems,
    ExpenseCategories,
    Expenses,
    Suppliers,
    Purchases,
    PurchaseItems,
    Quotes,
    QuoteItems,
    Invoices,
    InvoiceItems,
    Deliveries,
    AttendanceRecords,
    BackupRecords,
    AppNotifications,
    AutomationRules,
    AutomationRuns,
    SupplierProducts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('PRAGMA foreign_keys = ON');
      await _ensureAnalyticsTable();
      await _ensureBillingSchema();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _ensureV2Tables(m);
      }
      if (from < 3) {
        await _ensureAnalyticsTable();
      }
      if (from < 4) {
        await _ensureBillingSchema();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Répare aussi les installations qui ont été interrompues après avoir
      // créé seulement une partie des tables v2.
      if (details.versionNow >= 2) {
        await _ensureV2Tables(createMigrator());
      }
      if (details.versionNow >= 3) {
        await _ensureAnalyticsTable();
      }
      if (details.versionNow >= 4) {
        await _ensureBillingSchema();
      }
    },
  );

  Future<bool> _tableExists(String tableName) async {
    final rows = await customSelect(
      'SELECT 1 FROM sqlite_master '
      'WHERE type = ? AND name = ? LIMIT 1',
      variables: [const Variable<String>('table'), Variable(tableName)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<void> _ensureV2Tables(Migrator migrator) async {
    if (!await _tableExists('app_notifications')) {
      await migrator.createTable(appNotifications);
    }
    if (!await _tableExists('automation_rules')) {
      await migrator.createTable(automationRules);
    }
    if (!await _tableExists('automation_runs')) {
      await migrator.createTable(automationRuns);
    }
    if (!await _tableExists('supplier_products')) {
      await migrator.createTable(supplierProducts);
    }
  }

  Future<void> _ensureAnalyticsTable() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS analytics_events (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  properties_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0
)
''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_analytics_events_synced '
      'ON analytics_events (synced, created_at)',
    );
  }

  Future<void> insertAnalyticsEvent({
    required String id,
    required String name,
    required String propertiesJson,
    required DateTime createdAt,
  }) {
    return customStatement(
      'INSERT OR IGNORE INTO analytics_events '
      '(id, name, properties_json, created_at, synced) VALUES (?, ?, ?, ?, 0)',
      [id, name, propertiesJson, createdAt.millisecondsSinceEpoch],
    );
  }

  Future<List<Map<String, dynamic>>> pendingAnalyticsEvents({
    int limit = 120,
  }) async {
    final rows = await customSelect(
      'SELECT id, name, properties_json, created_at FROM analytics_events '
      'WHERE synced = 0 ORDER BY created_at ASC LIMIT ?',
      variables: [Variable<int>(limit)],
    ).get();
    return [
      for (final row in rows)
        {
          'id': row.read<String>('id'),
          'name': row.read<String>('name'),
          'propertiesJson': row.read<String>('properties_json'),
          'createdAt': DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('created_at'),
          ),
        },
    ];
  }

  Future<void> markAnalyticsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await customStatement(
      'UPDATE analytics_events SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<int> analyticsPendingCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM analytics_events WHERE synced = 0',
    ).getSingle();
    return row.read<int>('c');
  }

  Future<int> analyticsTotalCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM analytics_events',
    ).getSingle();
    return row.read<int>('c');
  }

  Future<int> analyticsOpenDays() async {
    final row = await customSelect(
      "SELECT COUNT(DISTINCT date(created_at / 1000, 'unixepoch', 'localtime')) "
      "AS c FROM analytics_events WHERE name = 'app.opened'",
    ).getSingle();
    return row.read<int>('c');
  }

  Future<List<Map<String, dynamic>>> analyticsEventCounts() async {
    final rows = await customSelect(
      'SELECT name, COUNT(*) AS c FROM analytics_events '
      'GROUP BY name ORDER BY c DESC',
    ).get();
    return [
      for (final row in rows)
        {'name': row.read<String>('name'), 'count': row.read<int>('c')},
    ];
  }

  Future<List<Map<String, dynamic>>> recentAnalyticsEvents({
    int limit = 40,
  }) async {
    final rows = await customSelect(
      'SELECT id, name, properties_json, created_at, synced '
      'FROM analytics_events ORDER BY created_at DESC LIMIT ?',
      variables: [Variable<int>(limit)],
    ).get();
    return [
      for (final row in rows)
        {
          'id': row.read<String>('id'),
          'name': row.read<String>('name'),
          'propertiesJson': row.read<String>('properties_json'),
          'createdAt': DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('created_at'),
          ),
          'synced': row.read<int>('synced') == 1,
        },
    ];
  }

  Future<void> _ensureBillingSchema() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS ledger_entries (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  journal_ref TEXT NOT NULL,
  account_code TEXT NOT NULL,
  account_name TEXT NOT NULL,
  debit REAL NOT NULL DEFAULT 0,
  credit REAL NOT NULL DEFAULT 0,
  related_type TEXT,
  related_id TEXT,
  memo TEXT,
  user_id TEXT,
  created_at INTEGER NOT NULL
)
''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_ledger_related '
      'ON ledger_entries (business_id, related_id, created_at)',
    );
    await customStatement('''
CREATE TABLE IF NOT EXISTS product_taxes (
  product_id TEXT NOT NULL PRIMARY KEY,
  tax_rate REAL NOT NULL DEFAULT 0,
  tax_code TEXT NOT NULL DEFAULT 'EXONERE'
)
''');
    await customStatement('''
CREATE TABLE IF NOT EXISTS billing_settings (
  business_id TEXT NOT NULL PRIMARY KEY,
  allow_negative_stock INTEGER NOT NULL DEFAULT 0,
  default_tax_rate REAL NOT NULL DEFAULT 0,
  prices_include_tax INTEGER NOT NULL DEFAULT 1
)
''');
    await customStatement('''
CREATE TABLE IF NOT EXISTS invoice_templates (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  name TEXT NOT NULL,
  logo_path TEXT,
  header_text TEXT,
  footer_text TEXT,
  legal_mentions TEXT,
  is_default INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
    await _ensureColumn('sales', 'billing_json', "TEXT NOT NULL DEFAULT '{}'");
    await _ensureColumn('sale_items', 'tax_rate', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sale_items', 'tax_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('sale_items', 'line_ht', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn('products', 'tax_rate', 'REAL NOT NULL DEFAULT 0');
    await customStatement('''
CREATE TABLE IF NOT EXISTS stock_reservations (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  draft_id TEXT NOT NULL,
  quantity REAL NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
)
''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_stock_reservations_product '
      'ON stock_reservations (product_id, draft_id)',
    );
    await customStatement('''
CREATE TABLE IF NOT EXISTS cash_closes (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  closed_on INTEGER NOT NULL,
  theoretical REAL NOT NULL DEFAULT 0,
  counted REAL NOT NULL DEFAULT 0,
  variance REAL NOT NULL DEFAULT 0,
  user_id TEXT,
  created_at INTEGER NOT NULL
)
''');
  }

  Future<void> _ensureColumn(
    String table,
    String column,
    String declaration,
  ) async {
    final rows = await customSelect(
      'PRAGMA table_info($table)',
    ).get();
    final exists = rows.any((row) => row.read<String>('name') == column);
    if (exists) return;
    await customStatement(
      'ALTER TABLE $table ADD COLUMN $column $declaration',
    );
  }

  Future<void> insertLedgerEntries({
    required String businessId,
    required String journalRef,
    required String relatedType,
    required String relatedId,
    required List<Map<String, Object?>> entries,
    String? userId,
    DateTime? at,
  }) async {
    final created = (at ?? DateTime.now()).millisecondsSinceEpoch;
    for (final entry in entries) {
      await customStatement(
        'INSERT INTO ledger_entries '
        '(id, business_id, journal_ref, account_code, account_name, debit, credit, '
        'related_type, related_id, memo, user_id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          entry['id'] ?? IdGenerator.uuid(),
          businessId,
          journalRef,
          entry['accountCode'],
          entry['accountName'],
          entry['debit'] ?? 0,
          entry['credit'] ?? 0,
          relatedType,
          relatedId,
          entry['memo'],
          userId,
          created,
        ],
      );
    }
  }

  Future<List<Map<String, dynamic>>> ledgerFor({
    required String businessId,
    String? relatedId,
  }) async {
    final rows = relatedId == null
        ? await customSelect(
            'SELECT * FROM ledger_entries WHERE business_id = ? '
            'ORDER BY created_at ASC',
            variables: [Variable<String>(businessId)],
          ).get()
        : await customSelect(
            'SELECT * FROM ledger_entries WHERE business_id = ? AND related_id = ? '
            'ORDER BY created_at ASC',
            variables: [
              Variable<String>(businessId),
              Variable<String>(relatedId),
            ],
          ).get();
    return [
      for (final row in rows)
        {
          'id': row.read<String>('id'),
          'accountCode': row.read<String>('account_code'),
          'accountName': row.read<String>('account_name'),
          'debit': row.read<double>('debit'),
          'credit': row.read<double>('credit'),
          'relatedId': row.read<String?>('related_id'),
          'journalRef': row.read<String>('journal_ref'),
        },
    ];
  }

  Future<({double debit, double credit})> ledgerTotals(String businessId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(debit),0) AS d, COALESCE(SUM(credit),0) AS c '
      'FROM ledger_entries WHERE business_id = ?',
      variables: [Variable<String>(businessId)],
    ).getSingle();
    return (debit: row.read<double>('d'), credit: row.read<double>('c'));
  }

  Future<double> productTaxRate(String productId) async {
    final rows = await customSelect(
      'SELECT tax_rate FROM product_taxes WHERE product_id = ?',
      variables: [Variable<String>(productId)],
    ).get();
    if (rows.isEmpty) return 0;
    return rows.first.read<double>('tax_rate');
  }

  Future<void> setProductTaxRate(
    String productId, {
    required double taxRate,
    String taxCode = 'TVA',
  }) {
    return customStatement(
      'INSERT OR REPLACE INTO product_taxes (product_id, tax_rate, tax_code) '
      'VALUES (?, ?, ?)',
      [productId, taxRate, taxCode],
    );
  }

  Future<bool> allowNegativeStock(String businessId) async {
    final rows = await customSelect(
      'SELECT allow_negative_stock FROM billing_settings WHERE business_id = ?',
      variables: [Variable<String>(businessId)],
    ).get();
    if (rows.isEmpty) return false;
    return rows.first.read<int>('allow_negative_stock') == 1;
  }

  Future<void> setAllowNegativeStock(String businessId, bool allow) {
    return customStatement(
      'INSERT INTO billing_settings (business_id, allow_negative_stock) '
      'VALUES (?, ?) ON CONFLICT(business_id) DO UPDATE SET '
      'allow_negative_stock = excluded.allow_negative_stock',
      [businessId, allow ? 1 : 0],
    );
  }

  Future<bool> pricesIncludeTax(String businessId) async {
    final rows = await customSelect(
      'SELECT prices_include_tax FROM billing_settings WHERE business_id = ?',
      variables: [Variable<String>(businessId)],
    ).get();
    if (rows.isEmpty) return true;
    return rows.first.read<int>('prices_include_tax') == 1;
  }

  Future<String> getSaleBillingJson(String saleId) async {
    final rows = await customSelect(
      'SELECT billing_json FROM sales WHERE id = ?',
      variables: [Variable<String>(saleId)],
    ).get();
    if (rows.isEmpty) return '{}';
    return rows.first.read<String>('billing_json');
  }

  Future<void> setSaleBillingJson(String saleId, String json) {
    return customStatement('UPDATE sales SET billing_json = ? WHERE id = ?', [
      json,
      saleId,
    ]);
  }

  Future<void> updateSaleItemTax({
    required String itemId,
    required double taxRate,
    required double taxAmount,
    required double lineHt,
  }) {
    return customStatement(
      'UPDATE sale_items SET tax_rate = ?, tax_amount = ?, line_ht = ? WHERE id = ?',
      [taxRate, taxAmount, lineHt, itemId],
    );
  }

  Future<Map<String, double>> allProductTaxRates() async {
    final rows = await customSelect(
      'SELECT product_id, tax_rate FROM product_taxes',
    ).get();
    return {
      for (final row in rows)
        row.read<String>('product_id'): row.read<double>('tax_rate'),
    };
  }

  Future<void> replaceStockReservations({
    required String businessId,
    required String draftId,
    required List<({String productId, double quantity})> lines,
  }) async {
    await customStatement(
      'DELETE FROM stock_reservations WHERE draft_id = ?',
      [draftId],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final line in lines) {
      if (line.quantity <= 0) continue;
      await customStatement(
        'INSERT INTO stock_reservations '
        '(id, business_id, product_id, draft_id, quantity, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          IdGenerator.uuid(),
          businessId,
          line.productId,
          draftId,
          line.quantity,
          now,
        ],
      );
    }
  }

  Future<void> releaseDraftReservations(String draftId) {
    return customStatement(
      'DELETE FROM stock_reservations WHERE draft_id = ?',
      [draftId],
    );
  }

  Future<double> reservedQuantity(
    String productId, {
    String? exceptDraftId,
  }) async {
    final rows = exceptDraftId == null
        ? await customSelect(
            'SELECT COALESCE(SUM(quantity), 0) AS q '
            'FROM stock_reservations WHERE product_id = ?',
            variables: [Variable<String>(productId)],
          ).get()
        : await customSelect(
            'SELECT COALESCE(SUM(quantity), 0) AS q '
            'FROM stock_reservations WHERE product_id = ? AND draft_id != ?',
            variables: [
              Variable<String>(productId),
              Variable<String>(exceptDraftId),
            ],
          ).get();
    if (rows.isEmpty) return 0;
    final value = rows.first.data['q'];
    if (value is num) return value.toDouble();
    return 0;
  }

  Future<void> upsertInvoiceTemplate({
    required String id,
    required String businessId,
    required String name,
    String? logoPath,
    String? headerText,
    String? footerText,
    String? legalMentions,
    bool isDefault = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (isDefault) {
      await customStatement(
        'UPDATE invoice_templates SET is_default = 0 WHERE business_id = ?',
        [businessId],
      );
    }
    await customStatement(
      'INSERT INTO invoice_templates '
      '(id, business_id, name, logo_path, header_text, footer_text, '
      'legal_mentions, is_default, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET '
      'name = excluded.name, '
      'logo_path = excluded.logo_path, '
      'header_text = excluded.header_text, '
      'footer_text = excluded.footer_text, '
      'legal_mentions = excluded.legal_mentions, '
      'is_default = excluded.is_default, '
      'updated_at = excluded.updated_at',
      [
        id,
        businessId,
        name,
        logoPath,
        headerText,
        footerText,
        legalMentions,
        isDefault ? 1 : 0,
        now,
        now,
      ],
    );
  }

  Future<Map<String, dynamic>?> defaultInvoiceTemplate(String businessId) async {
    final rows = await customSelect(
      'SELECT * FROM invoice_templates WHERE business_id = ? '
      'ORDER BY is_default DESC, updated_at DESC LIMIT 1',
      variables: [Variable<String>(businessId)],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'id': row.read<String>('id'),
      'name': row.read<String>('name'),
      'logoPath': row.read<String?>('logo_path'),
      'headerText': row.read<String?>('header_text'),
      'footerText': row.read<String?>('footer_text'),
      'legalMentions': row.read<String?>('legal_mentions'),
    };
  }

  Future<Map<String, dynamic>> recordCashClose({
    required String businessId,
    required DateTime day,
    required double counted,
    String? userId,
  }) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await customSelect(
      'SELECT COALESCE(SUM(CASE '
      "WHEN type IN ('sale', 'debt') AND method = 'cash' THEN amount "
      "WHEN type = 'refund' THEN -amount "
      'ELSE 0 END), 0) AS theoretical '
      'FROM payments WHERE business_id = ? '
      'AND paid_at >= ? AND paid_at < ?',
      variables: [
        Variable<String>(businessId),
        Variable<int>(start.millisecondsSinceEpoch),
        Variable<int>(end.millisecondsSinceEpoch),
      ],
    ).get();
    final raw = rows.isEmpty ? 0 : rows.first.data['theoretical'];
    final theoretical = raw is num ? raw.toDouble() : 0.0;
    final variance = counted - theoretical;
    final id = IdGenerator.uuid();
    await customStatement(
      'INSERT INTO cash_closes '
      '(id, business_id, closed_on, theoretical, counted, variance, user_id, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        businessId,
        start.millisecondsSinceEpoch,
        theoretical,
        counted,
        variance,
        userId,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    return {
      'id': id,
      'theoretical': theoretical,
      'counted': counted,
      'variance': variance,
    };
  }

  // ——— Business ———
  Future<Business?> getBusiness(String id) =>
      (select(businesses)
            ..where((t) => t.id.equals(id) & t.isDeleted.equals(false)))
          .getSingleOrNull();

  Future<Business?> getFirstBusiness() =>
      (select(businesses)
            ..where((t) => t.isDeleted.equals(false))
            ..limit(1))
          .getSingleOrNull();

  Future<int> insertBusiness(BusinessesCompanion entry) =>
      into(businesses).insertOnConflictUpdate(entry);

  // ——— Users ———
  Future<User?> getUser(String id) =>
      (select(users)..where((t) => t.id.equals(id) & t.isDeleted.equals(false)))
          .getSingleOrNull();

  Future<List<User>> getUsersForBusiness(String businessId) =>
      (select(users)
            ..where(
              (t) =>
                  t.businessId.equals(businessId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.fullName)]))
          .get();

  Future<User?> getRecoveryUserForBusiness(String businessId) async {
    final businessUsers = await getUsersForBusiness(businessId);
    if (businessUsers.isEmpty) return null;
    return businessUsers.cast<User?>().firstWhere(
      (user) => user!.isOwner,
      orElse: () => businessUsers.first,
    );
  }

  Future<int> insertUser(UsersCompanion entry) =>
      into(users).insertOnConflictUpdate(entry);

  Future<int> upsertDevice(DevicesCompanion entry) =>
      into(devices).insertOnConflictUpdate(entry);

  // ——— Products ———
  Future<List<Product>> getProducts(
    String businessId, {
    String? query,
    bool? lowStock,
  }) {
    final q = select(products)
      ..where(
        (t) => t.businessId.equals(businessId) & t.isDeleted.equals(false),
      );
    if (query != null && query.isNotEmpty) {
      final lower = query.toLowerCase();
      q.where(
        (t) =>
            t.name.lower().like('%$lower%') |
            t.barcode.like('%$query%') |
            t.sku.lower().like('%$lower%'),
      );
    }
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.get().then((list) {
      if (lowStock == true) {
        return list
            .where((p) => p.trackStock && p.stockQty <= p.lowStockThreshold)
            .toList();
      }
      return list;
    });
  }

  Future<Product?> getProduct(String id) =>
      (select(products)
            ..where((t) => t.id.equals(id) & t.isDeleted.equals(false)))
          .getSingleOrNull();

  Future<Product?> getProductByBarcode(String businessId, String barcode) =>
      (select(products)..where(
            (t) =>
                t.businessId.equals(businessId) &
                t.barcode.equals(barcode) &
                t.isDeleted.equals(false),
          ))
          .getSingleOrNull();

  Future<Product?> getProductBySku(String businessId, String sku) =>
      (select(products)..where(
            (t) =>
                t.businessId.equals(businessId) &
                t.sku.equals(sku) &
                t.isDeleted.equals(false),
          ))
          .getSingleOrNull();

  Future<Set<String>> getProductSkus(String businessId) async {
    final rows =
        await (select(products)..where(
              (t) =>
                  t.businessId.equals(businessId) & t.isDeleted.equals(false),
            ))
            .get();
    return {
      for (final product in rows)
        if (product.sku != null && product.sku!.isNotEmpty) product.sku!,
    };
  }

  Future<int> insertProduct(ProductsCompanion entry) =>
      into(products).insertOnConflictUpdate(entry);

  Future<bool> updateProductRow(Product product) =>
      update(products).replace(product);

  // ——— Customers ———
  Future<List<Customer>> getCustomers(String businessId, {String? query}) {
    final q = select(customers)
      ..where(
        (t) => t.businessId.equals(businessId) & t.isDeleted.equals(false),
      );
    if (query != null && query.isNotEmpty) {
      final lower = query.toLowerCase();
      q.where(
        (t) => t.name.lower().like('%$lower%') | t.phone.like('%$query%'),
      );
    }
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.get();
  }

  Future<Customer?> getCustomer(String id) =>
      (select(customers)
            ..where((t) => t.id.equals(id) & t.isDeleted.equals(false)))
          .getSingleOrNull();

  Future<int> insertCustomer(CustomersCompanion entry) =>
      into(customers).insertOnConflictUpdate(entry);

  Future<bool> updateCustomerRow(Customer c) => update(customers).replace(c);

  // ——— Sales ———
  Future<List<Sale>> getSales(
    String businessId, {
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) {
    final q = select(sales)
      ..where(
        (t) => t.businessId.equals(businessId) & t.isDeleted.equals(false),
      );
    if (from != null) q.where((t) => t.soldAt.isBiggerOrEqualValue(from));
    if (to != null) q.where((t) => t.soldAt.isSmallerOrEqualValue(to));
    q.orderBy([(t) => OrderingTerm.desc(t.soldAt)]);
    q.limit(limit);
    return q.get();
  }

  Future<Sale?> getSale(String id) =>
      (select(sales)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<SaleItem>> getSaleItems(String saleId) =>
      (select(saleItems)..where((t) => t.saleId.equals(saleId))).get();

  // ——— Returns ———
  Future<List<SaleReturn>> getSaleReturns(
    String businessId, {
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) {
    final q = select(saleReturns)
      ..where((t) => t.businessId.equals(businessId));
    if (from != null) q.where((t) => t.createdAt.isBiggerOrEqualValue(from));
    if (to != null) q.where((t) => t.createdAt.isSmallerOrEqualValue(to));
    q.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    q.limit(limit);
    return q.get();
  }

  Future<SaleReturn?> getSaleReturn(String id) =>
      (select(saleReturns)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<SaleReturnItem>> getSaleReturnItems(String returnId) =>
      (select(saleReturnItems)..where((t) => t.returnId.equals(returnId))).get();

  // ——— Expenses ———
  Future<List<Expense>> getExpenses(
    String businessId, {
    DateTime? from,
    DateTime? to,
  }) {
    final q = select(expenses)
      ..where(
        (t) => t.businessId.equals(businessId) & t.isDeleted.equals(false),
      );
    if (from != null) q.where((t) => t.expenseDate.isBiggerOrEqualValue(from));
    if (to != null) q.where((t) => t.expenseDate.isSmallerOrEqualValue(to));
    q.orderBy([(t) => OrderingTerm.desc(t.expenseDate)]);
    return q.get();
  }

  // ——— Suppliers / Purchases ———
  Future<List<Supplier>> getSuppliers(String businessId) =>
      (select(suppliers)
            ..where(
              (t) =>
                  t.businessId.equals(businessId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<List<Purchase>> getPurchases(String businessId) =>
      (select(purchases)
            ..where(
              (t) =>
                  t.businessId.equals(businessId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.purchasedAt)]))
          .get();

  // ——— Quotes / Invoices ———
  Future<List<Quote>> getQuotes(String businessId) =>
      (select(quotes)
            ..where(
              (t) =>
                  t.businessId.equals(businessId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<List<Invoice>> getInvoices(String businessId) =>
      (select(invoices)
            ..where(
              (t) =>
                  t.businessId.equals(businessId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.issuedAt)]))
          .get();

  // ——— Deliveries ———
  Future<List<Delivery>> getDeliveries(String businessId, {String? status}) {
    final q = select(deliveries)..where((t) => t.businessId.equals(businessId));
    if (status != null) q.where((t) => t.status.equals(status));
    q.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return q.get();
  }

  // ——— Debtors ———
  Future<List<Customer>> getDebtors(String businessId) =>
      (select(customers)
            ..where(
              (t) =>
                  t.businessId.equals(businessId) &
                  t.isDeleted.equals(false) &
                  t.balance.isBiggerThanValue(0),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.balance)]))
          .get();

  Future<List<DebtMovement>> getDebtMovements(String customerId) =>
      (select(debtMovements)
            ..where((t) => t.customerId.equals(customerId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  // ——— Audit ———
  Future<int> insertAudit(AuditLogsCompanion entry) =>
      into(auditLogs).insertOnConflictUpdate(entry);

  // ——— Sync ———
  Future<List<SyncQueueEntry>> getPendingSync() =>
      (select(syncQueue)
            ..where((t) => t.status.isIn(['pending', 'local']))
            ..orderBy([(t) => OrderingTerm.asc(t.localCreatedAt)]))
          .get();

  Future<int> enqueueSync(SyncQueueCompanion entry) =>
      into(syncQueue).insertOnConflictUpdate(entry);

  // ——— Settings ———
  Future<String?> getSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(
    String key,
    String value, {
    String? businessId,
  }) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: key,
        value: value,
        businessId: Value(businessId),
        updatedAt: DateTime.now(),
      ),
    );
  }

  // ——— Dashboard aggregates ———
  Future<Map<String, double>> todayStats(String businessId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    final todaySales = await getSales(
      businessId,
      from: start,
      to: end,
      limit: 10000,
    );
    final completed = todaySales.where((s) => s.status == 'completed');
    double sold = 0;
    double collected = 0;
    double credit = 0;
    for (final s in completed) {
      sold += s.total;
      collected += s.amountPaid;
      credit += s.amountDue;
    }

    final todayExpenses = await getExpenses(businessId, from: start, to: end);
    double expensesTotal = 0;
    for (final e in todayExpenses.where((e) => e.status == 'confirmed')) {
      expensesTotal += e.amount;
    }

    return {
      'sold': sold,
      'collected': collected,
      'credit': credit,
      'expenses': expensesTotal,
      'profit_estimate': collected - expensesTotal,
      'sales_count': completed.length.toDouble(),
    };
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final legacyFile = File(p.join(dir.path, 'kumba_business.db'));
    final encryptedFile = File(p.join(dir.path, 'kumba_business_encrypted.db'));
    final key = await SecureStorageService().getOrCreateDatabaseKey();
    final escapedKey = key.replaceAll("'", "''");
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
    return NativeDatabase.createInBackground(
      encryptedFile,
      isolateSetup: () async {
        open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
        if (await legacyFile.exists() && !await encryptedFile.exists()) {
          final temporary = File('${encryptedFile.path}.migration');
          if (await temporary.exists()) await temporary.delete();
          final source = sqlite.sqlite3.open(legacyFile.path);
          try {
            if (source.select('PRAGMA cipher_version;').isEmpty) {
              throw StateError('SQLCipher encryption engine unavailable');
            }
            source.select('SELECT count(*) FROM sqlite_master;');
            source.execute(
              "ATTACH DATABASE "
              "'${temporary.path.replaceAll("'", "''")}' "
              "AS encrypted KEY '$escapedKey';",
            );
            source.select("SELECT sqlcipher_export('encrypted');");
            source.execute('DETACH DATABASE encrypted;');
          } finally {
            source.dispose();
          }
          final migrating = sqlite.sqlite3.open(temporary.path);
          try {
            migrating.execute("PRAGMA key = '$escapedKey';");
            migrating.select('SELECT count(*) FROM sqlite_master;');
          } finally {
            migrating.dispose();
          }
          await temporary.rename(encryptedFile.path);
          await legacyFile.delete();
          for (final suffix in const ['-wal', '-shm', '-journal']) {
            final sidecar = File('${legacyFile.path}$suffix');
            if (await sidecar.exists()) await sidecar.delete();
          }
        }
      },
      setup: (rawDb) {
        if (rawDb.select('PRAGMA cipher_version;').isEmpty) {
          throw StateError('SQLCipher encryption engine unavailable');
        }
        rawDb.execute("PRAGMA key = '$escapedKey';");
        rawDb.select('SELECT count(*) FROM sqlite_master;');
        rawDb.execute('PRAGMA cipher_memory_security = ON;');
      },
    );
  });
}

/// Base en mémoire pour tests.
AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}
