import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Saved data for runnable notes ("mini apps"), one small key-value map per
/// note. Pages save with `localStorage` or `codenote.storage`, and the data
/// stays on this device and travels in backups.
class MiniAppStorage {
  MiniAppStorage._();
  static final MiniAppStorage instance = MiniAppStorage._();

  static const _boxName = 'miniAppData';

  /// The most one note may store, so a buggy page can't fill the device.
  static const maxBytes = 1024 * 1024;

  Future<Box> _box() => Hive.isBoxOpen(_boxName)
      ? Future.value(Hive.box(_boxName))
      : Hive.openBox(_boxName);

  /// Checks and cleans what a page sent. Returns null if it isn't a map of
  /// text values or is too big.
  static Map<String, String>? decode(String body) {
    if (utf8.encode(body).length > maxBytes) return null;
    try {
      final raw = json.decode(body);
      if (raw is! Map) return null;
      return {
        for (final e in raw.entries)
          if (e.value != null) e.key.toString(): e.value.toString(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> load(String noteId) async {
    final raw = (await _box()).get(noteId);
    if (raw is! String) return {};
    return decode(raw) ?? {};
  }

  Future<bool> save(String noteId, Map<String, String> data) async {
    final box = await _box();
    if (data.isEmpty) {
      await box.delete(noteId);
      return true;
    }
    final encoded = json.encode(data);
    if (utf8.encode(encoded).length > maxBytes) return false;
    await box.put(noteId, encoded);
    return true;
  }

  Future<void> clear(String noteId) async => (await _box()).delete(noteId);

  Future<bool> hasData(String noteId) async => (await _box()).containsKey(noteId);

  /// Everything, for backups: note id to its map.
  Future<Map<String, Map<String, String>>> exportAll() async {
    final box = await _box();
    return {
      for (final key in box.keys)
        if (box.get(key) is String) key.toString(): decode(box.get(key) as String) ?? {},
    };
  }

  /// Restores from a backup. Keeps what this device already has for a note.
  Future<int> importAll(Map<String, dynamic> all) async {
    final box = await _box();
    var count = 0;
    for (final e in all.entries) {
      if (box.containsKey(e.key) || e.value is! Map) continue;
      final map = {
        for (final kv in (e.value as Map).entries) kv.key.toString(): kv.value.toString(),
      };
      if (await save(e.key, map)) count++;
    }
    return count;
  }
}
