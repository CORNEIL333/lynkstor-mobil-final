import 'package:drift/drift.dart';

import 'catalog_tables.dart';
import 'core_tables.dart';
import 'ops_tables.dart';

@DataClassName('AppNotification')
class AppNotifications extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get type => text()();
  TextColumn get severity => text().withDefault(const Constant('info'))();
  TextColumn get titleKey => text()();
  TextColumn get bodyKey => text()();
  TextColumn get argsJson => text().withDefault(const Constant('{}'))();
  TextColumn get entityType => text().nullable()();
  TextColumn get entityId => text().nullable()();
  TextColumn get actionType => text().nullable()();
  TextColumn get actionPayloadJson => text().nullable()();
  TextColumn get dedupeKey => text().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get readAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class AutomationRules extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get triggerType => text()();
  TextColumn get name => text()();
  TextColumn get conditionJson => text().withDefault(const Constant('{}'))();
  TextColumn get actionType => text()();
  TextColumn get actionConfigJson => text().withDefault(const Constant('{}'))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get cooldownMinutes =>
      integer().withDefault(const Constant(1440))();
  DateTimeColumn get lastRunAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class AutomationRuns extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get ruleId => text().nullable()();
  TextColumn get triggerType => text()();
  TextColumn get entityType => text().nullable()();
  TextColumn get entityId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get resultJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class SupplierProducts extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  TextColumn get productId => text().references(Products, #id)();
  BoolColumn get isPreferred => boolean().withDefault(const Constant(false))();
  TextColumn get supplierReference => text().nullable()();
  RealColumn get lastUnitCost => real().nullable()();
  RealColumn get reorderQuantity => real().withDefault(const Constant(1))();
  IntColumn get leadTimeDays => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
