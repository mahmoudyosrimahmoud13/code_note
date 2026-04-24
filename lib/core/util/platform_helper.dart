import 'package:flutter/foundation.dart';
import 'dart:io';

class PlatformHelper {
  static bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  static bool get isWeb => kIsWeb;
  static bool get isDesktopOrWeb => isDesktop || isWeb;
}
