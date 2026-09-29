import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/database/app_database.dart';

void main() {
  group('AppDatabase migrations', () {
    late Directory tempDirectory;
    late File databaseFile;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'lynkstor_db_migration_',
      );
      databaseFile = File('${tempDirectory.path}/migration.sqlite');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('repairs a partially applied v1 to v2 migration', () async {
      final initial = AppDatabase(NativeDatabase(databaseFile));
      await initial.customSelect('SELECT 1').get();
      await initial.customStatement('DROP TABLE automation_rules');
      await initial.customStatement('DROP TABLE automation_runs');
      await initial.customStatement('DROP TABLE supplier_products');
      await initial.customStatement('PRAGMA user_version = 1');
      await initial.close();

      final migrated = AppDatabase(NativeDatabase(databaseFile));
      addTearDown(migrated.close);

      final tables = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name IN "
            "('app_notifications', 'automation_rules', "
            "'automation_runs', 'supplier_products')",
          )
          .map((row) => row.read<String>('name'))
          .get();

      expect(tables.toSet(), {
        'app_notifications',
        'automation_rules',
        'automation_runs',
        'supplier_products',
      });
      final version = await migrated
          .customSelect('PRAGMA user_version')
          .map((row) => row.read<int>('user_version'))
          .getSingle();
      expect(version, 3);
    });

    test(
      'repairs missing v2 tables even when user_version is already 2',
      () async {
        final initial = AppDatabase(NativeDatabase(databaseFile));
        await initial.customSelect('SELECT 1').get();
        await initial.customStatement('DROP TABLE automation_runs');
        await initial.close();

        final repaired = AppDatabase(NativeDatabase(databaseFile));
        addTearDown(repaired.close);

        final exists = await repaired
            .customSelect(
              "SELECT COUNT(*) AS count FROM sqlite_master "
              "WHERE type = 'table' AND name = 'automation_runs'",
            )
            .map((row) => row.read<int>('count'))
            .getSingle();
        expect(exists, 1);
      },
    );
  });
}
