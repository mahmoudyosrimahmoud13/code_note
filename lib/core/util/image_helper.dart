import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// The folder for saved images. Uses Documents when the system has one,
/// otherwise the app's own data folder (some Linux setups have no Documents).
Future<Directory> imagesBaseDir() async {
  try {
    return await getApplicationDocumentsDirectory();
  } catch (_) {
    return await getApplicationSupportDirectory();
  }
}

class ImageHelper {
  static Future<String> persistImage(String tempPath) async {
    final File tempFile = File(tempPath);
    if (!await tempFile.exists()) return tempPath;

    final Directory appDocDir = await imagesBaseDir();
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
