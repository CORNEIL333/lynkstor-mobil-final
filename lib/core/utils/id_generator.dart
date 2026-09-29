import 'package:uuid/uuid.dart';

/// Génération d'identifiants UUID v4 pour sync / idempotence.
class IdGenerator {
  IdGenerator._();
  static const _uuid = Uuid();

  static String uuid() => _uuid.v4();

  /// Référence lisible métier (ex: VTE-20260721-A3F2).
  static String businessRef(String prefix) {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final short = _uuid.v4().substring(0, 4).toUpperCase();
    return '$prefix-$date-$short';
  }
}
