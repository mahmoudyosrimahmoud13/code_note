import 'package:code_note/constants/themes.dart';
import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/features/auth/presentation/pages/start.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'injection_container.dart' as di;
import 'features/notes/presentation/bloc/note_bloc.dart';
import 'features/notes/presentation/bloc/note_event.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await di.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => di.sl<NoteBloc>()..add(GetNotesEvent()),
        )
      ],
      child: MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Code note',
          theme: mainTheme,
          darkTheme: darkTheme,
          home: const StartScreen()),
    );
  }
}
