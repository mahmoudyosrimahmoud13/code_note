import '../../domain/entities/settings.dart';

class SettingsModel extends SettingsEntity {
  const SettingsModel({
    required super.userName,
    required super.userHandle,
    super.profileImagePath,
    required super.themeMode,
    required super.fontSizeMultiplier,
    super.hasCompletedOnboarding,
    super.lastSelectedIndex,
  });

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      userName: json['userName'] ?? 'User Name',
      userHandle: json['userHandle'] ?? '@username',
      profileImagePath: json['profileImagePath'],
      themeMode: json['themeMode'] ?? 'system',
      fontSizeMultiplier: (json['fontSizeMultiplier'] ?? 1.0).toDouble(),
      hasCompletedOnboarding: json['hasCompletedOnboarding'] ?? false,
      lastSelectedIndex: json['lastSelectedIndex'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userName': userName,
      'userHandle': userHandle,
      'profileImagePath': profileImagePath,
      'themeMode': themeMode,
      'fontSizeMultiplier': fontSizeMultiplier,
      'hasCompletedOnboarding': hasCompletedOnboarding,
      'lastSelectedIndex': lastSelectedIndex,
    };
  }

  factory SettingsModel.fromEntity(SettingsEntity entity) {
    return SettingsModel(
      userName: entity.userName,
      userHandle: entity.userHandle,
      profileImagePath: entity.profileImagePath,
      themeMode: entity.themeMode,
      fontSizeMultiplier: entity.fontSizeMultiplier,
      hasCompletedOnboarding: entity.hasCompletedOnboarding,
      lastSelectedIndex: entity.lastSelectedIndex,
    );
  }

  factory SettingsModel.defaultSettings() {
    return const SettingsModel(
      userName: 'User Name',
      userHandle: '@username',
      themeMode: 'system',
      fontSizeMultiplier: 1.0,
      hasCompletedOnboarding: false,
      lastSelectedIndex: 0,
    );
  }
}
