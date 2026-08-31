import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/chat_screen.dart';

class CystemApp extends StatelessWidget {
  const CystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CYSTEM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const ChatScreen(),
    );
  }
}
