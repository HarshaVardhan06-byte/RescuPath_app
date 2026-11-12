import 'package:flutter/material.dart';

class AppTheme {
  static const navy = Color(0xFF0A2540);
  static const navy2 = Color(0xFF0F172A);
  static const red = Color(0xFFDC2626);
  static const redLight = Color(0xFFEF4444);
  static const redDark = Color(0xFFB91C1C);
  static const blue = Color(0xFF2563EB);
  static const cyan = Color(0xFF0EA5E9);
  static const green = Color(0xFF16A34A);
  static const greenLight = Color(0xFFDCFCE7);
  static const greenText = Color(0xFF15803D);
  static const pinkLight = Color(0xFFFFF1F2);
  static const pinkBorder = Color(0xFFFECDD3);
  static const amber = Color(0xFFF59E0B);
  static const orange = amber;
  static const purple = Color(0xFF6B4EFF);
  static const pink = Color(0xFFFF4C93);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const bg = Color(0xFFF8FAFC);
  static const card = Colors.white;
  static const surface = card;
  static const line = Color(0xFFE2E8F0);

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
