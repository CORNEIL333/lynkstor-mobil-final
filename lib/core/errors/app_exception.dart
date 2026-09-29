/// Exceptions métier typées — messages lisibles pour le commerçant.
sealed class AppException implements Exception {
  const AppException(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => 'AppException($code): $message';
}

class ValidationException extends AppException {
  const ValidationException(
    super.message, {
    super.code = 'validation',
    super.cause,
  });
}

class NotFoundException extends AppException {
  const NotFoundException(
    super.message, {
    super.code = 'not_found',
    super.cause,
  });
}

class PermissionException extends AppException {
  const PermissionException(
    super.message, {
    super.code = 'permission',
    super.cause,
  });
}

class AuthException extends AppException {
  const AuthException(super.message, {super.code = 'auth', super.cause});
}

class StockException extends AppException {
  const StockException(super.message, {super.code = 'stock', super.cause});
}

class PaymentException extends AppException {
  const PaymentException(super.message, {super.code = 'payment', super.cause});
}

class SyncException extends AppException {
  const SyncException(super.message, {super.code = 'sync', super.cause});
}

class BackupException extends AppException {
  const BackupException(super.message, {super.code = 'backup', super.cause});
}

class DatabaseException extends AppException {
  const DatabaseException(
    super.message, {
    super.code = 'database',
    super.cause,
  });
}

class OfflineException extends AppException {
  const OfflineException([
    super.message = 'Aucune connexion. Les données restent sur cet appareil.',
  ]) : super(code: 'offline');
}
