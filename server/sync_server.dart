import 'dart:convert';
import 'dart:io';

/// Serveur de synchronisation HTTP autonome de référence pour KUMBA Business.
/// Gère la réception des requêtes de synchronisation et la persistance des événements.
void main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 8080 : 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln(
    '🚀 KUMBA Sync Server running on '
    'http://${server.address.host}:${server.port}',
  );

  final syncedItems = <String, Map<String, dynamic>>{};

  await for (HttpRequest request in server) {
    try {
      final response = request.response;
      response.headers.add('Access-Control-Allow-Origin', '*');
      response.headers.add(
        'Access-Control-Allow-Methods',
        'GET, POST, OPTIONS',
      );
      response.headers.add(
        'Access-Control-Allow-Headers',
        'Content-Type, Authorization, X-Idempotency-Key',
      );

      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.ok;
        await response.close();
        continue;
      }

      final path = request.uri.path;

      if (path == '/health') {
        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'status': 'ok',
            'service': 'KUMBA Sync Server',
            'version': '1.0.0',
          }),
        );
        await response.close();
        continue;
      }

      if (request.method == 'POST' &&
          (path == '/api/v1/sync/push' || path == '/sync')) {
        final body = await utf8.decoder.bind(request).join();
        final data = jsonDecode(body) as Map<String, dynamic>;

        final id =
            (data['id'] ??
                    data['entityId'] ??
                    DateTime.now().millisecondsSinceEpoch)
                .toString();
        syncedItems[id] = data;

        stdout.writeln(
          '📦 [Sync Server] Received item: $id '
          'entityType=${data['entityType']} operation=${data['operation']}',
        );

        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'status': 'success',
            'id': id,
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );
        await response.close();
        continue;
      }

      if (request.method == 'GET' &&
          (path == '/api/v1/sync/pull' || path == '/sync/pull')) {
        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'status': 'success',
            'items': syncedItems.values.toList(),
            'count': syncedItems.length,
          }),
        );
        await response.close();
        continue;
      }

      response.statusCode = HttpStatus.notFound;
      response.write(jsonEncode({'error': 'Not found'}));
      await response.close();
    } catch (e) {
      stderr.writeln('❌ [Sync Server Error]: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'error': e.toString()}));
      await request.response.close();
    }
  }
}
