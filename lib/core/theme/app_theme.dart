import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF0B0B0D);
  static const Color surface = Color(0xFF121214);
  static const Color surfaceRaised = Color(0xFF19191C);
  static const Color surfaceInteractive = Color(0xFF222226);

  static const Color primary = Color(0xFF9B7BFF);
  static const Color primarySoft = Color(0xFFB9A4FF);

  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFFA5A5AD);
  static const Color textMuted = Color(0xFF777780);

  static const double radiusSmall = 10;
  static const double radiusMedium = 16;
  static const double radiusLarge = 24;
  static const double radiusPill = 999;

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      surface: background,
    ).copyWith(
      primary: primary,
      onPrimary: const Color(0xFF17121F),
      secondary: primarySoft,
      onSecondary: const Color(0xFF17121F),
      surface: background,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceRaised,
      surfaceContainerHigh: surfaceInteractive,
      surfaceContainerHighest: const Color(0xFF2A2A2F),
      outline: const Color(0xFF36363B),
      outlineVariant: const Color(0xFF29292E),
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerTheme: const DividerThemeData(color: Color(0xFF252529), thickness: 1, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(color: textPrimary, fontWeight: FontWeight.w700, letterSpacing: -1.2),
        displayMedium: const TextStyle(color: textPrimary, fontWeight: FontWeight.w700, letterSpacing: -0.8),
        headlineLarge: const TextStyle(color: textPrimary, fontWeight: FontWeight.w700, letterSpacing: -0.6),
        headlineMedium: const TextStyle(color: textPrimary, fontWeight: FontWeight.w700, letterSpacing: -0.4),
        headlineSmall: const TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        titleLarge: const TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        titleMedium: const TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        titleSmall: const TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: const TextStyle(color: textPrimary, height: 1.45),
        bodyMedium: const TextStyle(color: textSecondary, height: 1.45),
        bodySmall: const TextStyle(color: textSecondary, height: 1.4),
        labelLarge: const TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        labelMedium: const TextStyle(color: textSecondary, fontWeight: FontWeight.w500),
        labelSmall: const TextStyle(color: textMuted, fontWeight: FontWeight.w500),
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised,
        hintStyle: const TextStyle(color: textMuted),
        labelStyle: const TextStyle(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMedium), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMedium), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMedium), borderSide: const BorderSide(color: primary, width: 1.2)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceInteractive,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceRaised,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.14),
      ),
    );
  }
}
