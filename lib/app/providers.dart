import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/config/runtime_config.dart';
import '../core/config/sector_modules.dart';
import '../core/database/app_database.dart';
import '../core/permissions/permission_guard.dart';
import '../core/permissions/permissions.dart';
import '../core/security/biometric_service.dart';
import '../core/security/secure_storage_service.dart';
import '../core/sync/sync_engine.dart';
import '../features/ai_assistant/data/lynk_brain_service.dart';
import '../features/ai_assistant/domain/business_ai_context.dart';
import '../shared/services/backup_service.dart';
import '../shared/services/automation_service.dart';
import '../shared/services/business_service.dart';
import '../shared/services/customer_service.dart';
import '../shared/services/cloud_backup_service.dart';
import '../shared/services/demo_seeder.dart';
import '../shared/services/expense_service.dart';
import '../shared/services/invitation_service.dart';
import '../shared/services/notification_service.dart';
import '../shared/services/product_service.dart';
import '../shared/services/sector_catalog_service.dart';
import '../shared/services/product_image_service.dart';
import '../shared/services/report_service.dart';
import '../shared/services/restore_onboarding_service.dart';
import '../shared/services/sale_service.dart';
import '../shared/models/subscription_info.dart';
import '../shared/services/session_service.dart';
import '../shared/services/analytics_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden at startup');
});

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

// ——— Config runtime serveur (audit S8 : force-update / kill switch) ———
final runtimeConfigServiceProvider = Provider<RuntimeConfigService>((ref) {
  return RuntimeConfigService(
    configUrl: AppConfig.cloudConfigUrl,
    anonKey: AppConfig.cloudAnonKey,
  );
});

/// FutureProvider non autoDispose : la dernière config connue est conservée
/// (grâce offline). Le [RuntimeGate] l'affiche sans bloquer pendant le fetch.
final runtimeConfigProvider = FutureProvider<RuntimeConfig>((ref) {
  return ref.watch(runtimeConfigServiceProvider).fetch();
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(ref.watch(databaseProvider));
  ref.onDispose(engine.dispose);
  return engine;
});

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService(
    db: ref.watch(databaseProvider),
    secure: ref.watch(secureStorageProvider),
    // S1 : le verrouillage se pilote A DISTANCE via la config runtime (aucun
    // rebuild binaire nécessaire). `read(...future)` renvoie la config déjà
    // mise en cache si RuntimeGate l'a lancée, sinon déclenche un fetch
    // borné ; hors ligne → safeDefault(false) → comportement historique.
    enforceLicensePolicy: () async {
      final config = await ref.read(runtimeConfigProvider.future);
      return config.requireAgentActivationCode;
    },
  );
});

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final service = AnalyticsService(
    db: ref.watch(databaseProvider),
    secure: ref.watch(secureStorageProvider),
  );
  AppAnalytics.bind(service);
  ref.onDispose(() {
    AppAnalytics.unbind();
    service.dispose();
  });
  return service;
});

final businessServiceProvider = Provider<BusinessService>((ref) {
  return BusinessService(
    db: ref.watch(databaseProvider),
    secure: ref.watch(secureStorageProvider),
    sync: ref.watch(syncEngineProvider),
  );
});

final productServiceProvider = Provider<ProductService>((ref) {
  return ProductService(
    db: ref.watch(databaseProvider),
    sync: ref.watch(syncEngineProvider),
    automation: ref.watch(automationServiceProvider),
  );
});

final productImageServiceProvider = Provider<ProductImageService>((ref) {
  return ProductImageService();
});

final sectorCatalogServiceProvider = Provider<SectorCatalogService>((ref) {
  return SectorCatalogService(
    db: ref.watch(databaseProvider),
    products: ref.watch(productServiceProvider),
  );
});

final customerServiceProvider = Provider<CustomerService>((ref) {
  return CustomerService(
    db: ref.watch(databaseProvider),
    sync: ref.watch(syncEngineProvider),
  );
});

