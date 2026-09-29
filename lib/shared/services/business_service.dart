import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/config/app_config.dart';
import '../../core/config/sector_modules.dart';
import '../../core/database/app_database.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/utils/id_generator.dart';
import '../../l10n/app_strings.dart';
import '../../core/logging/app_logger.dart';
import 'analytics_service.dart';
import 'cloud_registration_service.dart';

class BusinessCreationInput {
  BusinessCreationInput({
    required this.name,
    required this.ownerName,
    required this.phone,
    required this.password,
    required this.pin,
    this.city,
    this.neighborhood,
    this.sector = 'boutique',
    this.currency = 'FCFA',
    this.language = 'fr',
    this.modules = const [],
    this.isDemo = false,
    this.isRestore = false,
    this.activationCode,
  });

  final String name;
  final String ownerName;
  final String phone;
  final String password;
  final String pin;
  final String? city;
  final String? neighborhood;
  final String sector;
  final String currency;
  final String language;
  final List<String> modules;
  final bool isDemo;
  final bool isRestore;

  /// Code fourni par un agent Lynkstor (obligatoire hors démo).
  final String? activationCode;
}

class BusinessService {
  BusinessService({required this.db, required this.secure, required this.sync});

  final AppDatabase db;
  final SecureStorageService secure;
  final SyncEngine sync;

  Future<Business>? _creationInFlight;

  Future<Business> createBusiness(BusinessCreationInput input) {
    final activeCreation = _creationInFlight;
    if (activeCreation != null) return activeCreation;

    late final Future<Business> operation;
    operation = _createBusiness(input).whenComplete(() {
      if (identical(_creationInFlight, operation)) {
        _creationInFlight = null;
      }
    });
    _creationInFlight = operation;
    return operation;
  }

