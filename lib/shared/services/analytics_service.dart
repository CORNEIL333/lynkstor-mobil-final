import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/database/app_database.dart';
import '../../core/logging/app_logger.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/utils/id_generator.dart';
import 'analytics_local_store.dart';

/// Point d’entrée statique — les services métier peuvent tracer sans Riverpod.
class AppAnalytics {
  AppAnalytics._();

  static AnalyticsService? _bound;

  static void bind(AnalyticsService service) => _bound = service;
  static void unbind() => _bound = null;

  static void track(String name, {Map<String, Object?> properties = const {}}) {
    unawaited(_bound?.track(name, properties: properties) ?? Future.value());
  }
}

class TrialSnapshot {
  const TrialSnapshot({
    required this.salesCount,
    required this.soldFcfa,
    required this.productsCount,
    required this.catalogActivatedCount,
    required this.customersCount,
    required this.expensesCount,
    required this.eventCount,
    required this.pendingCount,
    required this.openDays,
    this.lastOpenAt,
    this.sector,
  });

  final int salesCount;
  final double soldFcfa;
  final int productsCount;
  final int catalogActivatedCount;
  final int customersCount;
  final int expensesCount;
  final int eventCount;
  final int pendingCount;
  final int openDays;
  final DateTime? lastOpenAt;
  final String? sector;

  Map<String, Object?> toJson() => {
    'salesCount': salesCount,
    'soldFcfa': soldFcfa,
    'productsCount': productsCount,
    'catalogActivatedCount': catalogActivatedCount,
    'customersCount': customersCount,
    'expensesCount': expensesCount,
    'eventCount': eventCount,
    'pendingCount': pendingCount,
    'openDays': openDays,
    'lastOpenAt': lastOpenAt?.toIso8601String(),
    'sector': sector,
  };
}

/// Analytique période test : events locaux, snapshot métier, envoi cloud.
class AnalyticsService {
  AnalyticsService({
    required this.db,
    required this.secure,
    http.Client? httpClient,
    AnalyticsLocalStore? localStore,
  }) : _http = httpClient ?? http.Client(),
       _store = localStore ?? AnalyticsLocalStore();

  final AppDatabase db;
  final SecureStorageService secure;
  final http.Client _http;
  final AnalyticsLocalStore _store;

  DateTime? _lastSnapshotAt;
  DateTime? _lastFlushAt;
  DateTime? _lastFolderWriteAt;
  bool _flushing = false;
  bool _writingFolder = false;
  Timer? _persistTimer;
  AnalyticsFolderResult? lastFolder;

  static const allowedEvents = {
    'app.opened',
    'app.background',
    'onboarding.completed',
    'screen.viewed',
    'sale.completed',
    'product.created',
    'catalog.opened',
    'catalog.activated',
    'customer.created',
    'expense.created',
    'debt.collected',
    'ai.used',
    'snapshot.daily',
    'error.captured',
    'analytics.exported',
  };

  Future<void> track(
    String name, {
    Map<String, Object?> properties = const {},
  }) async {
    if (!allowedEvents.contains(name)) return;
    try {
      final sanitized = <String, Object?>{};
      for (final entry in properties.entries) {
        final value = entry.value;
        if (value == null) continue;
        if (value is num || value is bool || value is String) {
          if (value is String && value.length > 120) {
            sanitized[entry.key] = value.substring(0, 120);
          } else {
            sanitized[entry.key] = value;
          }
        }
      }
      await db.insertAnalyticsEvent(
        id: IdGenerator.uuid(),
        name: name,
        propertiesJson: jsonEncode(sanitized),
        createdAt: DateTime.now(),
      );
      _scheduleFolderPersist();
    } catch (error, stack) {
      AppLogger.w('Analytics track failed for $name', error, stack);
    }
  }

