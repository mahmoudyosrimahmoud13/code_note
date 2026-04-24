import 'package:code_note/constants/themes.dart';
import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/features/auth/presentation/pages/start.dart';
import 'package:code_note/features/notes/presentation/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:code_note/injection_container.dart' as di;
import 'package:code_note/features/notes/presentation/bloc/note_bloc.dart';
import 'package:code_note/features/notes/presentation/bloc/note_event.dart';
import 'package:code_note/features/notes/presentation/bloc/note_group_bloc.dart';
import 'package:code_note/features/notes/presentation/bloc/note_group_event.dart';
import 'package:code_note/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:code_note/features/settings/presentation/bloc/settings_event.dart';
import 'package:code_note/features/settings/presentation/bloc/settings_state.dart';
import 'package:code_note/core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await di.init();
  await NotificationService().init();
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
        )
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
            title: 'Code note',
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
            home: state is SettingsLoaded && state.settings.hasCompletedOnboarding
                ? const HomePage()
                : const StartScreen(),
          );
        },
      ),
    );
  }
}
