import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/nvidia_api_service.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController =
      TextEditingController();

  final NvidiaApiService _apiService =
      NvidiaApiService();

  final List<ChatMessage> _messages = [];

  bool _isGenerating = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty || _isGenerating) return;

    final userMessage = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      content: text,
      role: MessageRole.user,
      createdAt: DateTime.now(),
    );

    final assistantMessageId =
        '${DateTime.now().microsecondsSinceEpoch}_assistant';

    var generatedText = '';

    setState(() {
      _messages.add(userMessage);

      _messages.add(
        ChatMessage(
          id: assistantMessageId,
          content: '',
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
        ),
      );

      _isGenerating = true;
    });

    _messageController.clear();

    try {
      await for (final chunk
          in _apiService.streamMessage(_messages.take(
        _messages.length - 1,
      ).toList())) {
        generatedText += chunk;

        if (!mounted) return;

        setState(() {
          final index = _messages.indexWhere(
            (message) =>
                message.id == assistantMessageId,
          );

          if (index != -1) {
            _messages[index] = ChatMessage(
              id: assistantMessageId,
              content: generatedText,
              role: MessageRole.assistant,
              createdAt: _messages[index].createdAt,
            );
          }
        });
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _messages.removeWhere(
          (message) =>
              message.id == assistantMessageId &&
              message.content.isEmpty,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),

            Expanded(
              child: _messages.isEmpty
                  ? _buildWelcome()
                  : _buildMessages(),
            ),

            _buildInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              // Sidebar will be added later.
            },
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'CYSTEM',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // New chat functionality comes later.
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.auto_awesome,
              size: 56,
            ),
            const SizedBox(height: 20),
            Text(
              'What can I help you with?',
              style:
                  Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Powered by Nemotron',
              style:
                  Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];

        return _MessageBubble(
          message: message,
          isGenerating:
              _isGenerating &&
              index == _messages.length - 1 &&
              message.isAssistant,
        );
      },
    );
  }

  Widget _buildInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16,
      ),
      child: TextField(
        controller: _messageController,
        minLines: 1,
        maxLines: 6,
        textInputAction: TextInputAction.newline,
        onSubmitted: (_) {
          if (!_isGenerating) {
            _sendMessage();
          }
        },
        decoration: InputDecoration(
          hintText: _isGenerating
              ? 'CYSTEM is responding...'
              : 'Ask anything...',
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_upward),
            onPressed: _isGenerating
                ? null
                : _sendMessage,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isGenerating,
  });

  final ChatMessage message;
  final bool isGenerating;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    if (message.content.isEmpty &&
        isGenerating) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 12),
            Text('Thinking...'),
          ],
        ),
      );
    }

    return Align(
      alignment: isUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 600,
        ),
        margin: const EdgeInsets.only(
          bottom: 12,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context)
                  .colorScheme
                  .primary
              : Theme.of(context)
                  .colorScheme
                  .surface,
          borderRadius:
              BorderRadius.circular(18),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isUser
                ? Theme.of(context)
                    .colorScheme
                    .onPrimary
                : null,
          ),
        ),
      ),
    );
  }
}
