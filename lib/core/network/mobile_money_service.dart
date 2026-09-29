import 'dart:async';
import '../logging/app_logger.dart';

enum MobileMoneyProvider { orangeMoney, mtnMoMo, wave, moovMoney }

enum MobileMoneyStatus { comingSoon, pending, success, failed }

class MobileMoneyTransactionResult {
  const MobileMoneyTransactionResult({
    required this.transactionId,
    required this.status,
    required this.reference,
    required this.provider,
    required this.amount,
    this.customerPhone,
    this.errorMessage,
  });

  final String transactionId;
  final MobileMoneyStatus status;
  final String reference;
  final MobileMoneyProvider provider;
  final double amount;
  final String? customerPhone;
  final String? errorMessage;
}

/// Enregistrement de paiements Mobile Money par **référence manuelle**.
/// Pas de push USSD / API opérateur dans cette version (pas de simulation trompeuse).
class MobileMoneyService {
  MobileMoneyService({bool sandboxMode = true}) : _sandboxMode = sandboxMode;

  // Conservé pour compatibilité d’injection ; le flux réel est la saisie de référence.
  // ignore: unused_field
  final bool _sandboxMode;

  /// Enregistre une référence de paiement déjà effectuée hors app.
  Future<MobileMoneyTransactionResult> initiatePayment({
    required String phone,
    required double amount,
    required MobileMoneyProvider provider,
    required String businessId,
    String? note,
    String? manualReference,
  }) async {
    final ref = (manualReference != null && manualReference.trim().isNotEmpty)
        ? manualReference.trim()
        : 'MOBILE-MONEY-A-VENIR';

    AppLogger.i(
      'MobileMoney: référence manuelle amount=$amount phone=$phone provider=${provider.name} ref=$ref',
    );

    return MobileMoneyTransactionResult(
      transactionId: 'coming-soon',
      status: MobileMoneyStatus.comingSoon,
      reference: ref,
      provider: provider,
      amount: amount,
      customerPhone: phone,
      errorMessage:
          'Fonctionnalité à venir — aucune transaction opérateur exécutée.',
    );
  }

  /// Vérifie le statut d'une transaction Mobile Money en attente.
  Future<MobileMoneyTransactionResult> checkStatus(String transactionId) async {
    return MobileMoneyTransactionResult(
      transactionId: transactionId,
      status: MobileMoneyStatus.comingSoon,
      reference: 'MOBILE-MONEY-A-VENIR',
      provider: MobileMoneyProvider.orangeMoney,
      amount: 0.0,
      errorMessage: 'Fonctionnalité à venir — statut opérateur indisponible.',
    );
  }
}
