import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_controller.dart';
import 'screens/modern_chat_screen.dart';

class CystemApp extends StatefulWidget {
  const CystemApp({super.key});

  @override
  State<CystemApp> createState() => _CystemAppState();
}

class _CystemAppState extends State<CystemApp> {
  final _themeController = AppThemeController.instance;

  @override
  void initState() {
    super.initState();
    _themeController.addListener(_onThemeChanged);
    _themeController.load();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CYSTEM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(accent: _themeController.accentColor),
      darkTheme: AppTheme.darkTheme(accent: _themeController.accentColor),
      themeMode: _themeController.themeMode,
      home: const ModernChatScreen(),
    );
  }
}
