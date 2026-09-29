import 'package:drift/drift.dart';

/// Tables cœur : commerce, utilisateurs, appareils, audit, sync.
@DataClassName('Business')
class Businesses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get ownerName => text()();
  TextColumn get phone => text()();
  TextColumn get city => text().nullable()();
  TextColumn get neighborhood => text().nullable()();
  TextColumn get sector => text().withDefault(const Constant('boutique'))();
  TextColumn get currency => text().withDefault(const Constant('FCFA'))();
  TextColumn get currencyCode => text().withDefault(const Constant('XOF'))();
  TextColumn get language => text().withDefault(const Constant('fr'))();
  TextColumn get logoPath => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get legalName => text().nullable()();
  TextColumn get taxId => text().nullable()();
  TextColumn get rccm => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get whatsapp => text().nullable()();
  TextColumn get slogan => text().nullable()();
  TextColumn get description => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  TextColumn get mode =>
      text().withDefault(const Constant('individual'))(); // individual | team
  TextColumn get modulesJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isDemo => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Users extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get fullName => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get username => text().nullable()();
  TextColumn get role => text().withDefault(const Constant('owner'))();
  TextColumn get permissionsJson => text().withDefault(const Constant('[]'))();
  TextColumn get photoPath => text().nullable()();
  TextColumn get agencyId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  BoolColumn get isOwner => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get userId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get platform => text().withDefault(const Constant('android'))();
  TextColumn get model => text().nullable()();
  BoolColumn get isAuthorized => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isRevoked => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  TextColumn get action => text()();
  TextColumn get entityType => text().nullable()();
  TextColumn get entityId => text().nullable()();
  TextColumn get detailsJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncQueueEntry')
class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()(); // create | update | delete
  TextColumn get payloadJson => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  // local | pending | syncing | synced | conflict | error
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  TextColumn get idempotencyKey => text()();
  TextColumn get agencyId => text().nullable()();
  TextColumn get userId => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  DateTimeColumn get localCreatedAt => dateTime()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get businessId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}
