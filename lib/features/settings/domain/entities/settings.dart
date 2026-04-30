import 'package:equatable/equatable.dart';

class SettingsEntity extends Equatable {
  final String userName;
  final String userHandle;
  final String? profileImagePath;
  final String themeMode; // 'light', 'dark', 'system'
  final double fontSizeMultiplier;
  final bool hasCompletedOnboarding;
  final int lastSelectedIndex;

  final String? about;
  final bool isRemoteMode;
 
   const SettingsEntity({
     required this.userName,
     required this.userHandle,
     this.profileImagePath,
     this.about,
     required this.themeMode,
     required this.fontSizeMultiplier,
     this.hasCompletedOnboarding = false,
     this.lastSelectedIndex = 0,
     this.isRemoteMode = false,
   });
 
   factory SettingsEntity.defaultSettings() {
     return const SettingsEntity(
       userName: 'Local User',
       userHandle: 'local',
       themeMode: 'system',
       fontSizeMultiplier: 1.0,
       hasCompletedOnboarding: false,
       lastSelectedIndex: 0,
       isRemoteMode: false,
     );
   }
 
   SettingsEntity copyWith({
     String? userName,
     String? userHandle,
     String? profileImagePath,
     String? about,
     String? themeMode,
     double? fontSizeMultiplier,
     bool? hasCompletedOnboarding,
     int? lastSelectedIndex,
     bool? isRemoteMode,
   }) {
     return SettingsEntity(
       userName: userName ?? this.userName,
       userHandle: userHandle ?? this.userHandle,
       profileImagePath: profileImagePath ?? this.profileImagePath,
       about: about ?? this.about,
       themeMode: themeMode ?? this.themeMode,
       fontSizeMultiplier: fontSizeMultiplier ?? this.fontSizeMultiplier,
       hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
       lastSelectedIndex: lastSelectedIndex ?? this.lastSelectedIndex,
       isRemoteMode: isRemoteMode ?? this.isRemoteMode,
     );
   }
 
   @override
   List<Object?> get props => [
         userName,
         userHandle,
         profileImagePath,
         about,
         themeMode,
         fontSizeMultiplier,
         hasCompletedOnboarding,
         lastSelectedIndex,
         isRemoteMode,
       ];
}
