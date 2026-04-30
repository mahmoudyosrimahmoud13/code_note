import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/settings_model.dart';

abstract class SettingsLocalDataSource {
  Future<SettingsModel> getSettings();
  Future<void> cacheSettings(SettingsModel settingsToCache);
  Future<void> resetData();
}

class SettingsLocalDataSourceImpl implements SettingsLocalDataSource {
  final Box box;
  static const cachedSettingsKey = 'CACHED_SETTINGS';

  SettingsLocalDataSourceImpl({required this.box});

  @override
  Future<SettingsModel> getSettings() async {
    final jsonString = box.get(cachedSettingsKey);
    if (jsonString != null) {
      return SettingsModel.fromJson(json.decode(jsonString));
    } else {
      return SettingsModel.defaultSettings();
    }
  }

  @override
  Future<void> cacheSettings(SettingsModel settingsToCache) async {
    await box.put(
      cachedSettingsKey,
      json.encode(settingsToCache.toJson()),
    );
  }

  @override
  Future<void> resetData() async {
    // 1. Clear dynamic chat message boxes
    // We try to find all chat IDs from the chatsBox before clearing it
    try {
      final chatsBox = Hive.box('chatsBox');
      for (var chatId in chatsBox.keys) {
        await Hive.deleteBoxFromDisk('chat_messages_$chatId');
      }
    } catch (_) {}

    // 2. Clear all structural boxes
    final boxesToClear = [
      'notesBox',
      'chatsBox',
      'messagesBox',
      'usersBox',
    ];

    for (final boxName in boxesToClear) {
      try {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).clear();
        } else {
          await Hive.deleteBoxFromDisk(boxName);
        }
      } catch (_) {}
    }

    // 3. Clear the settings box (which is 'box' in this class)
    await box.clear();
  }
}
