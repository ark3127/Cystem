import 'package:flutter/material.dart';

void main() {
  runApp(const CystemApp());
}

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
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            'CYSTEM',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
