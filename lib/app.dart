import 'package:flutter/material.dart';

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
      home: const CystemHome(),
    );
  }
}

class CystemHome extends StatelessWidget {
  const CystemHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),

            const Text(
              'CYSTEM',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),

            const Spacer(),

            const Icon(
              Icons.auto_awesome,
              size: 56,
            ),

            const SizedBox(height: 20),

            const Text(
              'What can I help you with?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Ask anything...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
