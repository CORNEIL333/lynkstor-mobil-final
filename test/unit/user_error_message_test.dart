import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/errors/app_exception.dart';
import 'package:kumba_business/core/errors/user_error_message.dart';

void main() {
  const fallback = 'Une erreur locale est survenue.';

  test('keeps a typed business error', () {
    expect(
      userFacingErrorMessage(
        const ValidationException('Le nom est obligatoire.'),
        fallback: fallback,
      ),
      'Le nom est obligatoire.',
    );
  });

  test('keeps a readable service error', () {
    expect(
      userFacingErrorMessage(
        Exception('Code d’activation invalide.'),
        fallback: fallback,
      ),
      'Code d’activation invalide.',
    );
  });

  test('hides SQLite statements and constraints', () {
    expect(
      userFacingErrorMessage(
        Exception(
          'SqliteException(1555): UNIQUE constraint failed: devices.id '
          'INSERT INTO "devices"',
        ),
        fallback: fallback,
      ),
      fallback,
    );
  });

  test('hides Flutter platform implementation details', () {
    expect(
      userFacingErrorMessage(
        Exception('MissingPluginException(No implementation found)'),
        fallback: fallback,
      ),
      fallback,
    );
  });
}
