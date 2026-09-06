import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_attachment.dart';
import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../models/chat_stream_event.dart';
import '../services/chat_cancellation_token.dart';
import '../services/chat_generation_service.dart';
import '../services/chat_storage_service.dart';
import '../services/image_attachment_service.dart';
import '../services/phone_tool_registry.dart';
import '../services/phone_tool_service.dart';
import '../widgets/chat_drawer.dart';
import '../widgets/code_block.dart';
import '../widgets/message_actions.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _storageService = ChatStorageService();
  final _imageService = ImageAttachmentService();
  final _generationService = ChatGenerationService(
    toolRegistry: PhoneToolRegistry.create(),
    toolExecutor: PhoneToolService(),
  );
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  StreamSubscription<ChatStreamEvent>? _generationSubscription;
  ChatCancellationToken? _generationCancellationToken;
  List<ChatConversation> _conversations = [];
  ChatConversation? _conversation;
  List<ChatAttachment> _pendingAttachments = [];
  bool _isGenerating = false;
  bool _isLoading = true;
  bool _userIsNearBottom = true;

  List<ChatMessage> get _messages => _conversation?.messages ?? [];

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onInputChanged);
    _scrollController.addListener(_onScroll);
    _loadConversations();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final distance = _scrollController.position.maxScrollExtent - _scrollController.position.pixels;
    _userIsNearBottom = distance < 180;
    if (mounted) setState(() {});
  }

  Future<void> _loadConversations() async {
    final conversations = await _storageService.loadConversations();
    _sortConversations(conversations);
    if (conversations.isEmpty) {
      final conversation = _createConversation();
      conversations.add(conversation);
      _conversation = conversation;
      await _storageService.saveConversations(conversations);
    } else {
      _conversation = conversations.first;
    }
    if (!mounted) return;
    setState(() {
      _conversations = conversations;
      _isLoading = false;
    });
    _scrollToBottom(jump: true);
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

  void _sortConversations(List<ChatConversation> conversations) {
    conversations.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Future<void> _saveAllConversations() async {
    _sortConversations(_conversations);
    await _storageService.saveConversations(_conversations);
  }

  Future<void> _createNewChat() async {
    if (_isGenerating) return;
    final conversation = _createConversation();
    setState(() {
      _conversations.add(conversation);
      _conversation = conversation;
      _pendingAttachments = [];
      _sortConversations(_conversations);
    });
    await _saveAllConversations();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    _scrollToBottom(jump: true);
  }

  Future<void> _selectConversation(ChatConversation conversation) async {
    if (_isGenerating) return;
    setState(() {
      _conversation = conversation;
      _pendingAttachments = [];
    });
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    _scrollToBottom(jump: true);
  }

  Future<void> _togglePin(ChatConversation conversation) async {
    if (_isGenerating) return;
    setState(() {
      conversation.isPinned = !conversation.isPinned;
      conversation.updatedAt = DateTime.now();
      _sortConversations(_conversations);
    });
    await _saveAllConversations();
  }

  Future<void> _renameConversation(ChatConversation conversation) async {
    if (_isGenerating) return;
    final controller = TextEditingController(text: conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(hintText: 'Enter chat name...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || !mounted) return;
    setState(() {
      conversation.title = title;
      conversation.updatedAt = DateTime.now();
    });
    await _saveAllConversations();
  }

  Future<void> _deleteConversation(ChatConversation conversation) async {
    if (_isGenerating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text('Delete "${conversation.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _conversations.removeWhere((item) => item.id == conversation.id);
      if (_conversation?.id == conversation.id) {
        if (_conversations.isEmpty) {
          _conversation = _createConversation();
          _conversations.add(_conversation!);
        } else {
          _sortConversations(_conversations);
          _conversation = _conversations.first;
        }
      }
      _pendingAttachments = [];
    });
    await _saveAllConversations();
    _scrollToBottom(jump: true);
  }

  Future<void> _pickImage() async {
    if (_isGenerating) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final attachment = await _imageService.pickImage(source);
      if (attachment == null || !mounted) return;
      setState(() => _pendingAttachments = [..._pendingAttachments, attachment]);
    } catch (error) {
      if (!mounted) return;
      _showSnack('Could not add image: $error');
    }
  }

  void _removePendingAttachment(String id) {
    setState(() => _pendingAttachments = _pendingAttachments.where((item) => item.id != id).toList());
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _pendingAttachments.isEmpty) || _isGenerating || _conversation == null) return;
    await _sendUserText(text, attachments: List.of(_pendingAttachments));
  }

  Future<void> _sendUserText(String text, {List<ChatAttachment> attachments = const []}) async {
    if (_conversation == null || _isGenerating) return;
    final now = DateTime.now();
    final userMessage = ChatMessage(
      id: now.microsecondsSinceEpoch.toString(),
      content: text,
      role: MessageRole.user,
      createdAt: now,
      attachments: attachments,
    );
    setState(() {
      _conversation!.messages.add(userMessage);
      _conversation!.updatedAt = DateTime.now();
      _pendingAttachments = [];
      if (_conversation!.title == 'New Chat') {
        final source = text.isNotEmpty ? text : 'Image message';
        _conversation!.title = source.length > 40 ? '${source.substring(0, 40)}...' : source;
      }
    });
    _messageController.clear();
    await _saveAllConversations();
    _scrollToBottom(jump: true);
    await _generateResponse();
  }

  Future<void> _generateResponse() async {
    if (_conversation == null || _isGenerating) return;
    final conversation = _conversation!;
    final assistantId = '${DateTime.now().microsecondsSinceEpoch}_assistant';
    final assistant = ChatMessage(
      id: assistantId,
      content: '',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
    );
    final cancellationToken = ChatCancellationToken();

    setState(() {
      conversation.messages.add(assistant);
      conversation.updatedAt = DateTime.now();
      _isGenerating = true;
      _generationCancellationToken = cancellationToken;
      _userIsNearBottom = true;
    });
    _scrollToBottom(jump: true);
    await _saveAllConversations();

    final messagesForApi = conversation.messages.where((m) => m.id != assistantId).toList();
    var generatedText = '';
    var generatedReasoning = '';

    _generationSubscription = _generationService.generate(
      messagesForApi,
      cancellationToken: cancellationToken,
      onToolMessage: (message) async {
        if (cancellationToken.isCancelled || !mounted || _conversation?.id != conversation.id) return;
        final placeholderIndex = conversation.messages.indexWhere((m) => m.id == assistantId);
        if (placeholderIndex == -1) return;
        setState(() {
          conversation.messages.insert(placeholderIndex, message);
          conversation.updatedAt = DateTime.now();
        });
        await _saveAllConversations();
        _scrollToBottom();
      },
    ).listen(
      (event) {
        if (event.hasText) generatedText += event.text!;
        if (event.hasReasoning) generatedReasoning += event.reasoning!;
        if (!mounted || _conversation?.id != conversation.id || cancellationToken.isCancelled) return;
        final index = conversation.messages.indexWhere((m) => m.id == assistantId);
        if (index == -1) return;
        final old = conversation.messages[index];
        final metadata = event.responseId != null || event.model != null || event.finishReason != null || event.hasUsage
            ? ChatApiMetadata(
                responseId: event.responseId ?? old.apiMetadata?.responseId,
                model: event.model ?? old.apiMetadata?.model,
                finishReason: event.finishReason ?? old.apiMetadata?.finishReason,
                promptTokens: event.promptTokens ?? old.apiMetadata?.promptTokens,
                completionTokens: event.completionTokens ?? old.apiMetadata?.completionTokens,
                totalTokens: event.totalTokens ?? old.apiMetadata?.totalTokens,
              )
            : old.apiMetadata;
        setState(() {
          conversation.messages[index] = old.copyWith(
            content: generatedText,
            reasoningContent: generatedReasoning.isEmpty ? old.reasoningContent : generatedReasoning,
            apiMetadata: metadata,
          );
          conversation.updatedAt = DateTime.now();
        });
        _scrollToBottom();
      },
      onError: (Object error) async {
        if (!mounted || _conversation?.id != conversation.id) return;
        final cancelled = cancellationToken.isCancelled || error is ChatGenerationCancelledException;
        setState(() {
          final index = conversation.messages.indexWhere((m) => m.id == assistantId);
          if (index != -1 && conversation.messages[index].content.isEmpty && conversation.messages[index].reasoningContent == null) {
            conversation.messages.removeAt(index);
          }
          _isGenerating = false;
          if (identical(_generationCancellationToken, cancellationToken)) {
            _generationCancellationToken = null;
          }
        });
        await _saveAllConversations();
        if (!cancelled) _showSnack('Error: $error');
        _generationSubscription = null;
      },
      onDone: () async {
        if (!mounted || _conversation?.id != conversation.id) return;
        setState(() {
          _isGenerating = false;
          if (identical(_generationCancellationToken, cancellationToken)) {
            _generationCancellationToken = null;
          }
          conversation.updatedAt = DateTime.now();
        });
        await _saveAllConversations();
        _generationSubscription = null;
        _scrollToBottom();
      },
      cancelOnError: true,
    );
  }

  Future<void> _stopGeneration() async {
    if (!_isGenerating) return;
    final token = _generationCancellationToken;
    token?.cancel();
    await _generationSubscription?.cancel();
    _generationSubscription = null;
    if (!mounted) return;
    setState(() {
      if (_conversation != null) {
        final index = _conversation!.messages.indexWhere(
          (message) => message.role == MessageRole.assistant &&
              message.content.isEmpty &&
              message.reasoningContent == null &&
              message.toolCalls.isEmpty,
        );
        if (index != -1) _conversation!.messages.removeAt(index);
        _conversation!.updatedAt = DateTime.now();
      }
      _isGenerating = false;
      _generationCancellationToken = null;
    });
    await _saveAllConversations();
  }

  Future<void> _copyMessage(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (mounted) _showSnack('Copied to clipboard');
  }

  Future<void> _editMessage(ChatMessage message) async {
    if (_conversation == null || _isGenerating) return;
    final controller = TextEditingController(text: message.content);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: controller, autofocus: true, minLines: 2, maxLines: 8),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Send')),
        ],
      ),
    );
    controller.dispose();
    if (edited == null || edited.isEmpty || !mounted) return;
    final index = _conversation!.messages.indexWhere((item) => item.id == message.id);
    if (index == -1) return;
    setState(() {
      _conversation!.messages = _conversation!.messages.take(index + 1).toList();
      _conversation!.messages[index] = ChatMessage(
        id: message.id,
        content: edited,
        role: MessageRole.user,
        createdAt: message.createdAt,
        attachments: message.attachments,
      );
      _conversation!.updatedAt = DateTime.now();
    });
    await _saveAllConversations();
    await _generateResponse();
  }

  Future<void> _regenerateResponse(ChatMessage message) async {
    if (_conversation == null || _isGenerating || !message.isAssistant) return;
    final index = _conversation!.messages.indexWhere((item) => item.id == message.id);
    if (index == -1) return;
    setState(() {
      _conversation!.messages = _conversation!.messages.take(index).toList();
      _conversation!.updatedAt = DateTime.now();
    });
    await _saveAllConversations();
    await _generateResponse();
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    if (_conversation == null || _isGenerating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This will remove this message and everything after it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final index = _conversation!.messages.indexWhere((item) => item.id == message.id);
    if (index == -1) return;
    setState(() {
      _conversation!.messages = _conversation!.messages.take(index).toList();
      _conversation!.updatedAt = DateTime.now();
    });
    await _saveAllConversations();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || (!_userIsNearBottom && !jump)) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _generationCancellationToken?.cancel();
    _generationSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      key: _scaffoldKey,
      drawer: ChatDrawer(
        conversations: _conversations,
        selectedConversation: _conversation,
        onNewChat: _createNewChat,
        onSelectConversation: _selectConversation,
        onRenameConversation: _renameConversation,
        onDeleteConversation: _deleteConversation,
        onTogglePin: _togglePin,
        onOpenSettings: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
      ),
      appBar: AppBar(
        title: const Text('CYSTEM'),
        actions: [IconButton(onPressed: () => _scaffoldKey.currentState?.openDrawer(), icon: const Icon(Icons.menu))],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildWelcome()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
                  ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: 52),
            const SizedBox(height: 16),
            Text('What can I do for you?', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _suggestion('Explain something'),
                _suggestion('Open a website'),
                _suggestion('Find a place'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestion(String text) => ActionChip(
        label: Text(text),
        onPressed: () => _sendUserText(text),
      );

  Widget _buildComposer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingAttachments.isNotEmpty)
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pendingAttachments.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final attachment = _pendingAttachments[index];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(attachment.data, width: 76, height: 76, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: IconButton.filledTonal(
                            iconSize: 18,
                            onPressed: () => _removePendingAttachment(attachment.id),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(onPressed: _isGenerating ? null : _pickImage, icon: const Icon(Icons.add_photo_alternate_outlined)),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(hintText: 'Message Cystem...'),
                  ),
                ),
                const SizedBox(width: 8),
                _isGenerating
                    ? IconButton.filled(onPressed: _stopGeneration, icon: const Icon(Icons.stop))
                    : IconButton.filled(onPressed: _sendMessage, icon: const Icon(Icons.arrow_upward)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.attachments.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: message.attachments.map((attachment) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(attachment.data, width: 180, height: 180, fit: BoxFit.cover),
                )).toList(),
              ),
            if (message.reasoningContent != null && message.reasoningContent!.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Reasoning'),
                children: [Align(alignment: Alignment.centerLeft, child: Text(message.reasoningContent!))],
              ),
            if (message.content.isNotEmpty)
              MarkdownBody(
                data: message.content,
                selectable: true,
                builders: {'code': CodeBlockBuilder()},
              ),
            if (message.content.isEmpty && message.reasoningContent == null && message.isAssistant && _isGenerating)
              const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            if (message.isAssistant && message.content.isNotEmpty)
              MessageActions(message: message, onCopy: () => _copyMessage(message), onEdit: () => _editMessage(message), onRegenerate: () => _regenerateResponse(message), onDelete: () => _deleteMessage(message)),
          ],
        ),
      ),
    );
  }
}
