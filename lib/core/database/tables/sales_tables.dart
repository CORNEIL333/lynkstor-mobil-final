import 'package:drift/drift.dart';

import 'core_tables.dart';

class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get neighborhood => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  RealColumn get creditLimit => real().withDefault(const Constant(0))();
  RealColumn get balance =>
      real().withDefault(const Constant(0))(); // positive = client owes
  TextColumn get note => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get lastActivityAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get reference => text()();
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  // draft | completed | cancelled | returned
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();
  RealColumn get amountDue => real().withDefault(const Constant(0))();
  RealColumn get changeGiven => real().withDefault(const Constant(0))();
  TextColumn get paymentMethodsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get note => text().nullable()();
  TextColumn get userId => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  DateTimeColumn get soldAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('local'))();
  TextColumn get idempotencyKey => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text().nullable()();
  TextColumn get productName => text()();
  TextColumn get unit => text().withDefault(const Constant('pièce'))();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get costPrice => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get lineTotal => real()();

  @override
  Set<Column> get primaryKey => {id};
}

class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get reference => text()();
  TextColumn get type => text()(); // sale | debt | purchase | expense | refund
  TextColumn get relatedType => text().nullable()();
  TextColumn get relatedId => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get supplierId => text().nullable()();
  RealColumn get amount => real()();
  TextColumn get method => text()();
  // cash | mtn_momo | orange_money | transfer | card | credit | mixed | cod
  TextColumn get methodRef =>
      text().nullable()(); // ref Mobile Money saisie manuellement
  TextColumn get status => text().withDefault(const Constant('confirmed'))();
  // pending | confirmed | failed | cancelled
  TextColumn get note => text().nullable()();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get paidAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('local'))();
  TextColumn get idempotencyKey => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class DebtMovements extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get type => text()(); // credit_sale | payment | adjustment
  RealColumn get amount => real()(); // + increases debt, - decreases
  RealColumn get balanceBefore => real()();
  RealColumn get balanceAfter => real()();
  TextColumn get relatedType => text().nullable()();
  TextColumn get relatedId => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('local'))();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleReturns extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get reference => text()();
  TextColumn get reason => text()();
  RealColumn get total => real()();
  TextColumn get refundMethod => text()(); // refund | credit_note
  BoolColumn get restock => boolean().withDefault(const Constant(true))();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get authorizedBy => text().nullable()();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('local'))();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleReturnItems extends Table {
  TextColumn get id => text()();
  TextColumn get returnId => text().references(SaleReturns, #id)();
  TextColumn get saleItemId => text().nullable()();
  TextColumn get productId => text().nullable()();
  TextColumn get productName => text()();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get lineTotal => real()();

  @override
  Set<Column> get primaryKey => {id};
}
