import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';

class CystemApp extends StatelessWidget {
  const CystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CYSTEM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurpleAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const ChatScreen(),
    );
  }
}
