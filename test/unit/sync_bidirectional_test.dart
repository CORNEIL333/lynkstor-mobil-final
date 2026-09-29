import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/sync/http_sync_client.dart';
import 'package:kumba_business/core/sync/remote_event_applier.dart';

Future<void> _insertBusiness(AppDatabase db) async {
  final now = DateTime.utc(2026, 7, 31);
  await db
      .into(db.businesses)
      .insert(
        BusinessesCompanion.insert(
          id: 'business-1',
          name: 'Commerce',
          ownerName: 'Awa',
          phone: '690000000',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

void main() {
  test('pull uses a monotonic cursor and decodes the server page', () async {
    late Uri requestedUri;
    late String? authorization;
    final client = HttpSyncClient(
      client: MockClient((request) async {
        requestedUri = request.url;
        authorization = request.headers['authorization'];
        return http.Response(
          jsonEncode({
            'status': 'success',
            'items': [
              {
                'id': 'event-42',
                'businessId': 'business-1',
                'entityType': 'product',
                'entityId': 'product-1',
                'operation': 'update',
                'payload': {'name': 'Café', 'version': 2},
                'createdAt': '2026-07-31T12:00:00.000Z',
                'serverSeq': 42,
                'entityVersion': 2,
                'deviceId': 'device-2',
              },
            ],
            'nextCursor': 42,
            'hasMore': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final page = await client.pull(
      pushEndpointUrl:
          'https://example.test/functions/v1/lynkstor-api/api/v1/sync/push',
      businessId: 'business-1',
      cursor: 17,
      authToken: 'device-token',
      deviceId: 'device-1',
    );

    expect(requestedUri.path, endsWith('/api/v1/sync/pull'));
    expect(requestedUri.queryParameters['cursor'], '17');
    expect(requestedUri.queryParameters['deviceId'], 'device-1');
    expect(authorization, 'Bearer device-token');
    expect(page?.nextCursor, 42);
    expect(page?.items.single.entityVersion, 2);
    client.dispose();
  });

  test('remote product updates are versioned and never re-enqueued', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await _insertBusiness(db);
    final applier = RemoteEventApplier(db);
    final now = DateTime.utc(2026, 7, 31, 12);

    await applier.apply(
      RemoteSyncEvent(
        id: 'event-2',
        businessId: 'business-1',
        entityType: 'product',
        entityId: 'product-1',
        operation: 'create',
        payload: {
          'id': 'product-1',
          'businessId': 'business-1',
          'name': 'Café premium',
          'salePrice': 2500.0,
          'costPrice': 1800.0,
          'stockQty': 8.0,
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'version': 2,
          'isDeleted': false,
        },
        serverSeq: 2,
        entityVersion: 2,
        createdAt: now,
      ),
    );
    await applier.apply(
      RemoteSyncEvent(
        id: 'event-1',
        businessId: 'business-1',
        entityType: 'product',
        entityId: 'product-1',
        operation: 'update',
        payload: {'name': 'Ancien nom', 'version': 1},
        serverSeq: 3,
        entityVersion: 1,
        createdAt: now.add(const Duration(seconds: 1)),
      ),
    );

    final product = await (db.select(
      db.products,
    )..where((row) => row.id.equals('product-1'))).getSingle();
    final queued = await db.select(db.syncQueue).get();
    expect(product.name, 'Café premium');
    expect(product.version, 2);
    expect(queued, isEmpty);
  });

  test('remote tombstone hides a product without deleting history', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await _insertBusiness(db);
    final now = DateTime.utc(2026, 7, 31, 12);
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'product-1',
            businessId: 'business-1',
            name: 'Café',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await RemoteEventApplier(db).apply(
      RemoteSyncEvent(
        id: 'event-delete',
        businessId: 'business-1',
        entityType: 'product',
        entityId: 'product-1',
        operation: 'delete',
        payload: const {},
        serverSeq: 5,
        entityVersion: 3,
        createdAt: now.add(const Duration(minutes: 1)),
      ),
    );

    final product = await (db.select(
      db.products,
    )..where((row) => row.id.equals('product-1'))).getSingle();
    expect(product.isDeleted, isTrue);
    expect(product.isActive, isFalse);
    expect(product.version, 3);
  });
}
