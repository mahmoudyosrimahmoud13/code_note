import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings_model.dart';

abstract class SettingsLocalDataSource {
  Future<SettingsModel> getSettings();
  Future<void> cacheSettings(SettingsModel settingsToCache);
}

class SettingsLocalDataSourceImpl implements SettingsLocalDataSource {
  final SharedPreferences sharedPreferences;
  static const CACHED_SETTINGS = 'CACHED_SETTINGS';

  SettingsLocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<SettingsModel> getSettings() async {
    final jsonString = sharedPreferences.getString(CACHED_SETTINGS);
    if (jsonString != null) {
      return SettingsModel.fromJson(json.decode(jsonString));
    } else {
      return SettingsModel.defaultSettings();
    }
  }

  @override
  Future<void> cacheSettings(SettingsModel settingsToCache) {
    return sharedPreferences.setString(
      CACHED_SETTINGS,
      json.encode(settingsToCache.toJson()),
    );
  }
}
