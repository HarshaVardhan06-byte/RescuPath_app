import 'package:flutter/material.dart';

class AppTheme {
  static const navy = Color(0xFF0A1930);
  static const navy2 = Color(0xFF102744);
  static const red = Color(0xFFFF3B4B);
  static const redDark = Color(0xFFDE1830);
  static const blue = Color(0xFF2477FF);
  static const cyan = Color(0xFF12BFEA);
  static const green = Color(0xFF14B879);
  static const amber = Color(0xFFFFA81E);
  static const orange = amber;
  static const purple = Color(0xFF6B4EFF);
  static const pink = Color(0xFFFF4C93);
  static const ink = Color(0xFF10233F);
  static const muted = Color(0xFF68788F);
  static const bg = Color(0xFFF4F7FB);
  static const card = Colors.white;
  static const surface = card;
  static const line = Color(0xFFE4EAF2);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme.copyWith(
        primary: blue,
        secondary: cyan,
        error: red,
        surface: card,
      ),
      fontFamily: 'Arial',
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: blue, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: navy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: blue.withValues(alpha: .13),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 11,
            color: ink,
          ),
        ),
      ),
    );
  }
}
