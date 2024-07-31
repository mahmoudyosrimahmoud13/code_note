import 'package:code_note/constants/themes.dart';
import 'package:code_note/cubit/note/note_cubit.dart';
import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/screens/home/home_screen.dart';

import 'package:code_note/screens/note/note_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => NoteCubit(),
        )
      ],
      child: MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Code note',
          theme: mainTheme,
          darkTheme: darkTheme,
          home: HomeScreen()),
    );
  }
}
