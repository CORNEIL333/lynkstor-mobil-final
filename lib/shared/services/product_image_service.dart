import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/id_generator.dart';

/// Stocke les photos produit dans le dossier privé de l'application.
class ProductImageService {
  ProductImageService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<String?> pickAndPersist({
    required String businessId,
    required ImageSource source,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
    if (picked == null) return null;

    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      p.join(root.path, 'product_images', _safeSegment(businessId)),
    );
    await directory.create(recursive: true);

    final extension = _safeExtension(p.extension(picked.path));
    final target = File(
      p.join(directory.path, '${IdGenerator.uuid()}$extension'),
    );
    await File(picked.path).copy(target.path);
    return target.path;
  }

  Future<void> deleteIfManaged(String? path) async {
    if (path == null || path.isEmpty) return;
    final root = await getApplicationDocumentsDirectory();
    final managedRoot = p.normalize(p.join(root.path, 'product_images'));
    final candidate = p.normalize(path);
    if (!p.isWithin(managedRoot, candidate)) return;
    final file = File(candidate);
    if (await file.exists()) await file.delete();
  }

  String _safeSegment(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  String _safeExtension(String raw) {
    final extension = raw.toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)
        ? extension
        : '.jpg';
  }
}
