import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'SQLCipher encrypts the local database file at rest',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kumba_sqlcipher_test_',
      );
      final file = File('${directory.path}${Platform.pathSeparator}secure.db');
      try {
        final database = sqlite3.open(file.path);
        expect(database.select('PRAGMA cipher_version;'), isNotEmpty);
        database.execute("PRAGMA key = 'test-only-strong-key';");
        database.execute('CREATE TABLE secret (value TEXT NOT NULL);');
        database.execute('INSERT INTO secret (value) VALUES (?);', [
          'confidential',
        ]);
        database.dispose();

        final header = await file
            .openRead(0, 16)
            .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
        expect(String.fromCharCodes(header), isNot('SQLite format 3\u0000'));

        final reopened = sqlite3.open(file.path);
        reopened.execute("PRAGMA key = 'test-only-strong-key';");
        expect(
          reopened.select('SELECT value FROM secret;').single['value'],
          'confidential',
        );
        reopened.dispose();
      } finally {
        try {
          await directory.delete(recursive: true);
        } on PathAccessException {
          // SQLCipher on Windows may retain the native handle until the test
          // isolate exits; the OS temp directory remains the only fallback.
        }
      }
    },
    skip: Platform.isWindows
        ? 'The parallel Windows test runner can preload regular sqlite3; '
              'Android performs a mandatory cipher_version runtime check.'
        : false,
  );
}
