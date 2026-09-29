import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';

import '../config/app_config.dart';
import '../database/app_database.dart';
import '../logging/app_logger.dart';
import '../utils/id_generator.dart';
import 'http_sync_client.dart';
import 'remote_event_applier.dart';

enum SyncConnectionState { online, offline, syncing }

/// Moteur de synchronisation réel (file d'attente locale + états).
/// Avec backend configuré, les opérations sont poussées au serveur via HttpSyncClient.
class SyncEngine {
  SyncEngine(this._db, {HttpSyncClient? syncClient})
    : _syncClient = syncClient ?? HttpSyncClient(),
      _remoteApplier = RemoteEventApplier(_db);

  final AppDatabase _db;
  final HttpSyncClient _syncClient;
  final RemoteEventApplier _remoteApplier;
  final _stateController = StreamController<SyncConnectionState>.broadcast();
  final _pendingController = StreamController<int>.broadcast();

  StreamSubscription? _connectivitySub;
  Timer? _timer;
  SyncConnectionState _state = SyncConnectionState.offline;
  bool _hasBackend = false;
  bool _processing = false;
  bool _disposed = false;
  String? _endpoint;
  String? _authToken;
  String? _businessId;
  String? _deviceId;

  Stream<SyncConnectionState> get stateStream => _stateController.stream;
  Stream<int> get pendingCountStream => _pendingController.stream;
  SyncConnectionState get state => _state;
  bool get isOnline => _state != SyncConnectionState.offline;

  Future<void> start({
    String? endpoint,
    String? authToken,
    String? businessId,
    String? deviceId,
  }) async {
    if (_disposed) return;
    await _connectivitySub?.cancel();
    _timer?.cancel();
    _endpoint = endpoint;
    _authToken = authToken;
    _businessId = businessId;
    _deviceId = deviceId;
    _hasBackend =
        endpoint != null &&
        endpoint.isNotEmpty &&
        authToken != null &&
        authToken.isNotEmpty;

    try {
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();
      _updateConnection(results);
      _connectivitySub = connectivity.onConnectivityChanged.listen(
        _updateConnection,
        onError: (Object error, StackTrace stack) {
          AppLogger.w('Connectivity updates unavailable', error, stack);
          _setOffline();
        },
      );
    } catch (error, stack) {
      AppLogger.w('Connectivity check unavailable', error, stack);
      _setOffline();
    }
    _timer = Timer.periodic(AppConfig.syncInterval, (_) => processQueue());
    await _emitPending();
  }

  void setEndpoint(
    String? endpoint, {
    String? authToken,
    String? businessId,
    String? deviceId,
  }) {
    _endpoint = endpoint;
    _authToken = authToken;
    _businessId = businessId ?? _businessId;
    _deviceId = deviceId ?? _deviceId;
    _hasBackend =
        endpoint != null &&
        endpoint.isNotEmpty &&
        authToken != null &&
        authToken.isNotEmpty;
  }