final saleServiceProvider = Provider<SaleService>((ref) {
  return SaleService(
    db: ref.watch(databaseProvider),
    sync: ref.watch(syncEngineProvider),
    automation: ref.watch(automationServiceProvider),
  );
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(db: ref.watch(databaseProvider));
});

final automationServiceProvider = Provider<AutomationService>((ref) {
  return AutomationService(
    db: ref.watch(databaseProvider),
    notifications: ref.watch(notificationServiceProvider),
    sync: ref.watch(syncEngineProvider),
  );
});

final expenseServiceProvider = Provider<ExpenseService>((ref) {
  return ExpenseService(
    db: ref.watch(databaseProvider),
    sync: ref.watch(syncEngineProvider),
  );
});

final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService(db: ref.watch(databaseProvider));
});

final lynkBrainProvider = Provider<LynkBrainService>((ref) {
  final service = LynkBrainService();
  ref.onDispose(service.dispose);
  return service;
});

final businessAiContextProvider = Provider<BusinessAiContextBuilder>((ref) {
  return BusinessAiContextBuilder(
    db: ref.watch(databaseProvider),
    reports: ref.watch(reportServiceProvider),
  );
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    db: ref.watch(databaseProvider),
    secure: ref.watch(secureStorageProvider),
  );
});

final cloudBackupServiceProvider = Provider<CloudBackupService>((ref) {
  return CloudBackupService(
    db: ref.watch(databaseProvider),
    secure: ref.watch(secureStorageProvider),
  );
});

final invitationServiceProvider = Provider<InvitationService>((ref) {
  return InvitationService(
    db: ref.watch(databaseProvider),
    secure: ref.watch(secureStorageProvider),
    sync: ref.watch(syncEngineProvider),
  );
});

final restoreOnboardingServiceProvider = Provider<RestoreOnboardingService>((
  ref,
) {
  return RestoreOnboardingService(
    db: ref.watch(databaseProvider),
    secure: ref.watch(secureStorageProvider),
    businessService: ref.watch(businessServiceProvider),
  );
});

final demoSeederProvider = Provider<DemoSeeder>((ref) {
  return DemoSeeder(db: ref.watch(databaseProvider));
});

/// Session courante réactive.
final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>((
  ref,
) {
  ref.watch(analyticsServiceProvider);
  return SessionNotifier(ref.watch(sessionServiceProvider));
});

class SessionState {
  const SessionState({
    this.isLoading = true,
    this.isAuthenticated = false,
    this.needsOnboarding = true,
    this.business,
    this.user,
    this.performanceMode = false,
    this.biometricEnabled = false,
    this.activeModules = const [],
    this.subscription = SubscriptionInfo.unknownValue,
  });

  final bool isLoading;
  final bool isAuthenticated;
  final bool needsOnboarding;
  final Business? business;
  final User? user;
  final bool performanceMode;
  final bool biometricEnabled;
  final List<String> activeModules;
  final SubscriptionInfo subscription;

  String get role => user?.role ?? 'seller';

  PermissionGuard get guard => PermissionGuard.of(role);

  bool can(AppPermission p) => guard.allows(p);

  bool moduleEnabled(String module) {
    if (activeModules.isEmpty) return true;
    return SectorModules.isEnabled(activeModules, module);
  }

  /// Vente autorisée selon abonnement cloud (ou démo / grâce offline).
  bool get canSell => subscription.allowsSales;

  bool get subscriptionBlocked => !canSell;

  SessionState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    bool? needsOnboarding,
    Business? business,
    User? user,
    bool? performanceMode,
    bool? biometricEnabled,
    List<String>? activeModules,
    SubscriptionInfo? subscription,
  }) {
    return SessionState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
      business: business ?? this.business,
      user: user ?? this.user,
      performanceMode: performanceMode ?? this.performanceMode,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      activeModules: activeModules ?? this.activeModules,
      subscription: subscription ?? this.subscription,
    );
  }
}

