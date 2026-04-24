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
  }
}