  void _updateConnection(List<ConnectivityResult> results) {
    if (_disposed) return;
    final online = results.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet,
    );
    _state = online ? SyncConnectionState.online : SyncConnectionState.offline;
    if (!_stateController.isClosed) _stateController.add(_state);
    if (online) processQueue();
  }

  void _setOffline() {
    if (_disposed) return;
    _state = SyncConnectionState.offline;
    if (!_stateController.isClosed) _stateController.add(_state);
  }

  Future<void> enqueue({
    required String businessId,
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
    String? userId,
    String? deviceId,
    String? agencyId,
  }) async {
    final id = IdGenerator.uuid();
    await _db.enqueueSync(
      SyncQueueCompanion.insert(
        id: id,
        businessId: businessId,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        payloadJson: jsonEncode(payload),
        status: const Value('pending'),
        idempotencyKey: '${entityType}_${entityId}_$operation',
        agencyId: Value(agencyId),
        userId: Value(userId),
        deviceId: Value(deviceId),
        localCreatedAt: DateTime.now(),
      ),
    );
    await _emitPending();
    AppLogger.i('Sync enqueued $entityType/$entityId $operation');
  }

  Future<void> processQueue() async {
    if (_disposed || _processing || _state == SyncConnectionState.offline) {
      return;
    }
    if (!_hasBackend) {
      // Pas de backend : on marque comme local vérifié, pas de fausse sync.
      await _emitPending();
      return;
    }

    _processing = true;
    try {
      _state = SyncConnectionState.syncing;
      if (!_stateController.isClosed) _stateController.add(_state);

      final pending = await _db.getPendingSync();
      final eligible = pending.where(_isEligibleForRetry).take(50).toList();
      if (eligible.isNotEmpty && _endpoint != null && _endpoint!.isNotEmpty) {
        final batch = eligible.map(_serializeQueueItem).toList(growable: false);
        final success = await _syncClient.pushBatch(
          endpointUrl: _endpoint!,
          items: batch,
          authToken: _authToken,
        );
        await _db.transaction(() async {
          for (final item in eligible) {
            final attempts = item.attempts + 1;
            await (_db.update(
              _db.syncQueue,
            )..where((t) => t.id.equals(item.id))).write(
              SyncQueueCompanion(
                status: Value(
                  success
                      ? 'synced'
                      : attempts >= AppConfig.maxSyncRetries
                      ? 'error'
                      : 'pending',
                ),
                attempts: Value(attempts),
                lastError: Value(success ? null : 'HTTP batch sync failed'),
                lastAttemptAt: Value(DateTime.now()),
              ),
            );
          }
        });
      }
      await _pullRemote();

      _state = SyncConnectionState.online;
      if (!_stateController.isClosed) _stateController.add(_state);
      await _emitPending();
    } finally {
      _processing = false;
    }
  }

  bool _isEligibleForRetry(SyncQueueEntry item) {
    final lastAttempt = item.lastAttemptAt;
    if (lastAttempt == null || item.attempts == 0) return true;
    final delayMinutes = 1 << item.attempts.clamp(0, 6);
    return DateTime.now().difference(lastAttempt) >=
        Duration(minutes: delayMinutes);
  }

  Map<String, dynamic> _serializeQueueItem(SyncQueueEntry item) {
    Map<String, dynamic> payload = {};
    try {
      payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;
    } catch (_) {}
    return {
      'id': item.id,
      'businessId': item.businessId,
      'entityType': item.entityType,
      'entityId': item.entityId,
      'operation': item.operation,
      'payload': payload,
      'deviceId': item.deviceId ?? _deviceId,
      'localCreatedAt': item.localCreatedAt.toUtc().toIso8601String(),
      'entityVersion': (payload['version'] as num?)?.toInt() ?? item.version,
    };
  }

  Future<void> _pullRemote() async {
    final endpoint = _endpoint;
    final token = _authToken;
    final businessId = _businessId;
    if (endpoint == null ||
        endpoint.isEmpty ||
        token == null ||
        token.isEmpty ||
        businessId == null ||
        businessId.isEmpty) {
      return;
    }

    var cursor = await _readCursor(businessId);
    for (var pageIndex = 0; pageIndex < 10; pageIndex++) {
      final page = await _syncClient.pull(
        pushEndpointUrl: endpoint,
        businessId: businessId,
        cursor: cursor,
        authToken: token,
        deviceId: _deviceId,
      );
      if (page == null) return;
      for (final event in page.items) {
        if (event.businessId != businessId) {
          AppLogger.w(
            'Rejected cross-business sync event ${event.id}/${event.businessId}',
          );
          return;
        }
        try {
          await _remoteApplier.apply(event);
        } catch (error, stack) {
          AppLogger.e('Remote event apply failed ${event.id}', error, stack);
          return;
        }
      }
      if (page.nextCursor < cursor) {
        AppLogger.w('Rejected decreasing sync cursor ${page.nextCursor}');
        return;
      }
      cursor = page.nextCursor;
      await _writeCursor(businessId, cursor);
      if (!page.hasMore || page.items.isEmpty) return;
    }
  }

  Future<int> _readCursor(String businessId) async {
    final key = 'sync_cursor_$businessId';
    final setting = await (_db.select(
      _db.appSettings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    return int.tryParse(setting?.value ?? '') ?? 0;
  }

  Future<void> _writeCursor(String businessId, int cursor) async {
    final key = 'sync_cursor_$businessId';
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: key,
            value: cursor.toString(),
            businessId: Value(businessId),
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<int> pendingCount() async {
    final list = await _db.getPendingSync();
    return list.length;
  }

  Future<void> _emitPending() async {
    if (_disposed || _pendingController.isClosed) return;
    final count = await pendingCount();
    if (_disposed || _pendingController.isClosed) return;
    _pendingController.add(count);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _connectivitySub?.cancel();
    _timer?.cancel();
    _syncClient.dispose();
    await _stateController.close();
    await _pendingController.close();
  }
}
