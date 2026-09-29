import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';

class AnalyticsFolderResult {
  const AnalyticsFolderResult({
    required this.folderPath,
    this.publicFolderPath,
    this.files = const [],
  });

  final String folderPath;
  final String? publicFolderPath;
  final List<String> files;

  List<String> get shareableFiles => files
      .where(
        (path) =>
            path.endsWith('.json') ||
            path.endsWith('.csv') ||
            path.endsWith('.txt'),
      )
      .toList(growable: false);
}

/// Écrit le dossier analytics sur l’appareil (app + Documents/Téléchargements).
class AnalyticsLocalStore {
  AnalyticsLocalStore({
    Future<Directory> Function()? documentsDirectoryProvider,
    Future<Directory?> Function()? externalDirectoryProvider,
    Future<String?> Function(String name, String sourcePath)? publicFileWriter,
    Future<String?> Function()? publicFolderPathProvider,
  }) : _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _externalDirectoryProvider =
           externalDirectoryProvider ?? getExternalStorageDirectory,
       _publicFileWriter = publicFileWriter ?? _channelWriteFile,
       _publicFolderPathProvider =
           publicFolderPathProvider ?? _channelFolderPath;

  static const _channel = MethodChannel(
    'com.kumba.kumba_business/analytics_folder',
  );

  final Future<Directory> Function() _documentsDirectoryProvider;
  final Future<Directory?> Function() _externalDirectoryProvider;
  final Future<String?> Function(String name, String sourcePath)
  _publicFileWriter;
  final Future<String?> Function() _publicFolderPathProvider;

  Future<AnalyticsFolderResult> writeFiles(Map<String, String> files) async {
    final folders = await _resolvePrivateFolders();
    if (folders.isEmpty) {
      throw StateError('Aucun dossier analytics disponible sur cet appareil.');
    }

    final written = <String>[];
    for (final folder in folders) {
      for (final entry in files.entries) {
        final file = File(p.join(folder.path, entry.key));
        await file.writeAsString(entry.value, encoding: utf8, flush: true);
        written.add(file.path);
      }
    }

    String? publicPath;
    try {
      publicPath = await _publicFolderPathProvider();
      final primary = folders.first;
      for (final name in files.keys) {
        final source = File(p.join(primary.path, name));
        final path = await _publicFileWriter(name, source.path);
        if (path != null && path.isNotEmpty) {
          publicPath ??= path.contains('://') ? publicPath : p.dirname(path);
        }
      }
    } catch (error, stack) {
      AppLogger.w('Public analytics folder write skipped', error, stack);
    }

    return AnalyticsFolderResult(
      folderPath: folders.first.path,
      publicFolderPath: publicPath,
      files: written,
    );
  }

  Future<List<Directory>> _resolvePrivateFolders() async {
    final dirs = <Directory>[];
    final seen = <String>{};

    Future<void> add(Directory dir) async {
      final normalized = p.normalize(dir.path);
      if (!seen.add(normalized)) return;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      dirs.add(dir);
    }

    final documents = await _documentsDirectoryProvider();
    await add(
      Directory(p.join(documents.path, AppConfig.analyticsLocalFolderName)),
    );

    try {
      final external = await _externalDirectoryProvider();
      if (external != null) {
        await add(
          Directory(p.join(external.path, AppConfig.analyticsLocalFolderName)),
        );
      }
    } catch (error, stack) {
      AppLogger.w('External analytics folder skipped', error, stack);
    }

    return dirs;
  }

  static Future<String?> _channelWriteFile(
    String name,
    String sourcePath,
  ) async {
    try {
      final result = await _channel.invokeMethod<dynamic>('writeFile', {
        'name': name,
        'path': sourcePath,
      });
      if (result is Map) {
        return result['path']?.toString();
      }
      if (result is String && result.isNotEmpty) return result;
    } on MissingPluginException {
      return null;
    } catch (error, stack) {
      AppLogger.w('Analytics public writeFile failed', error, stack);
    }
    return null;
  }

  static Future<String?> _channelFolderPath() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('folderPath');
      if (result is Map) return result['path']?.toString();
      if (result is String && result.isNotEmpty) return result;
    } on MissingPluginException {
      return null;
    } catch (error, stack) {
      AppLogger.w('Analytics public folderPath failed', error, stack);
    }
    return null;
  }
}

String analyticsCsvCell(Object? value) {
  final text = '${value ?? ''}';
  if (text.contains(',') ||
      text.contains('"') ||
      text.contains('\n') ||
      text.contains('\r')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

String analyticsCsvTable(List<String> headers, List<List<Object?>> rows) {
  final buffer = StringBuffer('\uFEFF');
  buffer.writeln(headers.map(analyticsCsvCell).join(','));
  for (final row in rows) {
    buffer.writeln(row.map(analyticsCsvCell).join(','));
  }
  return buffer.toString();
}
