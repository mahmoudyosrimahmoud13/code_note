import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'constants/themes.dart';
import 'core/services/log_service.dart';
import 'features/notes/presentation/bloc/note_bloc.dart';
import 'features/notes/presentation/bloc/note_event.dart';
import 'features/notes/presentation/bloc/note_group_bloc.dart';
import 'features/notes/presentation/bloc/note_group_event.dart';
import 'features/notes/presentation/pages/home_page.dart';
import 'features/onboarding/presentation/pages/onboarding_page.dart';
import 'features/settings/presentation/bloc/settings_bloc.dart';
import 'features/settings/presentation/bloc/settings_event.dart';
import 'features/settings/presentation/bloc/settings_state.dart';
import 'helpers/helper_methods.dart';
import 'injection_container.dart' as di;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LogService().log("App: [START] Local-Only version started.");

  try {
    LogService().log("App: [STEP] Initializing Hive and Dependencies...");
    final appDocumentDir = await getApplicationSupportDirectory();
    await Hive.initFlutter(appDocumentDir.path);
    await di.init();
    LogService().log("App: [SUCCESS] Dependencies initialized.");
  } catch (e) {
    LogService().log("App: [FATAL] Dependency initialization failed: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => di.sl<SettingsBloc>()..add(GetSettingsEvent()),
        ),
        BlocProvider(
          create: (context) => di.sl<NoteBloc>()..add(GetNotesEvent()),
        ),
        BlocProvider(
          create: (context) => di.sl<NoteGroupBloc>()..add(GetGroupsEvent()),
        ),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          ThemeMode themeMode = ThemeMode.system;
          double fontMultiplier = 1.0;

          if (state is SettingsLoaded) {
            fontMultiplier = state.settings.fontSizeMultiplier;
            switch (state.settings.themeMode) {
              case 'light':
                themeMode = ThemeMode.light;
                break;
              case 'dark':
                themeMode = ThemeMode.dark;
                break;
              case 'system':
              default:
                themeMode = ThemeMode.system;
            }
          }

          return MaterialApp(
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            title: 'CodeNote (Local)',
            theme: mainTheme,
            darkTheme: darkTheme,
            themeMode: themeMode,
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(fontMultiplier),
                ),
                child: child!,
              );
            },
            home: state is SettingsLoaded
                ? (state.settings.hasCompletedOnboarding
                    ? const HomePage()
                    : const OnboardingPage())
                : const Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        },
      ),
    );
  }
}