  Future<TrialSnapshot> captureSnapshot({bool persist = true}) async {
    final businessId = await secure.getCurrentBusinessId();
    Business? business;
    if (businessId != null) {
      business = await db.getBusiness(businessId);
    }

    var salesCount = 0;
    var soldFcfa = 0.0;
    var productsCount = 0;
    var catalogActivated = 0;
    var customersCount = 0;
    var expensesCount = 0;
    var openDays = 0;
    DateTime? lastOpenAt;

    if (businessId != null) {
      final sales = await db.getSales(businessId, limit: 20000);
      final completed = sales.where((s) => s.status == 'completed');
      salesCount = completed.length;
      for (final sale in completed) {
        soldFcfa += sale.total;
      }
      final products = await db.getProducts(businessId);
      productsCount = products.length;
      catalogActivated = products
          .where((p) => (p.sku ?? '').startsWith('CAT-'))
          .length;
      customersCount = (await db.getCustomers(businessId)).length;
      expensesCount = (await db.getExpenses(businessId)).length;
    }

    openDays = await db.analyticsOpenDays();
    final recent = await db.recentAnalyticsEvents(limit: 80);
    for (final event in recent) {
      if (event['name'] == 'app.opened') {
        lastOpenAt = event['createdAt'] as DateTime;
        break;
      }
    }

    final snapshot = TrialSnapshot(
      salesCount: salesCount,
      soldFcfa: soldFcfa,
      productsCount: productsCount,
      catalogActivatedCount: catalogActivated,
      customersCount: customersCount,
      expensesCount: expensesCount,
      eventCount: await db.analyticsTotalCount(),
      pendingCount: await db.analyticsPendingCount(),
      openDays: openDays,
      lastOpenAt: lastOpenAt,
      sector: business?.sector,
    );

    if (persist) {
      final now = DateTime.now();
      final shouldStore =
          _lastSnapshotAt == null ||
          now.difference(_lastSnapshotAt!) > const Duration(hours: 6);
      if (shouldStore) {
        _lastSnapshotAt = now;
        await track('snapshot.daily', properties: snapshot.toJson());
      }
      await persistToDeviceFolder();
    }
    return snapshot;
  }

  Future<int> pendingCount() => db.analyticsPendingCount();

  Future<bool> flush({bool force = false}) async {
    if (_flushing) return false;
    final now = DateTime.now();
    if (!force &&
        _lastFlushAt != null &&
        now.difference(_lastFlushAt!) < const Duration(minutes: 2)) {
      return false;
    }
    _flushing = true;
    try {
      await persistToDeviceFolder(force: force);
      final pending = await db.pendingAnalyticsEvents();
      if (pending.isEmpty) return true;

      final snapshot = await captureSnapshot(persist: false);
      final installId = await _installId();
      final businessId = await secure.getCurrentBusinessId();
      final events = [
        for (final row in pending)
          {
            'id': row['id'],
            'name': row['name'],
            'properties': _decodeProps(row['propertiesJson'] as String),
            'createdAt': (row['createdAt'] as DateTime).toIso8601String(),
          },
      ];

      final payload = jsonEncode(
        structuredPayload(
          installId: installId,
          businessId: businessId,
          snapshot: snapshot,
          events: events,
        ),
      );

      final endpoints = <String>[
        if (AppConfig.analyticsIngestUrl.trim().isNotEmpty)
          AppConfig.analyticsIngestUrl.trim(),
        ...AppConfig.analyticsFallbackUrls,
      ];
      if (endpoints.isEmpty) {
        AppLogger.w(
          'Analytics Drive collector URL is empty. Data stays on device.',
        );
        return false;
      }
      var delivered = false;
      for (final endpoint in endpoints) {
        try {
          final ok = await _postJson(endpoint, payload);
          if (ok) {
            delivered = true;
            AppLogger.i(
              'Analytics flushed (${events.length} events) → $endpoint',
            );
            break;
          }
        } catch (error, stack) {
          AppLogger.w('Analytics flush error on $endpoint', error, stack);
        }
      }

      if (delivered) {
        await db.markAnalyticsSynced([
          for (final row in pending) row['id'] as String,
        ]);
        _lastFlushAt = now;
        return true;
      }
      return false;
    } catch (error, stack) {
      AppLogger.w('Analytics flush deferred', error, stack);
      return false;
    } finally {
      _flushing = false;
    }
  }

