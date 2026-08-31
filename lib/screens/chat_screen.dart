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

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() =>
      _ChatScreenState();
}

class _ChatScreenState
    extends State<ChatScreen> {
  final TextEditingController _messageController =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  final NvidiaApiService _apiService =
      NvidiaApiService();

  final ChatStorageService _storageService =
      ChatStorageService();

  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>();

  StreamSubscription<String>?
      _generationSubscription;

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
      final newConversation =
          _createConversation();

      conversations.add(newConversation);

      await _storageService
          .saveConversations(conversations);

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
      id: now.microsecondsSinceEpoch
          .toString(),
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

    final newConversation =
        _createConversation();

    setState(() {
      _conversations.add(newConversation);
      _conversation = newConversation;

      _sortConversations(_conversations);
    });

    await _saveAllConversations();

    if (mounted &&
        Navigator.of(context).canPop()) {
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
      conversation.isPinned =
          !conversation.isPinned;

      conversation.updatedAt =
          DateTime.now();

      _sortConversations(_conversations);
    });

    await _saveAllConversations();
  }

  Future<void> _renameConversation(
    ChatConversation conversation,
  ) async {
    if (_isGenerating) return;

    final controller =
        TextEditingController(
      text: conversation.title,
    );

    final newTitle =
        await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename chat'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 100,
            decoration:
                const InputDecoration(
              hintText:
                  'Enter chat name...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context)
                    .pop();
              },
              child:
                  const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context)
                    .pop(
                  controller.text.trim(),
                );
              },
              child:
                  const Text('Save'),
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
      conversation.updatedAt =
          DateTime.now();

      _sortConversations(_conversations);
    });

    await _saveAllConversations();
  }

  Future<void> _deleteConversation(
    ChatConversation conversation,
  ) async {
    if (_isGenerating) return;

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              const Text('Delete chat?'),
          content: Text(
            'Delete "${conversation.title}"? '
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context)
                    .pop(false);
              },
              child:
                  const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context)
                    .pop(true);
              },
              child:
                  const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        !mounted) {
      return;
    }

    setState(() {
      _conversations.removeWhere(
        (item) => item.id == conversation.id,
      );

      if (_conversation?.id ==
          conversation.id) {
        if (_conversations.isEmpty) {
          final newConversation =
              _createConversation();

          _conversations.add(
            newConversation,
          );

          _conversation =
              newConversation;
        } else {
          _sortConversations(
            _conversations,
          );

          _conversation =
              _conversations.first;
        }
      }
    });

    await _saveAllConversations();

    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final text =
        _messageController.text.trim();

    if (text.isEmpty ||
        _isGenerating ||
        _conversation == null) {
      return;
    }

    await _sendUserText(text);
  }

  Future<void> _sendUserText(
    String text,
  ) async {
    if (_conversation == null ||
        _isGenerating) {
      return;
    }

    final now = DateTime.now();

    final userMessage = ChatMessage(
      id: now.microsecondsSinceEpoch
          .toString(),
      content: text,
      role: MessageRole.user,
      createdAt: now,
    );

    setState(() {
      _conversation!.messages
          .add(userMessage);

      _conversation!.updatedAt =
          DateTime.now();

      if (_conversation!.title ==
          'New Chat') {
        _conversation!.title =
            text.length > 40
                ? '${text.substring(0, 40)}...'
                : text;
      }

      _sortConversations(
        _conversations,
      );
    });

    _messageController.clear();

    await _saveAllConversations();

    _scrollToBottom();

    await _generateResponse();
  }

  Future<void> _generateResponse() async {
    if (_conversation == null ||
        _isGenerating) {
      return;
    }

    final conversation =
        _conversation!;

    final assistantMessageId =
        '${DateTime.now().microsecondsSinceEpoch}_assistant';

    final assistantMessage =
        ChatMessage(
      id: assistantMessageId,
      content: '',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
    );

    setState(() {
      conversation.messages
          .add(assistantMessage);

      conversation.updatedAt =
          DateTime.now();

      _isGenerating = true;
    });

    _scrollToBottom();

    await _saveAllConversations();

    var generatedText = '';

    final messagesForApi =
        List<ChatMessage>.from(
      conversation.messages.where(
        (message) =>
            message.id != assistantMessageId,
      ),
    );

    _generationSubscription =
        _apiService
            .streamMessage(messagesForApi)
            .listen(
      (chunk) {
        generatedText += chunk;

        if (!mounted) return;

        if (_conversation?.id !=
            conversation.id) {
          return;
        }

        final index =
            conversation.messages.indexWhere(
          (message) =>
              message.id ==
              assistantMessageId,
        );

        if (index == -1) return;

        setState(() {
          conversation.messages[index] =
              conversation.messages[index]
                  .copyWith(
            content: generatedText,
          );

          conversation.updatedAt =
              DateTime.now();
        });

        _scrollToBottom();
      },
      onError: (Object error) async {
        if (!mounted) return;

        if (_conversation?.id ==
            conversation.id) {
          setState(() {
            final index =
                conversation.messages
                    .indexWhere(
              (message) =>
                  message.id ==
                  assistantMessageId,
            );

            if (index != -1 &&
                conversation
                    .messages[index]
                    .content
                    .isEmpty) {
              conversation.messages
                  .removeAt(index);
            }

            _isGenerating = false;
          });

          await _saveAllConversations();

          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(
              SnackBar(
                content: Text(
                  'Error: $error',
                ),
              ),
            );
          }
        }

        _generationSubscription = null;
      },
      onDone: () async {
        if (!mounted) return;

        if (_conversation?.id ==
            conversation.id) {
          setState(() {
            _isGenerating = false;

            conversation.updatedAt =
                DateTime.now();

            _sortConversations(
              _conversations,
            );
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
        _conversation!.updatedAt =
            DateTime.now();

        _sortConversations(
          _conversations,
        );
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

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content:
            Text('Copied to clipboard'),
      ),
    );
  }

  Future<void> _editMessage(
    ChatMessage message,
  ) async {
    if (_conversation == null ||
        _isGenerating) {
      return;
    }

    final controller =
        TextEditingController(
      text: message.content,
    );

    final editedText =
        await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              const Text('Edit message'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 8,
            decoration:
                const InputDecoration(
              hintText:
                  'Edit your message...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context)
                    .pop();
              },
              child:
                  const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context)
                    .pop(
                  controller.text.trim(),
                );
              },
              child:
                  const Text('Save'),
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

    final index =
        _conversation!.messages.indexWhere(
      (item) => item.id == message.id,
    );

    if (index == -1) return;

    setState(() {
      _conversation!.messages =
          _conversation!.messages
              .take(index + 1)
              .toList();

      _conversation!.messages[index] =
          ChatMessage(
        id: message.id,
        content: editedText,
        role: MessageRole.user,
        createdAt: message.createdAt,
      );

      _conversation!.updatedAt =
          DateTime.now();

      _sortConversations(
        _conversations,
      );
    });

    await _saveAllConversations();

    _scrollToBottom();

    await _generateResponse();
  }

  Future<void> _regenerateResponse(
    ChatMessage message,
  ) async {
    if (_conversation == null ||
        _isGenerating) {
      return;
    }

    final index =
        _conversation!.messages.indexWhere(
      (item) => item.id == message.id,
    );

    if (index == -1 ||
        !message.isAssistant) {
      return;
    }

    setState(() {
      _conversation!.messages =
          _conversation!.messages
              .take(index)
              .toList();

      _conversation!.updatedAt =
          DateTime.now();

      _sortConversations(
        _conversations,
      );
    });

    await _saveAllConversations();

    _scrollToBottom();

    await _generateResponse();
  }

  Future<void> _deleteMessage(
    ChatMessage message,
  ) async {
    if (_conversation == null ||
        _isGenerating) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              const Text('Delete message?'),
          content: const Text(
            'This will remove this message '
            'and all messages after it.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context)
                    .pop(false);
              },
              child:
                  const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context)
                    .pop(true);
              },
              child:
                  const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        !mounted) {
      return;
    }

    final index =
        _conversation!.messages.indexWhere(
      (item) => item.id == message.id,
    );

    if (index == -1) return;

    setState(() {
      _conversation!.messages =
          _conversation!.messages
              .take(index)
              .toList();

      _conversation!.updatedAt =
          DateTime.now();

      _sortConversations(
        _conversations,
      );
    });

    await _saveAllConversations();

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController
            .position.maxScrollExtent,
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
        builder: (_) =>
            const SettingsScreen(),
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
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: ChatDrawer(
        conversations: _conversations,
        currentConversationId:
            _conversation?.id,
        onNewChat: _createNewChat,
        onSelectConversation:
            _selectConversation,
        onTogglePin: _togglePin,
        onRenameConversation:
            _renameConversation,
        onDeleteConversation:
            _deleteConversation,
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
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      child: Row(
        children: [
          IconButton(
            icon:
                const Icon(Icons.menu),
            onPressed: () {
              _scaffoldKey.currentState
                  ?.openDrawer();
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _conversation?.title ??
                  'CYSTEM',
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          IconButton(
            icon:
                const Icon(Icons.add),
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
      child: Padding(
        padding:
            const EdgeInsets.all(24),
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
              style: Theme.of(context)
                  .textTheme
                  .titleLarge,
            ),
            const SizedBox(height: 8),
        