class SessionNotifier extends StateNotifier<SessionState> {
  /// Pas de bootstrap auto au constructeur : le [SplashScreen] pilote le
  /// démarrage. Un second bootstrap concurrent (constructeur + splash)
  /// basculait `isLoading` true/false en rafale et cassait la navigation.
  SessionNotifier(this._service) : super(const SessionState());

  final SessionService _service;

  /// Bootstrap en vol (anti double-appel concurrent).
  Future<void>? _bootstrapInFlight;

  /// Démarrage cold (splash) : affiche l’état loading et redirige via router.
  Future<void> bootstrap() => _runBootstrap(showLoading: true);

  /// Recharge session sans repasser par l’écran splash (post-PIN, refresh UI).
  Future<void> refresh() => _runBootstrap(showLoading: false);

  Future<void> _runBootstrap({required bool showLoading}) {
    final existing = _bootstrapInFlight;
    if (existing != null) return existing;
    // Stocker le Future renvoyé (avec whenComplete) pour que les appels
    // concurrents reçoivent strictement le même objet Future.
    late final Future<void> future;
    future = _bootstrapImpl(showLoading: showLoading).whenComplete(() {
      if (identical(_bootstrapInFlight, future)) {
        _bootstrapInFlight = null;
      }
    });
    _bootstrapInFlight = future;
    return future;
  }

  Future<void> _bootstrapImpl({required bool showLoading}) async {
    if (showLoading) {
      if (!mounted) return;
      state = state.copyWith(isLoading: true);
    }
    final result = await _service.bootstrap();
    if (!mounted) return;
    final modules = _parseModules(result.business);
    state = SessionState(
      isLoading: false,
      isAuthenticated: result.isAuthenticated,
      needsOnboarding: result.needsOnboarding,
      business: result.business,
      user: result.user,
      performanceMode: result.performanceMode,
      biometricEnabled: result.biometricEnabled,
      activeModules: modules,
      subscription: result.subscription,
    );
    if (result.isAuthenticated && result.business?.isDemo != true) {
      // ignore: unawaited_futures
      refreshSubscription();
    }
  }

  List<String> _parseModules(Business? business) {
    if (business == null) return [];
    try {
      final list = (jsonDecode(business.modulesJson) as List).cast<String>();
      if (list.isNotEmpty) return list;
    } catch (_) {}
    return SectorModules.forSector(business.sector);
  }

  Future<SubscriptionInfo> refreshSubscription() async {
    final info = await _service.refreshSubscriptionFromCloud();
    if (!mounted) return info;
    state = state.copyWith(subscription: info);
    return info;
  }

  /// Jeton cloud de l'appareil (Bearer des routes de paiement), ou null.
  Future<String?> cloudSyncToken() => _service.currentCloudSyncToken();

  void setPerformanceMode(bool value) {
    state = state.copyWith(performanceMode: value);
    _service.setPerformanceMode(value);
  }

  Future<void> setBiometricEnabled(bool value) async {
    await _service.setBiometricEnabled(value);
    state = state.copyWith(biometricEnabled: value);
  }

  Future<void> logout() async {
    await _service.logout();
    if (!mounted) return;
    state = SessionState(
      isLoading: false,
      isAuthenticated: false,
      needsOnboarding: false,
      performanceMode: state.performanceMode,
      biometricEnabled: state.biometricEnabled,
      business: state.business,
      user: state.user,
      activeModules: state.activeModules,
      subscription: state.subscription,
    );
  }

  Future<void> lock() async {
    await _service.lock();
    if (!mounted) return;
    state = state.copyWith(isAuthenticated: false);
  }
}

final connectivityOnlineProvider = StreamProvider<bool>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.stateStream.map((s) => s != SyncConnectionState.offline);
});

final pendingSyncCountProvider = StreamProvider<int>((ref) {
  return ref.watch(syncEngineProvider).pendingCountStream;
});

final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return Stream<int>.value(0);
  return ref.watch(notificationServiceProvider).watchUnreadCount(business.id);
});
