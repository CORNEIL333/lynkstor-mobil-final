import 'dart:convert';

import '../../core/config/sector_modules.dart';
import '../../core/billing/ed25519_license_verifier.dart';
import '../../core/billing/license_contract.dart';
import '../../core/config/app_config.dart';
import '../../core/database/app_database.dart';
import '../../core/logging/app_logger.dart';
import '../../core/security/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/subscription_info.dart';
import 'cloud_registration_service.dart';

class BootstrapResult {
  const BootstrapResult({
    required this.isAuthenticated,
    required this.needsOnboarding,
    this.business,
    this.user,
    this.performanceMode = false,
    this.biometricEnabled = false,
    this.subscription = SubscriptionInfo.unknownValue,
  });

  final bool isAuthenticated;
  final bool needsOnboarding;
  final Business? business;
  final User? user;
  final bool performanceMode;
  final bool biometricEnabled;
  final SubscriptionInfo subscription;
}

class SessionService {
  SessionService({
    required this.db,
    required this.secure,
    this.enforceLicensePolicy,
  });

  final AppDatabase db;
  final SecureStorageService secure;

  /// Politique d'application de la licence (audit S1). Injectée depuis la
  /// [RuntimeConfig] du serveur → le verrouillage s'active SANS rebuild
  /// binaire. Résolue à chaque estampille (async) ; en cas d'échec on retombe
  /// sur la const de compilation, jamais sur un choix muet.
  final Future<bool> Function()? enforceLicensePolicy;

  Future<BootstrapResult> bootstrap() async {
    final onboardingDone = await secure.isOnboardingDone();
    final businessId = await secure.getCurrentBusinessId();
    final userId = await secure.getCurrentUserId();
    final prefs = await SharedPreferences.getInstance();
    final performanceMode = prefs.getBool('performance_mode') ?? false;
    final biometricEnabled = await secure.isBiometricEnabled();

    if (!onboardingDone || businessId == null) {
      return BootstrapResult(
        isAuthenticated: false,
        needsOnboarding: true,
        performanceMode: performanceMode,
        biometricEnabled: biometricEnabled,
      );
    }

    var business = await db.getBusiness(businessId);
    if (business == null) {
      return BootstrapResult(
        isAuthenticated: false,
        needsOnboarding: true,
        performanceMode: performanceMode,
        biometricEnabled: biometricEnabled,
      );
    }
    var activeBusiness = business;

    try {
      final stored = (jsonDecode(activeBusiness.modulesJson) as List)
          .cast<String>();
      final repaired = SectorModules.repairExisting(
        activeBusiness.sector,
        stored,
      );
      if (repaired.length != stored.length) {
        activeBusiness = activeBusiness.copyWith(
          modulesJson: jsonEncode(repaired),
          updatedAt: DateTime.now(),
          version: activeBusiness.version + 1,
        );
        await db.update(db.businesses).replace(activeBusiness);
      }
    } catch (_) {
      final repaired = SectorModules.forSector(activeBusiness.sector);
      activeBusiness = activeBusiness.copyWith(
        modulesJson: jsonEncode(repaired),
        updatedAt: DateTime.now(),
        version: activeBusiness.version + 1,
      );
      await db.update(db.businesses).replace(activeBusiness);
    }

    User? user;
    if (userId != null) {
      user = await db.getUser(userId);
    }
    if (user == null || user.businessId != businessId) {
      user = await db.getRecoveryUserForBusiness(businessId);
      if (user != null) {
        await secure.setCurrentUserId(user.id);
        AppLogger.w('Session user reference repaired for business $businessId');
      }
    }
    if (user == null) {
      await secure.clearSession();
      return BootstrapResult(
        isAuthenticated: false,
        needsOnboarding: true,
        business: activeBusiness,
        performanceMode: performanceMode,
        biometricEnabled: biometricEnabled,
      );
    }

    final token = await secure.getSessionToken();
    final authenticated = token != null;
    final subscription = await loadSubscriptionLocal(business: activeBusiness);

    return BootstrapResult(
      isAuthenticated: authenticated,
      needsOnboarding: false,
      business: activeBusiness,
      user: user,
      performanceMode: performanceMode,
      biometricEnabled: biometricEnabled,
      subscription: subscription,
    );
  }

  /// Lit le cache local (rapide, offline), puis y greffe la preuve de licence :
  /// `enforceLicense` (config prod) et `signedLicenseVerified` (jeton Ed25519
  /// mémorisé re-vérifié à froid). C'est ce qui rend la grâce offline
  /// offline-first sans jamais faire confiance à un simple flag local.
  Future<SubscriptionInfo> loadSubscriptionLocal({Business? business}) async {
    final cache = await secure.getSubscriptionCache();
    final SubscriptionInfo base;
    if (cache['planName'] != null && cache['planName']!.isNotEmpty) {
      base = SubscriptionInfo.fromCache(cache);
    } else if (business?.isDemo == true) {
      await secure.setSubscriptionCache(
        planName: 'DEMO',
        status: 'demo',
        licenseActive: true,
        source: 'demo',
      );
      base = SubscriptionInfo.demo();
    } else {
      final hasToken = (await secure.getCloudSyncToken())?.isNotEmpty == true;
      if (!hasToken) {
        base = const SubscriptionInfo(
          planName: 'LOCAL',
          status: 'local',
          licenseActive: true,
          source: 'local',
        );
      } else {
        // Cloud lié mais cache vide (mise à jour app) → unknown jusqu'au refresh
        base = const SubscriptionInfo(
          planName: '…',
          status: 'unknown',
          licenseActive: true,
          source: 'cloud',
        );
      }
    }
    return _stampLicenseProof(base, cache['licenseToken']);
  }

