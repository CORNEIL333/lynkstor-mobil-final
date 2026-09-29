import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kumba_business/core/sync/http_sync_client.dart';

void main() {
  test('pushBatch sends all queued changes in one HTTP transaction', () async {
    var requestCount = 0;
    final transport = MockClient((request) async {
      requestCount++;
      expect(request.method, 'POST');
      expect(request.headers['authorization'], 'Bearer device-token');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['items'], hasLength(2));
      return http.Response('{"status":"success","count":2}', 201);
    });
    final client = HttpSyncClient(client: transport);

    final success = await client.pushBatch(
      endpointUrl: 'https://example.test/api/v1/sync/push',
      authToken: 'device-token',
      items: [
        {
          'id': 'event-1',
          'businessId': 'business-1',
          'entityType': 'supplier',
          'entityId': 'supplier-1',
          'operation': 'create',
          'payload': {'name': 'Fournisseur A'},
        },
        {
          'id': 'event-2',
          'businessId': 'business-1',
          'entityType': 'attendance',
          'entityId': 'attendance-1',
          'operation': 'create',
          'payload': {'type': 'check_in'},
        },
      ],
    );

    expect(success, isTrue);
    expect(requestCount, 1);
    client.dispose();
  });
}
