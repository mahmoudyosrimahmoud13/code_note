import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ImageHelper {
  static Future<String> persistImage(String tempPath) async {
    final File tempFile = File(tempPath);
    if (!await tempFile.exists()) return tempPath;

    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String imagesDir = p.join(appDocDir.path, 'persistent_images');
    await Directory(imagesDir).create(recursive: true);

    final String extension = p.extension(tempPath);
    final String fileName = '${const Uuid().v4()}$extension';
    final String newPath = p.join(imagesDir, fileName);

    await tempFile.copy(newPath);
    return newPath;
  }

  // Note: We can add more advanced compression here if we add flutter_image_compress
  // For now, we rely on ImagePicker's imageQuality, but this helper
  // ensures we have a consistent place for it.
}