  /// Estampille `enforceLicense` + vérifie éventuellement le jeton signé
  /// [token] contre la clé publique embarquée, lié au business courant.
  Future<SubscriptionInfo> _stampLicenseProof(
    SubscriptionInfo info,
    String? token,
  ) async {
    final enforce = await _resolveEnforceLicense();
    final bizId = await secure.getCurrentBusinessId();
    var verified = false;
    if (token != null && token.isNotEmpty && bizId != null) {
      final license = await SignedLicense.parseAndVerify(
        token,
        const Ed25519LicenseVerifier(),
        expectedBusinessId: bizId,
      );
      verified = license != null;
    }
    return info.copyWith(
      enforceLicense: enforce,
      signedLicenseVerified: verified,
    );
  }

  /// `true` = le bypass forgable `source == 'local' | 'unknown'` est fermé.
  /// Priorité à la config runtime (activable à distance) ; si la résolution
  /// échoue ou n'est pas câblée (tests, hors Riverpod), on retombe sur la
  /// const de compilation.
  Future<bool> _resolveEnforceLicense() async {
    final policy = enforceLicensePolicy;
    if (policy == null) return AppConfig.requireAgentActivationCode;
    try {
      return await policy();
    } catch (e) {
      AppLogger.w('enforceLicense policy unavailable: $e');
      return AppConfig.requireAgentActivationCode;
    }
  }

  /// Jeton de synchronisation cloud courant (Bearer des routes payantes), ou
  /// null si l'appareil n'est pas lié au cloud. Utilisé par le paiement
  /// Mobile Money qui doit prouver l'identité de l'appareil au gateway.
  Future<String?> currentCloudSyncToken() => secure.getCloudSyncToken();

  /// Interroge Supabase et met à jour le cache. Ne throw pas (offline-first).
  Future<SubscriptionInfo> refreshSubscriptionFromCloud() async {
    final businessId = await secure.getCurrentBusinessId();
    Business? business;
    if (businessId != null) business = await db.getBusiness(businessId);

    if (business?.isDemo == true) {
      final demo = SubscriptionInfo.demo();
      await secure.setSubscriptionCache(
        planName: demo.planName,
        status: demo.status,
        licenseActive: true,
        source: 'demo',
      );
      return demo;
    }

    final token = await secure.getCloudSyncToken();
    if (token == null || token.isEmpty) {
      return loadSubscriptionLocal(business: business);
    }

    final cloud = CloudRegistrationService();
    try {
      final remote = await cloud.fetchSubscriptionStatus(syncToken: token);
      final info = SubscriptionInfo(
        planName: remote.planName,
        status: remote.subscriptionStatus,
        expiresAt: remote.expiresAt,
        checkedAt: remote.checkedAt,
        licenseActive: remote.licenseActive,
        source: 'cloud',
        priceFcfa: remote.priceFcfa,
        businessName: remote.businessName,
      );
      await secure.setSubscriptionCache(
        planName: info.planName,
        status: info.status,
        expiresAt: info.expiresAt,
        licenseActive: info.licenseActive,
        source: 'cloud',
        checkedAt: info.checkedAt,
        licenseToken: remote.licenseToken ?? '',
      );
      AppLogger.i(
        'Subscription refreshed: ${info.planName} ${info.status} active=${info.licenseActive}',
      );
      return _stampLicenseProof(info, remote.licenseToken);
    } catch (e) {
      AppLogger.w('Subscription refresh failed: $e');
      return loadSubscriptionLocal(business: business);
    } finally {
      cloud.dispose();
    }
  }

  Future<void> setPerformanceMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('performance_mode', value);
  }

  Future<void> setBiometricEnabled(bool value) =>
      secure.setBiometricEnabled(value);

  Future<bool> loginWithPin(String pin) async {
    if ((await secure.pinLockRemaining()) != null) return false;
    final ok = await secure.verifyPin(pin);
    if (!ok) {
      await secure.recordPinFailure();
      return false;
    }
    await secure.resetPinFailures();
    if (!await _hasValidCurrentIdentity()) {
      await secure.clearSession();
      return false;
    }
    await secure.setSessionToken(
      'local_${DateTime.now().millisecondsSinceEpoch}',
    );
    return true;
  }

  Future<bool> loginWithPassword(String password) async {
    final ok = await secure.verifyPassword(password);
    if (!ok) return false;
    if (!await _hasValidCurrentIdentity()) {
      await secure.clearSession();
      return false;
    }
    await secure.setSessionToken(
      'local_${DateTime.now().millisecondsSinceEpoch}',
    );
    return true;
  }

  Future<bool> openSessionAfterBiometric() async {
    if (!await _hasValidCurrentIdentity()) {
      await secure.clearSession();
      return false;
    }
    await secure.setSessionToken(
      'local_bio_${DateTime.now().millisecondsSinceEpoch}',
    );
    return true;
  }

  Future<bool> _hasValidCurrentIdentity() async {
    final businessId = await secure.getCurrentBusinessId();
    final userId = await secure.getCurrentUserId();
    if (businessId == null || userId == null) return false;
    final business = await db.getBusiness(businessId);
    final user = await db.getUser(userId);
    return business != null && user != null && user.businessId == businessId;
  }

  Future<void> logout() async {
    await secure.clearAuth();
  }

  /// Verrouille l'interface sans oublier le commerce ni l'utilisateur courant.
  Future<void> lock() => secure.clearSession();
}
