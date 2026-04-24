import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/notes/data/datasources/note_local_data_source.dart';
import 'features/notes/data/repositories/note_repository_impl.dart';
import 'features/notes/domain/repositories/note_repository.dart';
import 'features/notes/domain/usecases/get_notes.dart';
import 'features/notes/presentation/bloc/note_bloc.dart';
import 'features/notes/presentation/bloc/note_group_bloc.dart';
import 'features/settings/data/datasources/settings_local_data_source.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/repositories/settings_repository.dart';
import 'features/settings/presentation/bloc/settings_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
  //! Features - Notes
  // Bloc
  sl.registerFactory(
    () => NoteBloc(
      getNotes: sl(),
      repository: sl(),
    ),
  );
  sl.registerFactory(
    () => NoteGroupBloc(
      repository: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => GetNotes(sl()));

  // Repository
  sl.registerLazySingleton<NoteRepository>(
    () => NoteRepositoryImpl(
      localDataSource: sl(),
    ),
  );

  // Data sources
  sl.registerLazySingleton<NoteLocalDataSource>(
    () => NoteLocalDataSourceImpl(sharedPreferences: sl()),
  );

  //! Features - Settings
  // Bloc
  sl.registerFactory(() => SettingsBloc(repository: sl()));

  // Repository
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(localDataSource: sl()),
  );

  // Data sources
  sl.registerLazySingleton<SettingsLocalDataSource>(
    () => SettingsLocalDataSourceImpl(sharedPreferences: sl()),
  );

  //! Core
  // No core components yet

  //! External
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);
}
