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

  static ThemeData darkTheme({Color accent = primary}) => _buildTheme(Brightness.dark, accent);
  static ThemeData lightTheme({Color accent = primary}) => _buildTheme(Brightness.light, accent);

  static ThemeData _buildTheme(Brightness brightness, Color accent) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(useMaterial3: true, brightness: brightness);
    final bg = isDark ? background : const Color(0xFFF6F6F8);
    final card = isDark ? surface : Colors.white;
    final raised = isDark ? surfaceRaised : const Color(0xFFEDEDF1);
    final interactive = isDark ? surfaceInteractive : const Color(0xFFE3E3E8);
    final primaryText = isDark ? textPrimary : const Color(0xFF17171A);
    final secondaryText = isDark ? textSecondary : const Color(0xFF5F6068);
    final mutedText = isDark ? textMuted : const Color(0xFF777880);
    final softAccent = Color.lerp(accent, Colors.white, isDark ? 0.28 : 0.1)!;

    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness, surface: bg).copyWith(
      primary: accent,
      onPrimary: isDark ? const Color(0xFF17121F) : Colors.white,
      secondary: softAccent,
      onSecondary: isDark ? const Color(0xFF17121F) : Colors.white,
      surface: bg,
      surfaceContainerLowest: bg,
      surfaceContainerLow: card,
      surfaceContainer: raised,
      surfaceContainerHigh: interactive,
      surfaceContainerHighest: isDark ? const Color(0xFF2A2A2F) : const Color(0xFFD9D9DF),
      outline: isDark ? const Color(0xFF36363B) : const Color(0xFFD0D0D6),
      outlineVariant: isDark ? const Color(0xFF29292E) : const Color(0xFFE1E1E5),
      onSurface: primaryText,
      onSurfaceVariant: secondaryText,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerTheme: DividerThemeData(color: isDark ? const Color(0xFF252529) : const Color(0xFFE4E4E8), thickness: 1, space: 1),
      appBarTheme: AppBarTheme(backgroundColor: bg, foregroundColor: primaryText, elevation: 0, scrolledUnderElevation: 0, centerTitle: false, surfaceTintColor: Colors.transparent),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        constraints: const BoxConstraints.tightFor(width: 22, height: 22),
        strokeWidth: 2.2,
      ),
      textTheme: base.textTheme.copyWith(
        displayLarge: TextStyle(color: primaryText, fontWeight: FontWeight.w700, letterSpacing: -1.2),
        displayMedium: TextStyle(color: primaryText, fontWeight: FontWeight.w700, letterSpacing: -0.8),
        headlineLarge: TextStyle(color: primaryText, fontWeight: FontWeight.w700, letterSpacing: -0.6),
        headlineMedium: TextStyle(color: primaryText, fontWeight: FontWeight.w700, letterSpacing: -0.4),
        headlineSmall: TextStyle(color: primaryText, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: primaryText, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: primaryText, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: primaryText, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: primaryText, height: 1.45),
        bodyMedium: TextStyle(color: secondaryText, height: 1.45),
        bodySmall: TextStyle(color: secondaryText, height: 1.4),
        labelLarge: TextStyle(color: primaryText, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: secondaryText, fontWeight: FontWeight.w500),
        labelSmall: TextStyle(color: mutedText, fontWeight: FontWeight.w500),
      ),
      iconTheme: IconThemeData(color: secondaryText),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        hintStyle: TextStyle(color: mutedText),
        labelStyle: TextStyle(color: secondaryText),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMedium), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMedium), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMedium), borderSide: BorderSide(color: accent, width: 1.2)),
      ),
      cardTheme: CardThemeData(color: card, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium))),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: interactive, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium))),
      popupMenuTheme: PopupMenuThemeData(color: raised, elevation: 8, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium))),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent, showDragHandle: true),
      navigationDrawerTheme: NavigationDrawerThemeData(backgroundColor: card, indicatorColor: accent.withValues(alpha: 0.14)),
    );
  }
}
