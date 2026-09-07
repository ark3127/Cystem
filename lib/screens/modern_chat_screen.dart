import 'package:flutter/material.dart';

import 'chat_screen.dart';

/// Stable entry point for the modern CYSTEM chat surface.
///
/// The actual UI lives in ChatScreen. Keeping this compatibility wrapper lets
/// the app switch between UI iterations without leaving a second, stale screen
/// in the analyzer/build graph.
class ModernChatScreen extends StatelessWidget {
  const ModernChatScreen({super.key});

  @override
  Widget build(BuildContext context) => const ChatScreen();
}