  Map<String, Object?> structuredPayload({
    required String installId,
    required String? businessId,
    required TrialSnapshot snapshot,
    required List<Map<String, Object?>> events,
  }) {
    return {
      'schema': 'lynkstor.trial.v1',
      'folderId': AppConfig.analyticsDriveFolderId,
      'app': AppConfig.appName,
      'appVersion': '${AppConfig.version}+${AppConfig.buildNumber}',
      'sentAt': DateTime.now().toIso8601String(),
      'installId': installId,
      'businessId': businessId,
      'sector': snapshot.sector,
      'boutique': {
        'install_id': installId,
        'secteur': snapshot.sector,
        'business_id': businessId,
        'app_version': '${AppConfig.version}+${AppConfig.buildNumber}',
        'ventes': snapshot.salesCount,
        'ca_fcfa': snapshot.soldFcfa,
        'produits': snapshot.productsCount,
        'produits_actives': snapshot.catalogActivatedCount,
        'clients': snapshot.customersCount,
        'depenses': snapshot.expensesCount,
        'jours_ouverts': snapshot.openDays,
        'dernier_ouverture': snapshot.lastOpenAt?.toIso8601String(),
        'nb_evenements': snapshot.eventCount,
      },
      'device': {
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
      },
      'snapshot': snapshot.toJson(),
      'events': events,
      'evenements': [
        for (final event in events)
          {
            'install_id': installId,
            'event_id': event['id'],
            'event_name': event['name'],
            'created_at': event['createdAt'],
            'properties_json': jsonEncode(event['properties'] ?? {}),
          },
      ],
    };
  }

  Future<bool> _postJson(String endpoint, String payload) async {
    final request = http.Request('POST', Uri.parse(endpoint))
      ..followRedirects = false
      ..headers['Content-Type'] = 'text/plain;charset=utf-8'
      ..body = payload;
    var streamed = await _http
        .send(request)
        .timeout(const Duration(seconds: 25));
    var status = streamed.statusCode;
    if (status == 301 || status == 302 || status == 303 || status == 307) {
      final location = streamed.headers['location'];
      if (location == null || location.isEmpty) return false;
      await streamed.stream.drain();
      final redirected = await _http
          .post(
            Uri.parse(location),
            headers: const {'Content-Type': 'text/plain;charset=utf-8'},
            body: payload,
          )
          .timeout(const Duration(seconds: 25));
      status = redirected.statusCode;
      if (status < 200 || status >= 300) {
        AppLogger.w('Analytics Drive POST redirected failed: $status');
        return false;
      }
      return _looksSuccessful(redirected.body, status);
    }
    final body = await streamed.stream.bytesToString();
    if (status < 200 || status >= 300) {
      AppLogger.w('Analytics Drive POST failed: $status $body');
      return false;
    }
    return _looksSuccessful(body, status);
  }

