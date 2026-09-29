import 'app_exception.dart';

/// Converts an internal failure into text that is safe and useful in the UI.
///
/// Technical details stay in logs; SQL statements, paths and stack traces must
/// never be rendered to the merchant.
String userFacingErrorMessage(Object error, {required String fallback}) {
  if (error is AppException) return error.message;

  final message = error.toString().replaceFirst(
    RegExp(r'^(Exception|Error):\s*'),
    '',
  );
  final technical = message.toLowerCase();
  const technicalMarkers = [
    'sqliteexception',
    'sqflite',
    'constraint failed',
    'insert into',
    'update "',
    'delete from',
    'drift',
    'missingpluginexception',
    'platformexception',
    'bad state:',
    'stack trace',
    'package:',
  ];

  if (message.trim().isEmpty || technicalMarkers.any(technical.contains)) {
    return fallback;
  }
  return message;
}
