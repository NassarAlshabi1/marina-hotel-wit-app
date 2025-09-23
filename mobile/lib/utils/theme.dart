import 'package:flutter/material.dart';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF006C67),
    fontFamily: 'Tajawal',
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(centerTitle: true),
    cardTheme: const CardTheme(margin: EdgeInsets.all(8)),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}
