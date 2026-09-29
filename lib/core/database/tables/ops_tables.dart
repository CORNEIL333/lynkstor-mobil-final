import 'package:drift/drift.dart';

import 'core_tables.dart';

class ExpenseCategories extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get reference => text()();
  RealColumn get amount => real()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get categoryName => text().nullable()();
  TextColumn get account => text().withDefault(const Constant('cash'))();
  TextColumn get description => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('confirmed'))();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get expenseDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('local'))();
  TextColumn get idempotencyKey => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  RealColumn get balance =>
      real().withDefault(const Constant(0))(); // we owe supplier
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Purchases extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get reference => text()();
  TextColumn get supplierId => text().nullable()();
  TextColumn get supplierName => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('received'))();
  // draft | ordered | partial | received | cancelled
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();
  RealColumn get amountDue => real().withDefault(const Constant(0))();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get invoicePhotoPath => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get purchasedAt => dateTime()();
  DateTimeColumn get receivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('local'))();
  TextColumn get idempotencyKey => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class PurchaseItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseId => text().references(Purchases, #id)();
  TextColumn get productId => text().nullable()();
  TextColumn get productName => text()();
  RealColumn get quantityOrdered => real()();
  RealColumn get quantityReceived => real().withDefault(const Constant(0))();
  RealColumn get unitCost => real()();
  RealColumn get lineTotal => real()();

  @override
  Set<Column> get primaryKey => {id};
}

class Quotes extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get reference => text()();
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  // draft | sent | accepted | rejected | expired | converted
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  TextColumn get conditions => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get validUntil => dateTime().nullable()();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class QuoteItems extends Table {
  TextColumn get id => text()();
  TextColumn get quoteId => text().references(Quotes, #id)();
  TextColumn get productId => text().nullable()();
  TextColumn get productName => text()();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get lineTotal => real()();

  @override
  Set<Column> get primaryKey => {id};
}

class Invoices extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get reference => text()();
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text().nullable()();
  TextColumn get saleId => text().nullable()();
  TextColumn get quoteId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('issued'))();
  // draft | issued | partial | paid | cancelled | credit_note
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();
  RealColumn get amountDue => real().withDefault(const Constant(0))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get issuedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class InvoiceItems extends Table {
  TextColumn get id => text()();
  TextColumn get invoiceId => text().references(Invoices, #id)();
  TextColumn get productId => text().nullable()();
  TextColumn get productName => text()();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get lineTotal => real()();

  @override
  Set<Column> get primaryKey => {id};
}

class Deliveries extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get reference => text()();
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text()();
  TextColumn get customerPhone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('assigned'))();
  // assigned | preparing | en_route | delivered | absent | refused | postponed | partial | cancelled
  TextColumn get assignedTo => text().nullable()();
  RealColumn get amountToCollect => real().withDefault(const Constant(0))();
  RealColumn get amountCollected => real().withDefault(const Constant(0))();
  TextColumn get photoPath => text().nullable()();
  TextColumn get signaturePath => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get relatedType => text().nullable()();
  TextColumn get relatedId => text().nullable()();
  DateTimeColumn get scheduledAt => dateTime().nullable()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('local'))();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class AttendanceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get type => text()(); // check_in | check_out
  TextColumn get method => text().withDefault(const Constant('pin'))();
  // pin | qr | biometric | geo | photo
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  TextColumn get photoPath => text().nullable()();
  DateTimeColumn get recordedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('local'))();

  @override
  Set<Column> get primaryKey => {id};
}

class BackupRecords extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get filePath => text()();
  TextColumn get fileName => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get checksum => text()();
  TextColumn get type => text().withDefault(
    const Constant('manual'),
  )(); // manual | auto | transfer
  TextColumn get destination => text().withDefault(const Constant('local'))();
  BoolColumn get isEncrypted => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('success'))();

  @override
  Set<Column> get primaryKey => {id};
}
