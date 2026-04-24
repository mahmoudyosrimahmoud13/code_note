import 'package:equatable/equatable.dart';

class SettingsEntity extends Equatable {
  final String userName;
  final String userHandle;
  final String? profileImagePath;
  final String themeMode; // 'light', 'dark', 'system'
  final double fontSizeMultiplier;
  final bool hasCompletedOnboarding;
  final int lastSelectedIndex;

  const SettingsEntity({
    required this.userName,
    required this.userHandle,
    this.profileImagePath,
    required this.themeMode,
    required this.fontSizeMultiplier,
    this.hasCompletedOnboarding = false,
    this.lastSelectedIndex = 0,
  });

  factory SettingsEntity.defaultSettings() {
    return const SettingsEntity(
      userName: 'User Name',
      userHandle: '@username',
      themeMode: 'system',
      fontSizeMultiplier: 1.0,
      hasCompletedOnboarding: false,
      lastSelectedIndex: 0,
    );
  }

  SettingsEntity copyWith({
    String? userName,
    String? userHandle,
    String? profileImagePath,
    String? themeMode,
    double? fontSizeMultiplier,
    bool? hasCompletedOnboarding,
    int? lastSelectedIndex,
  }) {
    return SettingsEntity(
      userName: userName ?? this.userName,
      userHandle: userHandle ?? this.userHandle,
      profileImagePath: profileImagePath ?? this.profileImagePath,
      themeMode: themeMode ?? this.themeMode,
      fontSizeMultiplier: fontSizeMultiplier ?? this.fontSizeMultiplier,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      lastSelectedIndex: lastSelectedIndex ?? this.lastSelectedIndex,
    );
  }

  @override
  List<Object?> get props => [
        userName,
        userHandle,
        profileImagePath,
        themeMode,
        fontSizeMultiplier,
        hasCompletedOnboarding,
        lastSelectedIndex,
      ];
}
