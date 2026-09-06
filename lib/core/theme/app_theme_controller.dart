import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../services/app_settings_service.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();

  final AppSettingsService _settingsService = AppSettingsService();

  ThemeMode _themeMode = ThemeMode.dark;
  Color _accentColor = const Color(0xFF9B7BFF);

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;

  Future<void> load() async {
    final settings = await _settingsService.load();
    _themeMode = _themeModeFromString(settings.themeMode);
    _accentColor = Color(settings.accentColor);
    notifyListeners();
  }

  void updateThemeMode(String value) {
    _themeMode = _themeModeFromString(value);
    notifyListeners();
  }

  void updateAccentColor(Color color) {
    _accentColor = color;
    notifyListeners();
  }

  ThemeMode _themeModeFromString(String value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }
}