  bool _looksSuccessful(String body, int status) {
    if (status >= 200 && status < 300) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['status'] == 'error') return false;
      } catch (_) {}
      return true;
    }
    return false;
  }

  Future<String> exportJson() async {
    final snapshot = await captureSnapshot(persist: false);
    final events = await db.recentAnalyticsEvents(limit: 2000);
    final payload = jsonEncode(
      structuredPayload(
        installId: await _installId(),
        businessId: await secure.getCurrentBusinessId(),
        snapshot: snapshot,
        events: [
          for (final event in events)
            {
              'id': event['id'],
              'name': event['name'],
              'properties': _decodeProps(event['propertiesJson'] as String),
              'createdAt': (event['createdAt'] as DateTime).toIso8601String(),
            },
        ],
      ),
    );
    await track('analytics.exported', properties: {'bytes': payload.length});
    return payload;
  }

  Future<void> shareExport() async {
    final folder = await persistToDeviceFolder(force: true);
    final files = folder?.shareableFiles ?? const <String>[];
    final unique = <String>{};
    final toShare = <XFile>[];
    for (final path in files) {
      final name = path.split(Platform.pathSeparator).last;
      if (!unique.add(name)) continue;
      if (await File(path).exists()) {
        toShare.add(XFile(path, name: name));
      }
    }
    const shareNames = {
      'boutique.json',
      'resume.csv',
      'evenements.csv',
      'quotidien.csv',
      'usage.csv',
      'LISEZMOI.txt',
    };
    toShare.removeWhere((file) => !shareNames.contains(file.name));
    if (toShare.isNotEmpty) {
      await Share.shareXFiles(
        toShare,
        subject: 'Lynkstor — données période test',
      );
      return;
    }
    final payload = await exportJson();
    await Share.share(payload, subject: 'Lynkstor — données période test');
  }

  Future<AnalyticsFolderResult?> persistToDeviceFolder({
    bool force = false,
  }) async {
    if (_writingFolder) return lastFolder;
    final now = DateTime.now();
    if (!force &&
        _lastFolderWriteAt != null &&
        now.difference(_lastFolderWriteAt!) < const Duration(seconds: 12)) {
      return lastFolder;
    }
    _writingFolder = true;
    try {
      final snapshot = await captureSnapshot(persist: false);
      final installId = await _installId();
      final businessId = await secure.getCurrentBusinessId();
      final events = await db.recentAnalyticsEvents(limit: 5000);
      final eventMaps = <Map<String, Object?>>[
        for (final event in events)
          {
            'id': event['id'],
            'name': event['name'],
            'properties': _decodeProps(event['propertiesJson'] as String),
            'createdAt': event['createdAt'] as DateTime,
            'synced': event['synced'] == true,
          },
      ];
      final payload = structuredPayload(
        installId: installId,
        businessId: businessId,
        snapshot: snapshot,
        events: [
          for (final event in eventMaps)
            {
              'id': event['id'],
              'name': event['name'],
              'properties': event['properties'],
              'createdAt': (event['createdAt'] as DateTime).toIso8601String(),
            },
        ],
      );
      final counts = await db.analyticsEventCounts();
      final screens = <String, int>{};
      final errors = <Map<String, Object?>>[];
      for (final event in eventMaps) {
        final name = event['name'] as String? ?? '';
        final props = _asStringMap(event['properties']);
        if (name == 'screen.viewed') {
          final path = '${props['path'] ?? ''}';
          if (path.isEmpty) continue;
          screens[path] = (screens[path] ?? 0) + 1;
        }
        if (name == 'error.captured') {
          errors.add({
            'id': event['id'],
            'createdAt': (event['createdAt'] as DateTime).toIso8601String(),
            'properties': props,
          });
        }
      }
      final daily = await _dailyRows(businessId: businessId, events: eventMaps);
      final updatedAt = now.toIso8601String();
      final files = <String, String>{
        'LISEZMOI.txt': _readme(installId: installId, updatedAt: updatedAt),
        'manifest.json': const JsonEncoder.withIndent('  ').convert({
          'schema': 'lynkstor.trial.folder.v1',
          'folder': AppConfig.analyticsLocalFolderName,
          'updatedAt': updatedAt,
          'installId': installId,
          'app': AppConfig.appName,
          'appVersion': '${AppConfig.version}+${AppConfig.buildNumber}',
          'files': [
            'boutique.json',
            'evenements.json',
            'evenements.csv',
            'resume.csv',
            'quotidien.csv',
            'ecrans.csv',
            'usage.csv',
            'erreurs.json',
            'LISEZMOI.txt',
          ],
        }),
        'boutique.json': const JsonEncoder.withIndent('  ').convert(payload),
        'evenements.json': const JsonEncoder.withIndent('  ').convert({
          'installId': installId,
          'updatedAt': updatedAt,
          'events': [
            for (final event in eventMaps)
              {
                'id': event['id'],
                'name': event['name'],
                'createdAt': (event['createdAt'] as DateTime).toIso8601String(),
                'synced': event['synced'],
                'properties': event['properties'],
              },
          ],
        }),
        'evenements.csv': analyticsCsvTable(
          const ['created_at', 'event_name', 'synced', 'properties_json'],
          [
            for (final event in eventMaps.reversed)
              [
                (event['createdAt'] as DateTime).toIso8601String(),
                event['name'],
                event['synced'] == true ? 1 : 0,
                jsonEncode(event['properties']),
              ],
          ],
        ),
        'resume.csv': analyticsCsvTable(
          const ['cle', 'valeur'],
          [
            ['install_id', installId],
            ['business_id', businessId ?? ''],
            ['app_version', '${AppConfig.version}+${AppConfig.buildNumber}'],
            ['secteur', snapshot.sector ?? ''],
            ['ventes', snapshot.salesCount],
            ['ca_fcfa', snapshot.soldFcfa],
            ['produits', snapshot.productsCount],
            ['produits_actives', snapshot.catalogActivatedCount],
            ['clients', snapshot.customersCount],
            ['depenses', snapshot.expensesCount],
            ['jours_ouverts', snapshot.openDays],
            ['dernier_ouverture', snapshot.lastOpenAt?.toIso8601String() ?? ''],
            ['nb_evenements', snapshot.eventCount],
            ['evenements_en_attente', snapshot.pendingCount],
            ['mis_a_jour', updatedAt],
          ],
        ),
        'quotidien.csv': analyticsCsvTable(const [
          'date',
          'ouvertures',
          'ventes',
          'ca_fcfa',
          'encaisse_fcfa',
          'credit_fcfa',
          'ecrans',
          'erreurs',
        ], daily),
        'ecrans.csv': analyticsCsvTable(
          const ['chemin', 'vues'],
          [
            for (final entry
                in (screens.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value))))
              [entry.key, entry.value],
          ],
        ),
        'usage.csv': analyticsCsvTable(
          const ['event_name', 'count'],
          [
            for (final row in counts) [row['name'], row['count']],
          ],
        ),
        'erreurs.json': const JsonEncoder.withIndent('  ').convert({
          'installId': installId,
          'updatedAt': updatedAt,
          'errors': errors,
        }),
      };

      final result = await _store.writeFiles(files);
      lastFolder = result;
      _lastFolderWriteAt = now;
      AppLogger.i('Analytics folder updated → ${result.folderPath}');
      return result;
    } catch (error, stack) {
      AppLogger.w('Analytics folder persist failed', error, stack);
      return lastFolder;
    } finally {
      _writingFolder = false;
    }
  }

  void _scheduleFolderPersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 8), () {
      unawaited(persistToDeviceFolder());
    });
  }

  Future<List<List<Object?>>> _dailyRows({
    required String? businessId,
    required List<Map<String, Object?>> events,
  }) async {
    final byDay = <String, _DayAgg>{};

    void touch(String day) {
      byDay.putIfAbsent(day, _DayAgg.new);
    }

    for (final event in events) {
      final created = event['createdAt'] as DateTime?;
      if (created == null) continue;
      final key = _dayKey(created);
      touch(key);
      final name = event['name'] as String? ?? '';
      if (name == 'app.opened') byDay[key]!.openings++;
      if (name == 'screen.viewed') byDay[key]!.screens++;
      if (name == 'error.captured') byDay[key]!.errors++;
    }

    if (businessId != null) {
      final sales = await db.getSales(businessId, limit: 20000);
      for (final sale in sales.where((s) => s.status == 'completed')) {
        final key = _dayKey(sale.soldAt);
        touch(key);
        byDay[key]!.sales++;
        byDay[key]!.sold += sale.total;
        byDay[key]!.paid += sale.amountPaid;
        byDay[key]!.credit += sale.amountDue;
      }
    }

    final keys = byDay.keys.toList()..sort();
    return [
      for (final key in keys)
        [
          key,
          byDay[key]!.openings,
          byDay[key]!.sales,
          byDay[key]!.sold,
          byDay[key]!.paid,
          byDay[key]!.credit,
          byDay[key]!.screens,
          byDay[key]!.errors,
        ],
    ];
  }

  String _dayKey(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _readme({required String installId, required String updatedAt}) {
    return '''
Lynkstor — dossier données période test
=======================================

Mis à jour automatiquement par l'application.
Dernière écriture : $updatedAt
Installation      : $installId

Fichiers
--------
boutique.json     Synthèse boutique (ventes, CA, produits, jours ouverts)
evenements.json   Journal des actions de l'app
evenements.csv    Même journal, ouvrable dans Excel
resume.csv        Indicateurs en une colonne
quotidien.csv     Une ligne par jour (ouvertures, ventes, CA, crédit)
ecrans.csv        Écrans les plus ouverts
usage.csv         Comptage de chaque action
erreurs.json      Erreurs capturées
manifest.json     Date de mise à jour et identifiant

Aucune donnée sensible : pas de nom, téléphone, PIN ni mot de passe.

Récupération
------------
1. Fichiers → Documents ou Téléchargements → Lynkstor
2. Ou copier le dossier via USB
3. Ou Réglages → Données du test → Exporter le fichier
''';
  }

  Future<String> _installId() async {
    final existing = await secure.getDeviceId();
    if (existing != null && existing.isNotEmpty) return existing;
    final id = IdGenerator.uuid();
    await secure.setDeviceId(id);
    return id;
  }

  Map<String, Object?> _decodeProps(String raw) {
    try {
      return _asStringMap(jsonDecode(raw));
    } catch (_) {}
    return const {};
  }

  Map<String, Object?> _asStringMap(Object? raw) {
    if (raw is Map<String, Object?>) return raw;
    if (raw is Map) {
      return {
        for (final entry in raw.entries) entry.key.toString(): entry.value,
      };
    }
    return const {};
  }

  void dispose() {
    _persistTimer?.cancel();
    _http.close();
  }
}

class _DayAgg {
  int openings = 0;
  int sales = 0;
  double sold = 0;
  double paid = 0;
  double credit = 0;
  int screens = 0;
  int errors = 0;
}
