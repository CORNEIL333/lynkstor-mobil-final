import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/security/secure_storage_service.dart';

class CloudBackupInfo {
  const CloudBackupInfo({
    required this.id,
    required this.fileName,
    required this.checksum,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String fileName;
  final String checksum;
  final int sizeBytes;
  final DateTime createdAt;

  factory CloudBackupInfo.fromJson(Map<String, dynamic> json) {
    return CloudBackupInfo(
      id: json['id'] as String,
      fileName: json['file_name'] as String,
      checksum: json['checksum'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class CloudBackupService {
  CloudBackupService({
    required this.db,
    required this.secure,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final AppDatabase db;
  final SecureStorageService secure;
  final http.Client _client;

  Future<void> upload(BackupRecord record) async {
    final file = File(record.filePath);
    if (!await file.exists()) {
      throw const BackupException('Fichier de sauvegarde local introuvable.');
    }
    final auth = await _auth();
    final ticket = await _jsonRequest(
      'POST',
      auth.uri('/backups/upload-ticket'),
      auth.token,
      {
        'id': record.id,
        'fileName': record.fileName,
        'checksum': record.checksum,
        'sizeBytes': record.sizeBytes,
      },
    );
    final signedUrl = ticket['signedUrl'];
    if (signedUrl is! String || signedUrl.isEmpty) {
      throw const BackupException('Ticket de sauvegarde cloud invalide.');
    }

    final request = http.StreamedRequest('PUT', Uri.parse(signedUrl))
      ..contentLength = record.sizeBytes
      ..headers['content-type'] = 'application/octet-stream'
      ..headers['x-upsert'] = 'false';
    final responseFuture = _client.send(request);
    await request.sink.addStream(file.openRead());
    await request.sink.close();
    final response = await responseFuture.timeout(const Duration(minutes: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw BackupException(
        'Dépôt cloud refusé (${response.statusCode}) : $body',
      );
    }

    await _jsonRequest('POST', auth.uri('/backups/complete'), auth.token, {
      'id': record.id,
    });
    await (db.update(db.backupRecords)
          ..where((row) => row.id.equals(record.id)))
        .write(const BackupRecordsCompanion(destination: Value('local+cloud')));
  }

  Future<List<CloudBackupInfo>> list() async {
    final auth = await _auth();
    final body = await _jsonRequest(
      'GET',
      auth.uri('/backups'),
      auth.token,
      null,
    );
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) => CloudBackupInfo.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<String> download(CloudBackupInfo info) async {
    final auth = await _auth();
    final ticket = await _jsonRequest(
      'POST',
      auth.uri('/backups/download-ticket'),
      auth.token,
      {'id': info.id},
    );
    final signedUrl = ticket['signedUrl'];
    if (signedUrl is! String || signedUrl.isEmpty) {
      throw const BackupException('Ticket de téléchargement cloud invalide.');
    }
    final response = await _client
        .send(http.Request('GET', Uri.parse(signedUrl)))
        .timeout(const Duration(minutes: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackupException(
        'Téléchargement cloud refusé (${response.statusCode}).',
      );
    }
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'backups'));
    await directory.create(recursive: true);
    final temporary = File(p.join(directory.path, '.${info.id}.download'));
    final sink = temporary.openWrite();
    await response.stream.pipe(sink);
    final length = await temporary.length();
    final checksum = sha256.convert(await temporary.readAsBytes()).toString();
    if (length != info.sizeBytes || checksum != info.checksum) {
      await temporary.delete();
      throw const BackupException(
        'La sauvegarde cloud téléchargée est incomplète ou altérée.',
      );
    }
    final target = File(p.join(directory.path, 'cloud_${info.fileName}'));
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    return target.path;
  }

  Future<_CloudAuth> _auth() async {
    final endpoint = await secure.getCloudSyncEndpoint();
    final token = await secure.getCloudSyncToken();
    if (endpoint == null ||
        endpoint.isEmpty ||
        token == null ||
        token.isEmpty) {
      throw const BackupException(
        'Activez la synchronisation cloud avant la sauvegarde en ligne.',
      );
    }
    final endpointUri = Uri.parse(endpoint);
    final marker = endpointUri.path.indexOf('/api/v1/');
    if (marker < 0) {
      throw const BackupException('Adresse cloud invalide.');
    }
    final base = endpointUri.replace(
      path: endpointUri.path.substring(0, marker + '/api/v1'.length),
      query: null,
      fragment: null,
    );
    return _CloudAuth(base, token);
  }

  Future<Map<String, dynamic>> _jsonRequest(
    String method,
    Uri uri,
    String token,
    Map<String, dynamic>? body,
  ) async {
    final request = http.Request(method, uri)
      ..headers['authorization'] = 'Bearer $token'
      ..headers['content-type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 45));
    final text = await response.stream.bytesToString();
    Map<String, dynamic> decoded = {};
    try {
      decoded = Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackupException(
        decoded['message']?.toString() ??
            'Erreur cloud (${response.statusCode}).',
      );
    }
    return decoded;
  }
}

class _CloudAuth {
  const _CloudAuth(this.base, this.token);

  final Uri base;
  final String token;

  Uri uri(String suffix) => base.replace(path: '${base.path}$suffix');
}
