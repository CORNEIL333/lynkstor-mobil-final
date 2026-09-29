/// Config runtime serveur — client de `GET /v1/config` (audit S8).
///
/// BUT : donner à l'éditeur un levier à distance, sans redistribution binaire :
///   * **force-update** : refuser une version trop ancienne (`minSupportedVersion`)
///     — indispensable pour retirer du marché une build vulnérable ;
///   * **kill switch** : désactiver un module à distance ([killModules])
///     (ex. IA locale, scanner, module de paiement défaillant) ;
///   * **maintenance** : écran d'attente global ;
///   * grâce **offline-first** : l'échec réseau ne bloque JAMAIS l'app. On
///     retombe sur [RuntimeConfig.safeDefault] (aucune restriction), et on
///     conserve la dernière config connue tant qu'elle n'est pas périmée.
///
/// La config est publique (aucune PII, aucun secret) ; elle est servie par la
/// gateway avec des valeurs issues de variables d'environnement.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Sémantique : renvoie <0 si [a] < [b], 0 si égaux, >0 si [a] > [b].
/// Gère "1.2.0" vs "1.2" vs "1.10.0" (comparaison numérique champ par champ).
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.trim().split(RegExp(r'[^0-9]+')).where((s) => s.isNotEmpty).map(int.parse).toList();
  final pa = parts(a);
  final pb = parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

class RuntimeConfig {
  const RuntimeConfig({
    required this.minSupportedVersion,
    required this.latestVersion,
    required this.maintenance,
    required this.killModules,
    required this.maxOfflineDays,
    required this.requireAgentActivationCode,
    this.updateMessage = '',
    this.announcement,
    this.announcementUrl,
    this.serverTime,
    this.fetchedAt,
  });

  final String minSupportedVersion;
  final String latestVersion;
  final bool maintenance;

  /// Modules coupés à distance (minuscules) : `ai`, `scanner`, `wave`, …
  final Set<String> killModules;
  final int maxOfflineDays;
  final bool requireAgentActivationCode;
  final String updateMessage;
  final String? announcement;
  final String? announcementUrl;
  final DateTime? serverTime;

  /// Horodatage local du fetch (grâce offline). Null = jamais récupéré.
  final DateTime? fetchedAt;

  /// Version actuelle insuffisante → mise à jour obligatoire.
  bool updateRequiredFor(String currentVersion) =>
      currentVersion.isNotEmpty &&
      compareVersions(currentVersion, minSupportedVersion) < 0;

  /// Dernière politique d'activation connue, lisible SYNCRONEment (hooks hors
  /// Riverpod, `SessionService`) : `null` = jamais récupéré depuis le
  /// démarrage. Alimentée par [RuntimeConfigService.fetch].
  static bool? lastRequireAgentActivationCode;

  /// Résolution pour les appelants qui ne peuvent pas attendre : la valeur
  /// serveur connue, sinon la const de compilation (jamais un défaut muet).
  static bool requireAgentActivationCodeOr(bool compileTimeFallback) =>
      lastRequireAgentActivationCode ?? compileTimeFallback;

  bool isModuleKilled(String module) => killModules.contains(module.toLowerCase());

  /// Une config récupérée il y a plus de [maxAge] n'est plus digne de foi :
  /// l'app doit retenter un fetch (ex. après une longue période hors ligne).
  bool isStale(Duration maxAge) {
    final at = fetchedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > maxAge;
  }

  /// Aucun droit d'en restreindre l'usage par défaut : c'est le comportement
  /// SÛR en cas d'échec réseau (offline-first). Ne jamais activer maintenance
  /// ou kill sur une config inconnue.
  static const RuntimeConfig safeDefault = RuntimeConfig(
    minSupportedVersion: '0.0.0',
    latestVersion: '',
    maintenance: false,
    killModules: <String>{},
    maxOfflineDays: 7,
    requireAgentActivationCode: false,
  );

  factory RuntimeConfig.fromJson(Map<String, dynamic> j) {
    return RuntimeConfig(
      minSupportedVersion: (j['minSupportedVersion'] as String?)?.trim().isNotEmpty == true
          ? j['minSupportedVersion'] as String
          : '0.0.0',
      latestVersion: (j['latestVersion'] as String?) ?? '',
      maintenance: j['maintenance'] == true,
      killModules: ((j['killModules'] as List?) ?? const [])
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet(),
      maxOfflineDays: (j['maxOfflineDays'] as num?)?.toInt() ?? 7,
      requireAgentActivationCode: j['requireAgentActivationCode'] == true,
      updateMessage: (j['updateMessage'] as String?) ?? '',
      announcement: (j['announcement'] as String?)?.trim().isNotEmpty == true
          ? j['announcement'] as String
          : null,
      announcementUrl: (j['announcementUrl'] as String?)?.trim().isNotEmpty == true
          ? j['announcementUrl'] as String
          : null,
      serverTime: DateTime.tryParse((j['serverTime'] as String?) ?? ''),
      fetchedAt: DateTime.now(),
    );
  }
}

/// Récupère et normalise `GET /v1/config`. Ne lève jamais : toute erreur
/// (hors ligne, HTTP, parsing) retombe sur [fallback].
class RuntimeConfigService {
  RuntimeConfigService({http.Client? client, required this.configUrl, this.anonKey})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String configUrl;
  final String? anonKey;

  Future<RuntimeConfig> fetch({
    RuntimeConfig fallback = RuntimeConfig.safeDefault,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final res = await _client
          .get(
            Uri.parse(configUrl),
            headers: {
              'Content-Type': 'application/json',
              if (anonKey != null && anonKey!.isNotEmpty) ...{
                'apikey': anonKey!,
                'Authorization': 'Bearer ${anonKey!}',
              },
            },
          )
          .timeout(timeout);
      if (res.statusCode != 200) return _remember(fallback);
      final decoded = jsonDecode(res.body);
      // La gateway enveloppe : { status, data: {...} }
      final data = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : Map<String, dynamic>.from(decoded as Map);
      return _remember(RuntimeConfig.fromJson(data));
    } catch (_) {
      return _remember(fallback);
    }
  }

  /// Expose la politique d'activation aux lectureurs synchrones. La config
  /// retombée (hors ligne) est volontairement mémorisée aussi : c'est la
  /// "dernière connue", et [RuntimeConfig.safeDefault] ne restreint rien.
  static RuntimeConfig _remember(RuntimeConfig config) {
    RuntimeConfig.lastRequireAgentActivationCode =
        config.requireAgentActivationCode;
    return config;
  }
}

/// Politique d'activation lue SYNCHRONEMENT par la couche UI (onboarding,
/// bannière, écran d'abonnement), pour que le discours affiché reste aligné
/// avec le verrou de vente [SubscriptionInfo.allowsSales].
///
/// Source de vérité = [RuntimeConfig.requireAgentActivationCode] du serveur,
/// poussée ici par un `ref.listen` dans `main.dart`. Aucune dépendance à
/// Riverpod ni au réseau : les widget tests montent donc les écrans sans
/// déclencher de fetch, et [sync] null laisse la valeur précédente inchangée.
class ActivationPolicy {
  ActivationPolicy._();

  static bool? _requireAgentActivationCode;

  static bool get requireAgentActivationCode =>
      _requireAgentActivationCode ?? AppConfig.requireAgentActivationCode;

  /// Alimente le cache depuis la config runtime (null = rien de connu →
  /// comportement de compilation).
  static void sync(bool? serverValue) {
    if (serverValue != null) _requireAgentActivationCode = serverValue;
  }

  /// Réinitialisation (tests).
  static void reset() => _requireAgentActivationCode = null;
}
