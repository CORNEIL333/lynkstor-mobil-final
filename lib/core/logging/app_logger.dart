import 'package:logger/logger.dart';

/// Logger centralisé de l'application.
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: false,
      printEmojis: false,
    ),
  );

  static void d(String message, [Object? error, StackTrace? stack]) {
    _logger.d(message, error: error, stackTrace: stack);
  }

  static void i(String message, [Object? error, StackTrace? stack]) {
    _logger.i(message, error: error, stackTrace: stack);
  }

  static void w(String message, [Object? error, StackTrace? stack]) {
    _logger.w(message, error: error, stackTrace: stack);
  }

  static void e(String message, [Object? error, StackTrace? stack]) {
    _logger.e(message, error: error, stackTrace: stack);
  }

  /// Audit métier (ne jamais logger PIN, mots de passe, tokens).
  static void audit(
    String action, {
    String? userId,
    String? entityId,
    Map<String, dynamic>? meta,
  }) {
    _logger.i('AUDIT action=$action user=$userId entity=$entityId meta=$meta');
  }
}
