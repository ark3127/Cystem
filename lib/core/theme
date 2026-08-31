import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF090A0F);
  static const Color surface = Color(0xFF12141C);
  static const Color surfaceLight = Color(0xFF1A1D28);

  static const Color primary = Color(0xFF8B5CF6);
  static const Color primaryLight = Color(0xFFA78BFA);

  static const Color textPrimary = Color(0xFFF4F4F5);
  static const Color textSecondary = Color(0xFFA1A1AA);

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    scaffoldBackgroundColor: background,

    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: primaryLight,
      surface: surface,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      elevation: 0,
      centerTitle: false,
    ),

    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(
        color: textPrimary,
      ),
      bodyMedium: TextStyle(
        color: textSecondary,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: const TextStyle(
        color: textSecondary,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
