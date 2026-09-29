/// Contrat d'abonnement Lynkstor — couche d'abstraction agrégateur de paiement.
///
/// BUT : découpler l'app de tout agrégateur mobile-money précis (CinetPay,
/// SenePay, KkiaPay, Wave, …). L'app ne parle qu'à [PaymentProvider] ; un
/// adaptateur concret est choisi côté serveur, jamais côté client.
///
/// PRINCIPE SÉCURITAIRE (cf. audit S1/S3) : le client ne **signe** jamais un
/// paiement ni une licence. Il demande une intention, exécute le flux
/// opérateur, puis le résultat est **confirmé par webhook serveur**. La
/// licence n'est accordée que par un jeton signé émis par le backend
/// ([../billing/license_contract.dart]), jamais par une réponse client.
library;

/// opérateur / canaux mobiles supportés.
enum PaymentChannel { orangeMoney, mtnMoMo, wave, moovMoney, card, bankTransfer }

/// Cycle de vie d'une intention de paiement d'abonnement.
enum PaymentIntentStatus {
  created,
  pendingCustomer, // client doit confirmer chez l'opérateur (USSD/push)
  processing,
  succeeded,
  failed,
  expired,
  refunded,
}

/// Montant + devise. Devise par défaut XOF (FCFA) pour l'AOW/CEMAC.
class Money {
  const Money(this.amountMinorUnits, {this.currency = 'XOF'});

  /// Stocké en unités mineures (francs) pour éviter les erreurs de arrondi float.
  final int amountMinorUnits;
  final String currency;

  factory Money.fromFcfa(int fcfa) => Money(fcfa, currency: 'XOF');

  int get fcfa => amountMinorUnits;

  @override
  String toString() => '$amountMinorUnits $currency';
}

/// Demande de paiement créée côté serveur, transmise au client pour
/// déclencher le flux opérateur. Ne contient AUCUN secret agrégateur.
class PaymentIntent {
  const PaymentIntent({
    required this.id,
    required this.businessId,
    required this.planId,
    required this.channel,
    required this.amount,
    required this.status,
    required this.providerReference,
    this.customerPhone,
    this.clientSecret,
    this.expiresAt,
  });

  final String id;
  final String businessId;
  final String planId;
  final PaymentChannel channel;
  final Money amount;
  final PaymentIntentStatus status;

  /// Référence renvoyée par l'agrégateur ; sert de clé d'idempotence webhook.
  final String providerReference;
  final String? customerPhone;

  /// Secret temporaire (optionnel) permettant au client d'initier le flux
  /// opérateur sans exposer la clé API de l'agrégateur.
  final String? clientSecret;
  final DateTime? expiresAt;

  bool get isTerminal =>
      status == PaymentIntentStatus.succeeded ||
      status == PaymentIntentStatus.failed ||
      status == PaymentIntentStatus.expired ||
      status == PaymentIntentStatus.refunded;
}

/// Événement webhook normalisé, produit par un adaptateur agrégateur
/// après vérification de signature côté serveur.
class PaymentWebhookEvent {
  const PaymentWebhookEvent({
    required this.providerReference,
    required this.status,
    required this.receivedAt,
    this.rawPayloadId,
    this.amount,
    this.signatureValid = false,
  });

  final String providerReference;
  final PaymentIntentStatus status;
  final DateTime receivedAt;
  final String? rawPayloadId;
  final Money? amount;

  /// false ⇒ l'événement DOIT être rejeté (signature invalide / origine inconnue).
  final bool signatureValid;

  bool get isTrusted => signatureValid;
}

/// Résultats de l'appel [PaymentProvider.initiate].
class PaymentInitiationResult {
  const PaymentInitiationResult({
    required this.intent,
    required this.success,
    this.message,
  });

  final PaymentIntent intent;
  final bool success;
  final String? message;
}

/// Abstraction unique de l'agrégateur de paiement d'abonnement.
///
/// Implémentations attendues : un service HTTP **côté serveur** (Cloudflare
/// Worker / Edge Function) qui encapsule CinetPay/SenePay/KkiaPay. Le client
/// Flutter ne consomme que ce contrat via l'API gateway ; il n'a jamais accès
/// aux credentials réels de l'agrégateur.
abstract interface class PaymentProvider {
  /// Canaux effectivement disponibles pour [businessId] (pays/opérateur).
  Future<List<PaymentChannel>> availableChannels(String businessId);

  /// Crée une intention de paiement (montant = forfait du business).
  /// Ne débite rien : renvoie les éléments pour lancer le flux opérateur.
  Future<PaymentInitiationResult> initiate({
    required String businessId,
    required String planId,
    required PaymentChannel channel,
    required String customerPhone,
  });

  /// Interroge l'état courant d'une intention (polling de secours du webhook).
  Future<PaymentIntent> pollStatus(String intentId);

  /// Vérifie la signature brute d'un webhook et la normalise.
  /// Retourne un événement avec [PaymentWebhookEvent.signatureValid] = false
  /// si la signature ne valide pas — jamais d'exception qui divulgue un détail.
  Future<PaymentWebhookEvent> parseWebhook({
    required String rawBody,
    required Map<String, String> headers,
  });
}