  Future<Business> _createBusiness(BusinessCreationInput input) async {
    final now = DateTime.now();
    var businessId = IdGenerator.uuid();
    var userId = IdGenerator.uuid();
    final deviceId = await _ensureDeviceId();
    final modules = input.modules.isNotEmpty
        ? input.modules
        : SectorModules.forSector(input.sector);

    // ——— Inscription cloud obligatoire hors démo ———
    if (!input.isDemo &&
        !input.isRestore &&
        AppConfig.requireAgentActivationCode) {
      final code = input.activationCode?.trim().toUpperCase() ?? '';
      if (code.isEmpty) {
        throw Exception(
          S.tr(
            'Un code d’activation Lynkstor est obligatoire pour créer un commerce.',
            'A Lynkstor activation code is required to create a business.',
          ),
        );
      }
      final pending = await secure.getPendingCloudRegistration();
      if (pending?['activationCode'] == code) {
        businessId = pending!['businessId']!;
        userId = pending['userId']!;
      } else {
        await secure.setPendingCloudRegistration(
          activationCode: code,
          businessId: businessId,
          userId: userId,
        );
      }
      final cloud = CloudRegistrationService();
      try {
        final reg = await cloud.register(
          activationCode: code,
          businessId: businessId,
          userId: userId,
          name: input.name.trim(),
          ownerName: input.ownerName.trim(),
          phone: input.phone.trim(),
          sector: input.sector,
          city: input.city,
          neighborhood: input.neighborhood,
        );
        businessId = reg.businessId;
        userId = reg.userId;
        await secure.setPendingCloudRegistration(
          activationCode: code,
          businessId: businessId,
          userId: userId,
        );
        await secure.setCloudSyncToken(reg.syncToken);
        await secure.setCloudSyncEndpoint(reg.syncEndpoint);
        // Persiste le forfait renvoyé par Supabase (validation abonnement)
        await secure.setSubscriptionCache(
          planName: reg.planName ?? 'STARTER',
          status: 'active',
          expiresAt: reg.expiresAt,
          licenseActive: true,
          source: 'cloud',
        );
        try {
          await sync.start(
            endpoint: reg.syncEndpoint,
            authToken: reg.syncToken,
            businessId: businessId,
            deviceId: deviceId,
          );
        } catch (error, stack) {
          AppLogger.w(
            'Cloud sync start deferred after registration',
            error,
            stack,
          );
        }
      } finally {
        cloud.dispose();
      }
    } else if (input.isDemo) {
      await secure.setSubscriptionCache(
        planName: 'DEMO',
        status: 'demo',
        licenseActive: true,
        source: 'demo',
      );
    } else if (input.isRestore) {
      await secure.setSubscriptionCache(
        planName: 'RESTAURÉ',
        status: 'local',
        licenseActive: true,
        source: 'restore',
      );
    } else {
      // Panel test / inscription libre : pas de clé agent, licence locale.
      await secure.setSubscriptionCache(
        planName: 'TEST',
        status: 'active',
        licenseActive: true,
        source: 'local',
      );
    }

    await db.transaction(() async {
      await db.insertBusiness(
        BusinessesCompanion.insert(
          id: businessId,
          name: input.name.trim(),
          ownerName: input.ownerName.trim(),
          phone: input.phone.trim(),
          city: Value(input.city),
          neighborhood: Value(input.neighborhood),
          sector: Value(input.sector),
          currency: Value(input.currency),
          language: Value(input.language),
          modulesJson: Value(jsonEncode(modules)),
          isDemo: Value(input.isDemo),
          mode: const Value('individual'),
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.insertUser(
        UsersCompanion.insert(
          id: userId,
          businessId: businessId,
          fullName: input.ownerName.trim(),
          phone: Value(input.phone.trim()),
          role: const Value('owner'),
          isOwner: const Value(true),
          permissionsJson: const Value('["*"]'),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // L'identifiant matériel est stable. Une reprise d'activation doit
      // réaffecter l'appareil au commerce courant, pas tenter un second INSERT.
      await db.upsertDevice(
        DevicesCompanion.insert(
          id: deviceId,
          businessId: businessId,
          userId: Value(userId),
          name: 'Appareil principal',
          createdAt: now,
        ),
      );

      // Catégories de dépenses par défaut
      for (final name in [
        'Loyer',
        'Transport',
        'Électricité',
        'Salaire',
        'Approvisionnement',
        'Divers',
      ].indexed) {
        await db
            .into(db.expenseCategories)
            .insertOnConflictUpdate(
              ExpenseCategoriesCompanion.insert(
                id: 'default-expense-$businessId-${name.$1}',
                businessId: businessId,
                name: name.$2,
                isFavorite: Value(
                  name.$2 == 'Divers' || name.$2 == 'Transport',
                ),
                createdAt: now,
              ),
            );
      }

      await db.insertAudit(
        AuditLogsCompanion.insert(
          id: 'onboarding-$businessId',
          businessId: businessId,
          userId: Value(userId),
          deviceId: Value(deviceId),
          action: input.isDemo
              ? 'business.created_demo'
              : input.isRestore
              ? 'business.created_restore'
              : AppConfig.requireAgentActivationCode
              ? 'business.created_cloud'
              : 'business.created_local',
          entityType: const Value('business'),
          entityId: Value(businessId),
          createdAt: now,
        ),
      );
    });

    await secure.setPassword(input.password);
    await secure.setPin(input.pin);
    await secure.setCurrentBusinessId(businessId);
    await secure.setCurrentUserId(userId);
    await secure.setOnboardingDone(true);
    await secure.setSessionToken('local_${now.millisecondsSinceEpoch}');
    await secure.setDeviceId(deviceId);
    await secure.clearPendingCloudRegistration();
    final createdBusiness = (await db.getBusiness(businessId))!;

    try {
      await sync.enqueue(
        businessId: businessId,
        entityType: 'business',
        entityId: businessId,
        operation: 'create',
        payload: createdBusiness.toJson(),
        userId: userId,
        deviceId: deviceId,
      );
      // La synchronisation est best-effort : le commerce local est déjà créé.
      await sync.processQueue();
    } catch (error, stack) {
      AppLogger.w(
        'Initial business sync deferred; local onboarding remains valid',
        error,
        stack,
      );
    }

    AppLogger.audit('business.created', userId: userId, entityId: businessId);
    AppAnalytics.track(
      'onboarding.completed',
      properties: {
        'sector': input.sector,
        'demo': input.isDemo,
      },
    );
    return createdBusiness;
  }

  Future<String> _ensureDeviceId() async {
    final existing = await secure.getDeviceId();
    if (existing != null) return existing;
    final id = IdGenerator.uuid();
    await secure.setDeviceId(id);
    return id;
  }

  Future<void> markOnboardingDone() => secure.setOnboardingDone(true);
}
