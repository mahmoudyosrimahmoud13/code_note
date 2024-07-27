import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final clorScheme = ColorScheme.fromSeed(
    seedColor: Color.fromARGB(255, 77, 33, 238), brightness: Brightness.light);
final darkColorScheme = ColorScheme.fromSeed(
    seedColor: Color.fromARGB(255, 77, 35, 230), brightness: Brightness.dark);

final mainTheme = ThemeData().copyWith(
  colorScheme: clorScheme,
);
final darkTheme = ThemeData.dark().copyWith(
  colorScheme: darkColorScheme.copyWith(
    primary: Color.fromARGB(255, 126, 108, 192),
  ),
);
