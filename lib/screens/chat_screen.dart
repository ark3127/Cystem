import 'package:flutter/material.dart';

import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../services/chat_storage_service.dart';
import '../services/nvidia_api_service.dart';
import '../widgets/chat_drawer.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController =
      TextEditingController();

  final NvidiaApiService _apiService = NvidiaApiService();
  final ChatStorageService _storageService =
      ChatStorageService();

  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>();

  List<ChatConversation> _conversations = [];
  ChatConversation? _conversation;

  bool _isGenerating = false;
  bool _isLoading = true;

  List<ChatMessage> get _messages =>
      _conversation?.messages ?? [];

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final conversations =
        await _storageService.loadConversations();

    conversations.sort(
      (a, b) => b.updatedAt.compareTo(a.updatedAt),
    );

    if (conversations.isEmpty) {
      final now = DateTime.now();

      final newConversation = ChatConversation(
        id: now.microsecondsSinceEpoch.toString(),
        title: 'New Chat',
        createdAt: now,
        updatedAt: now,
      );

      conversations.add(newConversation);

      await _storageService.saveConversations(
        conversations,
      );

      _conversation = newConversation;
    } else {
      _conversation = conversations.first;
    }

    if (!mounted) return;

    setState(() {
      _conversations = conversations;
      _isLoading = false;
    });
  }

  Future<void> _saveAllConversations() async {
    await _storageService.saveConversations(
      _conversations,
    );
  }

  Future<void> _createNewChat() async {
    if (_isGenerating) return;

    final now = DateTime.now();

    final newConversation = ChatConversation(
      id: now.microsecondsSinceEpoch.toString(),
      title: 'New Chat',
      createdAt: now,
      updatedAt: now,
    );

    setState(() {
      _conversations.add(newConversation);
      _conversation = newConversation;
    });

    await _saveAllConversations();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _selectConversation(
    ChatConversation conversation,
  ) async {
    if (_isGenerating) return;

    setState(() {
      _conversation = conversation;
    });

    Navigator.of(context).pop();
  }

  Future<void> _togglePin(
    ChatConversation conversation,
  ) async {
    if (_isGenerating) return;

    setState(() {
      conversation.isPinned = !conversation.isPinned;
      conversation.updatedAt = DateTime.now();
    });

    await _saveAllConversations();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty ||
        _isGenerating ||
        _conversation == null) {
      return;
    }

    final now = DateTime.now();

    final userMessage = ChatMessage(
      id: now.microsecondsSinceEpoch.toString(),
      content: text,
      role: MessageRole.user,
      createdAt: now,
    );

    final assistantMessageId =
        '${DateTime.now().microsecondsSinceEpoch}_assistant';

    final assistantMessage = ChatMessage(
      id: assistantMessageId,
      content: '',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
    );

    setState(() {
      _conversation!.messages.add(userMessage);
      _conversation!.messages.add(assistantMessage);

      _conversation!.updatedAt = DateTime.now();

      if (_conversation!.title == 'New Chat') {
        _conversation!.title = text.length > 40
            ? '${text.substring(0, 40)}...'
            : text;
      }

      _isGenerating = true;
    });

    _messageController.clear();

    await _saveAllConversations();

    var generatedText = '';

    try {
      final messagesForApi =
          List<ChatMessage>.from(
        _conversation!.messages.where(
          (message) =>
              message.id != assistantMessageId,
        ),
      );

      await for (final chunk
          in _apiService.streamMessage(messagesForApi)) {
        generatedText += chunk;

        if (!mounted) return;

        setState(() {
          final index =
              _conversation!.messages.indexWhere(
            (message) =>
                message.id == assistantMessageId,
          );

          if (index != -1) {
            _conversation!.messages[index] =
                _conversation!.messages[index].copyWith(
              content: generatedText,
            );
          }
        });
      }

      _conversation!.updatedAt = DateTime.now();

      await _saveAllConversations();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _conversation!.messages.removeWhere(
          (message) =>
              message.id == assistantMessageId &&
              message.content.isEmpty,
        );
      });

      await _saveAllConversations();

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
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,

      drawer: ChatDrawer(
        conversations: _conversations,
        currentConversationId: _conversation?.id,
        onNewChat: _createNewChat,
        onSelectConversation: _selectConversation,
        onTogglePin: _togglePin,
        onOpenSettings: () {
          Navigator.of(context).pop();
          _openSettings();
        },
      ),

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
              _scaffoldKey.currentState?.openDrawer();
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _conversation?.title ?? 'CYSTEM',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New chat',
            onPressed: _isGenerating
                ? null
                : _createNewChat,
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

        final isGeneratingMessage =
            _isGenerating &&
            index == _messages.length - 1 &&
            message.isAssistant;

        if (message.content.isEmpty &&
            isGeneratingMessage) {
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

        return _MessageBubble(message: message);
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
  });

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

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
