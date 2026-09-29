import 'package:drift/drift.dart';

import 'core_tables.dart';

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get categoryId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get unit => text().withDefault(const Constant('pièce'))();
  RealColumn get salePrice => real().withDefault(const Constant(0))();
  RealColumn get costPrice => real().withDefault(const Constant(0))();
  RealColumn get wholesalePrice => real().nullable()();
  RealColumn get stockQty => real().withDefault(const Constant(0))();
  RealColumn get lowStockThreshold => real().withDefault(const Constant(5))();
  BoolColumn get trackStock => boolean().withDefault(const Constant(true))();
  BoolColumn get isService => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get photoPath => text().nullable()();
  TextColumn get expiryDate => text().nullable()(); // ISO date
  TextColumn get lotNumber => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class StockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get type => text()();
  // init | sale | purchase | return | loss | damage | inventory | transfer | adjustment
  RealColumn get quantity => real()(); // signed: + in, - out
  RealColumn get qtyBefore => real()();
  RealColumn get qtyAfter => real()();
  TextColumn get referenceType => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('local'))();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class InventorySessions extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  // open | submitted | validated | cancelled
  BoolColumn get blindMode => boolean().withDefault(const Constant(false))();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get submittedAt => dateTime().nullable()();
  DateTimeColumn get validatedAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class InventoryLines extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(InventorySessions, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get expectedQty => real()();
  RealColumn get countedQty => real().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  DateTimeColumn get countedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
