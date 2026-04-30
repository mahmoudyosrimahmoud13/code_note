import '../../domain/entities/settings.dart';

class SettingsModel extends SettingsEntity {
  const SettingsModel({
    required super.userName,
    required super.userHandle,
    super.profileImagePath,
    super.about,
    required super.themeMode,
    required super.fontSizeMultiplier,
    super.hasCompletedOnboarding,
    super.lastSelectedIndex,
    super.isRemoteMode,
  });

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      userName: json['userName'] ?? 'Local User',
      userHandle: json['userHandle'] ?? 'local',
      profileImagePath: json['profileImagePath'],
      about: json['about'],
      themeMode: json['themeMode'] ?? 'system',
      fontSizeMultiplier: (json['fontSizeMultiplier'] ?? 1.0).toDouble(),
      hasCompletedOnboarding: json['hasCompletedOnboarding'] ?? false,
      lastSelectedIndex: json['lastSelectedIndex'] ?? 0,
      isRemoteMode: json['isRemoteMode'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userName': userName,
      'userHandle': userHandle,
      'profileImagePath': profileImagePath,
      'about': about,
      'themeMode': themeMode,
      'fontSizeMultiplier': fontSizeMultiplier,
      'hasCompletedOnboarding': hasCompletedOnboarding,
      'lastSelectedIndex': lastSelectedIndex,
      'isRemoteMode': isRemoteMode,
    };
  }

  factory SettingsModel.fromEntity(SettingsEntity entity) {
    return SettingsModel(
      userName: entity.userName,
      userHandle: entity.userHandle,
      profileImagePath: entity.profileImagePath,
      about: entity.about,
      themeMode: entity.themeMode,
      fontSizeMultiplier: entity.fontSizeMultiplier,
      hasCompletedOnboarding: entity.hasCompletedOnboarding,
      lastSelectedIndex: entity.lastSelectedIndex,
      isRemoteMode: entity.isRemoteMode,
    );
  }

  factory SettingsModel.defaultSettings() {
    return const SettingsModel(
      userName: 'Local User',
      userHandle: 'local',
      themeMode: 'system',
      fontSizeMultiplier: 1.0,
      hasCompletedOnboarding: false,
      lastSelectedIndex: 0,
      isRemoteMode: false,
    );
  }
}
