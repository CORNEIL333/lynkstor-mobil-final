/// Configuration centrale de l'application.
/// Le nom commercial est isolé ici pour un rebranding sans toucher l'architecture.
class AppConfig {
  AppConfig._();

  static const String appName = 'Lynkstor Business';
  static const String appShortName = 'Lynkstor';
  static const String packageId = 'com.kumba.kumba_business';
  static const String version = '1.2.0';
  static const int buildNumber = 12;

  /// Devise par défaut (Afrique de l'Ouest francophone).
  static const String defaultCurrency = 'FCFA';
  static const String defaultCurrencyCode = 'XOF';
  static const String defaultLocale = 'fr';
  static const String defaultCountry = 'CM';

  /// Base locale
  static const String databaseName = 'kumba_business_encrypted.db';
  static const int databaseVersion = 4;

  /// Sécurité
  static const int pinLength = 4;
  static const int maxPinAttempts = 5;
  static const Duration sessionTimeout = Duration(minutes: 30);
  static const Duration lockAfterBackground = Duration(minutes: 2);

  /// Sync
  static const int maxSyncRetries = 5;
  static const Duration syncInterval = Duration(minutes: 5);

  /// Cloud Lynkstor — gateway Neon Function (backend production).
  /// Inscription + sync : un code agent est obligatoire pour créer un vrai commerce.
  /// Rollback Supabase (gateway Deno legacy) :
  ///   https://wtbmwquovcizrtggkkzn.supabase.co/functions/v1/lynkstor-api
  static const String cloudApiBase =
      'https://br-curly-mud-b11jrchz-api.compute.c-5.eu-central-1.aws.neon.tech';

  /// Clé anon du gateway : INUTILE côté Neon (routes register/config
  /// publiques, la vraie porte d'entrée est le code d'activation agent).
  /// L'ancien JWT Supabase legacy a été retiré le 2026-09-26 (projet
  /// legacy compromis) — laissé vide = headers apikey simplement omis.
  static const String cloudAnonKey = '';
  static const String cloudPublishableKey = '';
  static const String cloudSyncPushPath = '/api/v1/sync/push';
  static const String cloudRegisterPath = '/api/v1/register';
  static const String cloudAnalyticsPath = '/api/v1/analytics/ingest';

  /// Config runtime publique (audit S8) : force-update, kill switch, maintenance.
  static const String cloudConfigPath = '/v1/config';
  static String get cloudSyncPushUrl => '$cloudApiBase$cloudSyncPushPath';
  static String get cloudRegisterUrl => '$cloudApiBase$cloudRegisterPath';
  static String get cloudAnalyticsUrl => '$cloudApiBase$cloudAnalyticsPath';
  static String get cloudConfigUrl => '$cloudApiBase$cloudConfigPath';

  /// Paiement abonnement Mobile Money (PawaPay, modèle push). Les montants et
  /// forfaits sont résolus côté serveur ; l'app ne transporte AUCUNE secret
  /// agrégateur et ne fixe jamais le prix. Le PIN/OTP client ne transite jamais
  /// par Lynkstor (confirmation directement sur le téléphone du payeur).
  static String get cloudPaymentInitiateUrl =>
      '$cloudApiBase/api/v1/payments/initiate';
  static String cloudPaymentStatusUrl(String intentId) =>
      '$cloudApiBase/api/v1/payments/$intentId';

  /// Dossier Drive « Lynkstore analysis ».
  static const String analyticsDriveFolderId =
      '18VAF4ZmazMKQizw_OWl2YEb5oE0wAdEw';
  static const String analyticsDashboardUrl =
      'https://drive.google.com/drive/folders/18VAF4ZmazMKQizw_OWl2YEb5oE0wAdEw';

  /// Dossier créé sur le téléphone client (Documents / Téléchargements / fichiers app).
  static const String analyticsLocalFolderName = 'Lynkstor';

  /// Ingest période test : gateway Neon (route publique /api/v1/analytics/ingest,
  /// schéma lynkstor.trial.v1 — allowlist d'événements côté serveur, aucune PII).
  /// L'URL de rollback Apps Script/Drive n'est plus utilisée.
  static const String analyticsIngestUrl =
      '$cloudApiBase/api/v1/analytics/ingest';
  static const List<String> analyticsFallbackUrls = [];

  /// IA hybride « Lynk » : questions libres traitées par Llama-3.2-3B sur
  /// Cloudflare Workers AI (worker du dashboard, endpoint /ai/ask).
  /// Les questions métier couvertes (CA, dettes, stock, bénéfice) restent
  /// calculées 100 % localement et ne quittent jamais l'appareil.
  /// La clé est de classe « anon » (révocable par redéploiement wrangler).
  static const String aiAskUrl =
      'https://sweet-bush-a7e8.wosee-connect.workers.dev/ai/ask';
  static const String aiAccessAnonKey =
      '43e2f38f774d73bf91f4f8a8c52db248';
  static const String aiModelLabel = 'Llama 3.2-3B · cloud';

  /// Performance
  static const int listPageSize = 50;
  static const int maxCachedImages = 100;

  /// Demo — local uniquement, n'apparaît pas comme abonné cloud
  static const bool allowDemoMode = true;

  /// Exige un code agent pour « Créer mon commerce » (pas pour la démo).
  /// Désactivé pour le panel boutiques test : inscription libre sans clé.
  /// ⚠ En circulation, c'est la [RuntimeConfig] du serveur qui fait foi
  /// (via `ActivationPolicy` / `SessionService.enforceLicensePolicy`) : cette
  /// const n'est que le défaut avant le premier fetch, et le repli si le
  /// serveur est injoignable. Bascule en prod = changement côté Neon, pas de
  /// rebuild binaire.
  static const bool requireAgentActivationCode = false;

  /// Nombre minimum de références proposées (non activées) par secteur.
  static const int minSectorCatalogSize = 1000;
}
