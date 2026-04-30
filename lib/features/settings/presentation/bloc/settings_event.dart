import 'package:equatable/equatable.dart';
import '../../domain/entities/settings.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class GetSettingsEvent extends SettingsEvent {}

class UpdateSettingsEvent extends SettingsEvent {
  final SettingsEntity settings;
  const UpdateSettingsEvent(this.settings);

  @override
  List<Object?> get props => [settings];
}

class ResetAllDataEvent extends SettingsEvent {}

class SwitchToCloudProfileEvent extends SettingsEvent {
  final dynamic user; // Using dynamic to avoid circular import or just use the fields
  const SwitchToCloudProfileEvent(this.user);
  @override
  List<Object?> get props => [user];
}

class SwitchToLocalProfileEvent extends SettingsEvent {}
