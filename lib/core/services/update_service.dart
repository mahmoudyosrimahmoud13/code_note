import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_info.dart';

/// A newer release found on GitHub.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.downloadUrl,
  });

  final String version;

  /// Release notes (Markdown).
  final String notes;

  /// The release page on GitHub.
  final String pageUrl;

  /// Direct download for this platform, when the release has one.
  final String? downloadUrl;
}

/// Checks GitHub Releases for a newer CodeNote.
///
/// This is the only automatic network request the app makes. It sends no
/// notes and no personal data, just a normal request for the public release
/// list, and it can be turned off in Settings.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const repo = 'mahmoudyosrimahmoud13/code_note';
  static const releasesPage = 'https://github.com/$repo/releases/latest';
  static const _boxName = 'appBox';
  static const _enabledKey = 'UPDATES_ENABLED';
  static const _lastCheckKey = 'UPDATES_LAST_CHECK';
  static const _skippedKey = 'UPDATES_SKIPPED_VERSION';

  Future<Box> _box() => Hive.isBoxOpen(_boxName)
      ? Future.value(Hive.box(_boxName))
      : Hive.openBox(_boxName);

  Future<bool> isEnabled() async => (await _box()).get(_enabledKey, defaultValue: true) == true;
  Future<void> setEnabled(bool on) async => (await _box()).put(_enabledKey, on);

  /// Remember "not now" for this version, so it isn't shown again.
  Future<void> skip(String version) async => (await _box()).put(_skippedKey, version);

  /// The automatic check: at most once a day, quiet on any error.
  Future<AppUpdate?> checkInBackground() async {
    try {
      if (!await isEnabled()) return null;
      final box = await _box();
      final last = DateTime.tryParse('${box.get(_lastCheckKey) ?? ''}');
      if (last != null && DateTime.now().difference(last) < const Duration(hours: 20)) {
        return null;
      }
      await box.put(_lastCheckKey, DateTime.now().toIso8601String());
      final update = await check();
      if (update == null || box.get(_skippedKey) == update.version) return null;
      return update;
    } catch (_) {
      return null;
    }
  }

  /// Asks GitHub now. Returns null when this is already the newest version.
  /// Throws when GitHub can't be reached (for the "Check now" button).
  Future<AppUpdate?> check() async {
    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
      headers: {'accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('GitHub answered ${res.statusCode}');
    }
    final body = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final tag = (body['tag_name'] ?? '').toString();
    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    if (!isNewer(latest, appVersion)) return null;

    final assets = (body['assets'] as List? ?? const [])
        .whereType<Map>()
        .map((a) => (a['browser_download_url'] ?? '').toString())
        .where((u) => u.isNotEmpty)
        .toList();
    return AppUpdate(
      version: latest,
      notes: (body['body'] ?? '').toString(),
      pageUrl: (body['html_url'] ?? releasesPage).toString(),
      downloadUrl: _assetForThisPlatform(assets),
    );
  }

  String? _assetForThisPlatform(List<String> urls) {
    if (kIsWeb) return null;
    String? pick(String ending) {
      for (final u in urls) {
        if (u.toLowerCase().endsWith(ending)) return u;
      }
      return null;
    }

    if (Platform.isAndroid) return pick('.apk');
    if (Platform.isWindows) return pick('-windows-x64.zip');
    if (Platform.isMacOS) return pick('-macos.zip');
    if (Platform.isLinux) return pick('.deb') ?? pick('.tar.gz');
    return null;
  }

  /// True when version [a] is newer than [b] ("1.10.0" > "1.9.2").
  static bool isNewer(String a, String b) {
    List<int> parts(String v) => v
        .split(RegExp(r'[.+-]'))
        .take(3)
        .map((p) => int.tryParse(p) ?? 0)
        .toList()
      ..addAll(const [0, 0, 0]);
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i] > y[i];
    }
    return false;
  }
}
