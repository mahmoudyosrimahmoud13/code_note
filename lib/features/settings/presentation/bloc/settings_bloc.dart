import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository repository;

  SettingsBloc({required this.repository}) : super(SettingsInitial()) {
    on<GetSettingsEvent>((event, emit) async {
      emit(SettingsLoading());
      final result = await repository.getSettings();
      result.fold(
        (failure) => emit(const SettingsError('Could not fetch settings')),
        (settings) => emit(SettingsLoaded(settings)),
      );
    });

    on<UpdateSettingsEvent>((event, emit) async {
      final result = await repository.saveSettings(event.settings);
      result.fold(
        (failure) => emit(const SettingsError('Could not save settings')),
        (_) => add(GetSettingsEvent()),
      );
    });

    on<SwitchToCloudProfileEvent>((event, emit) async {
      final currentState = state;
      if (currentState is SettingsLoaded) {
        final updatedSettings = currentState.settings.copyWith(
          userName: event.user.name,
          userHandle: event.user.username,
          profileImagePath: event.user.profileImageUrl,
          about: event.user.about,
          isRemoteMode: true,
          hasCompletedOnboarding: true,
        );
        await repository.saveSettings(updatedSettings);
        add(GetSettingsEvent());
      }
    });

    on<SwitchToLocalProfileEvent>((event, emit) async {
      final result = await repository.getSettings(); // Get defaults
      result.fold(
        (_) => null,
        (settings) async {
          final localSettings = settings.copyWith(
            userName: 'Local User',
            userHandle: 'local',
            profileImagePath: '',
            about: '',
            isRemoteMode: false,
          );
          await repository.saveSettings(localSettings);
          add(GetSettingsEvent());
        },
      );
    });

    on<ResetAllDataEvent>((event, emit) async {
      emit(SettingsLoading());
      final result = await repository.resetAllData();
      result.fold(
        (failure) => emit(const SettingsError('Could not reset data')),
        (_) => add(GetSettingsEvent()),
      );
    });
  }
}
