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
