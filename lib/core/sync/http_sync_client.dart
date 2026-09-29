import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logging/app_logger.dart';

class RemoteSyncEvent {
  const RemoteSyncEvent({
    required this.id,
    required this.businessId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.serverSeq,
    required this.entityVersion,
    required this.createdAt,
    this.deviceId,
  });

  final String id;
  final String businessId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final int serverSeq;
  final int entityVersion;
  final DateTime createdAt;
  final String? deviceId;

  factory RemoteSyncEvent.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return RemoteSyncEvent(
      id: json['id'] as String,
      businessId: json['businessId'] as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      operation: json['operation'] as String,
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const {},
      serverSeq: (json['serverSeq'] as num).toInt(),
      entityVersion: (json['entityVersion'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.parse(json['createdAt'] as String),
      deviceId: json['deviceId'] as String?,
    );
  }
}

class SyncPullPage {
  const SyncPullPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<RemoteSyncEvent> items;
  final int nextCursor;
  final bool hasMore;
}

class HttpSyncClient {
  HttpSyncClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<bool> pushBatch({
    required String endpointUrl,
    required List<Map<String, dynamic>> items,
    String? authToken,
  }) async {
    if (items.isEmpty) return true;
    try {
      final response = await _client
          .post(
            Uri.parse(endpointUrl),
            headers: {
              'Content-Type': 'application/json',
              if (authToken != null && authToken.isNotEmpty)
                'Authorization': 'Bearer $authToken',
              'X-Idempotency-Key': items.map((e) => e['id']).join(','),
            },
            body: jsonEncode({'items': items}),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        AppLogger.i('Sync batch push succeeded (${items.length} items)');
        return true;
      }
      AppLogger.w(
        'Sync batch push failed: ${response.statusCode} ${response.body}',
      );
      return false;
    } catch (error, stack) {
      AppLogger.e('Sync batch push failed', error, stack);
      return false;
    }
  }

  Future<bool> pushItem({
    required String endpointUrl,
    required String itemId,
    required String businessId,
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
    String? authToken,
    String? deviceId,
    DateTime? localCreatedAt,
    int entityVersion = 1,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(endpointUrl),
            headers: {
              'Content-Type': 'application/json',
              if (authToken != null && authToken.isNotEmpty)
                'Authorization': 'Bearer $authToken',
              'X-Idempotency-Key': itemId,
            },
            body: jsonEncode({
              'id': itemId,
              'businessId': businessId,
              'entityType': entityType,
              'entityId': entityId,
              'operation': operation,
              'payload': payload,
              'deviceId': deviceId,
              'localCreatedAt': localCreatedAt?.toUtc().toIso8601String(),
              'entityVersion': entityVersion,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        AppLogger.i('Sync push succeeded for $itemId');
        return true;
      }
      AppLogger.w(
        'Sync push failed for $itemId: ${response.statusCode} ${response.body}',
      );
      return false;
    } catch (error, stack) {
      AppLogger.e('Sync push failed for $itemId', error, stack);
      return false;
    }
  }

  Future<SyncPullPage?> pull({
    required String pushEndpointUrl,
    required String businessId,
    required int cursor,
    required String authToken,
    String? deviceId,
    int limit = 100,
  }) async {
    try {
      final pushUri = Uri.parse(pushEndpointUrl);
      final pullPath = pushUri.path.endsWith('/push')
          ? '${pushUri.path.substring(0, pushUri.path.length - 5)}/pull'
          : '${pushUri.path.replaceFirst(RegExp(r'/$'), '')}/pull';
      final uri = pushUri.replace(
        path: pullPath,
        queryParameters: {
          ...pushUri.queryParameters,
          'businessId': businessId,
          'cursor': cursor.toString(),
          'limit': limit.clamp(1, 500).toString(),
          if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
        },
      );
      final response = await _client
          .get(uri, headers: {'Authorization': 'Bearer $authToken'})
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.w(
          'Sync pull failed: ${response.statusCode} ${response.body}',
        );
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final body = Map<String, dynamic>.from(decoded);
      final rawItems = body['items'];
      if (rawItems is! List) return null;
      final items = rawItems
          .map(
            (item) => RemoteSyncEvent.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
      return SyncPullPage(
        items: items,
        nextCursor: (body['nextCursor'] as num?)?.toInt() ?? cursor,
        hasMore: body['hasMore'] == true,
      );
    } catch (error, stack) {
      AppLogger.e('Sync pull failed', error, stack);
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
