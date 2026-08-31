import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../services/chat_storage_service.dart';
import '../services/nvidia_api_service.dart';
import '../widgets/chat_drawer.dart';
import '../widgets/message_actions.dart';
import 'settings_screen.dart';
import '../widgets/code_block.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController =
      TextEditingController();
  final ScrollController _scrollController =
      ScrollController();
  final NvidiaApiService _apiService = NvidiaApiService();
  final ChatStorageService _storageService =
      ChatStorageService();
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>();

  StreamSubscription<String>? _generationSubscription;

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

    _sortConversations(conversations);

    if (conversations.isEmpty) {
      final newConversation = _createConversation();
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

    _scrollToBottom();
  }

  ChatConversation _createConversation() {
    final now = DateTime.now();

    return ChatConversation(
      id: now.microsecondsSinceEpoch.toString(),
      title: 'New Chat',
      createdAt: now,
      updatedAt: now,
    );
  }

  void _sortConversations(
    List<ChatConversation> conversations,
  ) {
    conversations.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }

      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Future<void> _saveAllConversations() async {
    _sortConversations(_conversations);

    await _storageService.saveConversations(
      _conversations,
    );
  }

  Future<void> _createNewChat() async {
    if (_isGenerating) return;

    final newConversation = _createConversation();

    setState(() {
      _conversations.add(newConversation);
      _conversation = newConversation;
      _sortConversations(_conversations);
    });

    await _saveAllConversations();

    if (mounted && Navigator.of(context).canPop()) {
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

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    _scrollToBottom();
  }

  Future<void> _togglePin(
    ChatConversation conversation,
  ) async {
    if (_isGenerating) return;

    setState(() {
      conversation.isPinned = !conversation.isPinned;
      conversation.updatedAt = DateTime.now();
      _sortConversations(_conversations);
    });

    await _saveAllConversations();
  }

  Future<void> _renameConversation(
    ChatConversation conversation,
  ) async {
    if (_isGenerating) return;

    final controller = TextEditingController(
      text: conversation.title,
    );

    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename chat'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(
              hintText: 'Enter chat name...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  controller.text.trim(),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newTitle == null ||
        newTitle.isEmpty ||
        !mounted) {
      return;
    }

    setState(() {
      conversation.title = newTitle;
      conversation.updatedAt = DateTime.now();
      _sortConversations(_conversations);
    });

    await _saveAllConversations();
  }

  Future<void> _deleteConversation(
    ChatConversation conversation,
  ) async {
    if (_isGenerating) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete chat?'),
          content: Text(
            'Delete "${conversation.title}"? '
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _conversations.removeWhere(
        (item) => item.id == conversation.id,
      );

      if (_conversation?.id == conversation.id) {
        if (_conversations.isEmpty) {
          final newConversation = _createConversation();
          _conversations.add(newConversation);
          _conversation = newConversation;
        } else {
          _sortConversations(_conversations);
          _conversation = _conversations.first;
        }
      }
    });

    await _saveAllConversations();
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty ||
        _isGenerating ||
        _conversation == null) {
      return;
    }

    await _sendUserText(text);
  }

  Future<void> _sendUserText(String text) async {
    if (_conversation == null || _isGenerating) {
      return;
    }

    final now = DateTime.now();

    final userMessage = ChatMessage(
      id: now.microsecondsSinceEpoch.toString(),
      content: text,
      role: MessageRole.user,
      createdAt: now,
    );

    setState(() {
      _conversation!.messages.add(userMessage);
      _conversation!.updatedAt = DateTime.now();

      if (_conversation!.title == 'New Chat') {
        _conversation!.title = text.length > 40
            ? '${text.substring(0, 40)}...'
            : text;
      }

      _sortConversations(_conversations);
    });

    _messageController.clear();

    await _saveAllConversations();
    _scrollToBottom();

    await _generateResponse();
  }

  Future<void> _generateResponse() async {
    if (_conversation == null || _isGenerating) {
      return;
    }

    final conversation = _conversation!;

    final assistantMessageId =
        '${DateTime.now().microsecondsSinceEpoch}_assistant';

    final assistantMessage = ChatMessage(
      id: assistantMessageId,
      content: '',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
    );

    setState(() {
      conversation.messages.add(assistantMessage);
      conversation.updatedAt = DateTime.now();
      _isGenerating = true;
    });

    _scrollToBottom();
    await _saveAllConversations();

    var generatedText = '';

    final messagesForApi = List<ChatMessage>.from(
      conversation.messages.where(
        (message) => message.id != assistantMessageId,
      ),
    );

    _generationSubscription = _apiService
        .streamMessage(messagesForApi)
        .listen(
      (chunk) {
        generatedText += chunk;

        if (!mounted ||
            _conversation?.id != conversation.id) {
          return;
        }

        final index = conversation.messages.indexWhere(
          (message) => message.id == assistantMessageId,
        );

        if (index == -1) return;

        setState(() {
          conversation.messages[index] =
              conversation.messages[index].copyWith(
            content: generatedText,
          );

          conversation.updatedAt = DateTime.now();
        });

        _scrollToBottom();
      },
      onError: (Object error) async {
        if (!mounted) return;

        if (_conversation?.id == conversation.id) {
          setState(() {
            final index =
                conversation.messages.indexWhere(
              (message) =>
                  message.id == assistantMessageId,
            );

            if (index != -1 &&
                conversation.messages[index]
                    .content
                    .isEmpty) {
              conversation.messages.removeAt(index);
            }

            _isGenerating = false;
          });

          await _saveAllConversations();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $error'),
              ),
            );
          }
        }

        _generationSubscription = null;
      },
      onDone: () async {
        if (!mounted) return;

        if (_conversation?.id == conversation.id) {
          setState(() {
            _isGenerating = false;
            conversation.updatedAt = DateTime.now();
            _sortConversations(_conversations);
          });

          await _saveAllConversations();
        }

        _generationSubscription = null;
      },
      cancelOnError: true,
    );
  }

  Future<void> _stopGeneration() async {
    if (!_isGenerating) return;

    await _generationSubscription?.cancel();
    _generationSubscription = null;

    if (!mounted) return;

    setState(() {
      _isGenerating = false;

      if (_conversation != null) {
        _conversation!.updatedAt = DateTime.now();
        _sortConversations(_conversations);
      }
    });

    await _saveAllConversations();
    _scrollToBottom();
  }
    Future<void> _copyMessage(
    ChatMessage message,
  ) async {
    await Clipboard.setData(
      ClipboardData(
        text: message.content,
      ),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
      ),
    );
  }

  Future<void> _editMessage(
    ChatMessage message,
  ) async {
    if (_conversation == null || _isGenerating) {
      return;
    }

    final controller = TextEditingController(
      text: message.content,
    );

    final editedText = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit message'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Edit your message...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  controller.text.trim(),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (editedText == null ||
        editedText.isEmpty ||
        !mounted) {
      return;
    }

    final index = _conversation!.messages.indexWhere(
      (item) => item.id == message.id,
    );

    if (index == -1) return;

    setState(() {
      _conversation!.messages =
          _conversation!.messages.take(index + 1).toList();

      _conversation!.messages[index] = ChatMessage(
        id: message.id,
        content: editedText,
        role: MessageRole.user,
        createdAt: message.createdAt,
      );

      _conversation!.updatedAt = DateTime.now();
      _sortConversations(_conversations);
    });

    await _saveAllConversations();
    _scrollToBottom();

    await _generateResponse();
  }

  Future<void> _regenerateResponse(
    ChatMessage message,
  ) async {
    if (_conversation == null || _isGenerating) {
      return;
    }

    final index = _conversation!.messages.indexWhere(
      (item) => item.id == message.id,
    );

    if (index == -1 || !message.isAssistant) {
      return;
    }

    setState(() {
      _conversation!.messages =
          _conversation!.messages.take(index).toList();

      _conversation!.updatedAt = DateTime.now();
      _sortConversations(_conversations);
    });

    await _saveAllConversations();
    _scrollToBottom();

    await _generateResponse();
  }

  Future<void> _deleteMessage(
    ChatMessage message,
  ) async {
    if (_conversation == null || _isGenerating) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete message?'),
          content: const Text(
            'This will remove this message '
            'and all messages after it.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final index = _conversation!.messages.indexWhere(
      (item) => item.id == message.id,
    );

    if (index == -1) return;

    setState(() {
      _conversation!.messages =
          _conversation!.messages.take(index).toList();

      _conversation!.updatedAt = DateTime.now();
      _sortConversations(_conversations);
    });

    await _saveAllConversations();
    _scrollToBottom();
  }

  void _useSuggestion(String prompt) {
    if (_isGenerating) return;

    _sendUserText(prompt);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(
          milliseconds: 250,
        ),
        curve: Curves.easeOut,
      );
    });
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
    _generationSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
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
        onRenameConversation: _renameConversation,
        onDeleteConversation: _deleteConversation,
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
            icon: const Icon(
              Icons.settings_outlined,
            ),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 650,
          ),
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 56,
              ),
              const SizedBox(height: 20),
              Text(
                'What can I help you with?',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Powered by Nemotron',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium,
              ),
              const SizedBox(height: 32),
              _SuggestionCard(
                icon: Icons.lightbulb_outline,
                title: 'Explain a complex topic',
                subtitle:
                    'Break something difficult down simply',
                onTap: () => _useSuggestion(
                  'Explain a complex topic to me '
                  'in a simple and easy-to-understand way.',
                ),
              ),
              const SizedBox(height: 12),
              _SuggestionCard(
                icon: Icons.code,
                title: 'Help me write code',
                subtitle:
                    'Solve a programming problem with me',
                onTap: () => _useSuggestion(
                  'Help me solve a programming problem. '
                  'Ask me what I am working on first.',
                ),
              ),
              const SizedBox(height: 12),
              _SuggestionCard(
                icon: Icons.psychology_outlined,
                title: 'Brainstorm ideas',
                subtitle:
                    'Explore creative ideas and possibilities',
                onTap: () => _useSuggestion(
                  'Help me brainstorm some creative ideas. '
                  'Ask me what I want to brainstorm first.',
                ),
              ),
              const SizedBox(height: 12),
              _SuggestionCard(
                icon: Icons.edit_outlined,
                title: 'Help me write something',
                subtitle:
                    'Draft, rewrite, or improve my writing',
                onTap: () => _useSuggestion(
                  'Help me write something. '
                  'Ask me what I want to write first.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollController,
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

        return _MessageBubble(
          message: message,
          onCopy: () => _copyMessage(message),
          onEdit: message.isUser
              ? () => _editMessage(message)
              : null,
          onRegenerate: message.isAssistant
              ? () => _regenerateResponse(message)
              : null,
          onDelete: () => _deleteMessage(message),
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
            tooltip: _isGenerating
                ? 'Stop generating'
                : 'Send message',
            icon: Icon(
              _isGenerating
                  ? Icons.stop
                  : Icons.arrow_upward,
            ),
            onPressed: _isGenerating
                ? _stopGeneration
                : _sendMessage,
          ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontWeight:
                                FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onCopy,
    required this.onEdit,
    required this.onRegenerate,
    required this.onDelete,
  });

  final ChatMessage message;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    final backgroundColor = isUser
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surface;

    final textColor = isUser
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;

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
        padding: const EdgeInsets.fromLTRB(
          16,
          12,
          8,
          8,
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            isUser
                ? Text(
                    message.content,
                    style: TextStyle(
                      color: textColor,
                    ),
                  )
                : MarkdownBody(
                    data: message.content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        height: 1.45,
                      ),
                      h1: TextStyle(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      h2: TextStyle(
                        color: textColor,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                      h3: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      code: TextStyle(
                        color: textColor,
                        fontFamily: 'monospace',
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                    ),
                  ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: MessageActions(
                isUser: isUser,
                onCopy: onCopy,
                onEdit: onEdit,
                onRegenerate: onRegenerate,
                onDelete: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
