import 'package:intl/intl.dart';

import '../config/app_config.dart';

/// Formatage monétaire pour l'Afrique francophone (FCFA, espaces, etc.).
class MoneyFormat {
  MoneyFormat._();

  static final NumberFormat _number = NumberFormat('#,##0', 'fr_FR');

  /// Formate un montant en centimes ou unités entières (XOF n'a pas de décimales).
  static String format(
    num amount, {
    String? currency,
    bool showCurrency = true,
  }) {
    final cur = currency ?? AppConfig.defaultCurrency;
    final formatted = _number
        .format(amount.round())
        .replaceAll(',', ' ')
        .replaceAll('\u00A0', ' ');
    if (!showCurrency) return formatted;
    return '$formatted $cur';
  }

  /// Parse une saisie utilisateur vers un nombre.
  static double? parse(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[^\d,.\-]'), '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static String formatCompact(num amount, {String? currency}) {
    final cur = currency ?? AppConfig.defaultCurrency;
    if (amount.abs() >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)} M $cur';
    }
    if (amount.abs() >= 1000) {
      return '${(amount / 1000).toStringAsFixed(amount.abs() >= 10000 ? 0 : 1)} k $cur';
    }
    return format(amount, currency: cur);
  }
}
