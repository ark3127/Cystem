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
          if (identical(_generationCancellationToken, cancellationToken)) _generationCancellationToken = null;
        });
        await _saveAllConversations();
        if (!cancelled) _showSnack('Error: $error');
        _generationSubscription = null;
      },
      onDone: () async {
        if (!mounted || _conversation?.id != conversation.id) return;
        setState(() {
          _isGenerating = false;
          if (identical(_generationCancellationToken, cancellationToken)) _generationCancellationToken = null;
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
        final index = _conversation!.messages.indexWhere((message) =>
            message.role == MessageRole.assistant &&
            message.content.isEmpty &&
            message.reasoningContent == null &&
            message.toolCalls.isEmpty);
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
    setState(() => _conversation!.messages = _conversation!.messages.take(index).toList());
    await _saveAllConversations();
  }

  void _useSuggestion(String prompt) {
    if (!_isGenerating) _sendUserText(prompt);
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || (!_userIsNearBottom && !jump)) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  void dispose() {
    _generationCancellationToken?.cancel();
    _generationSubscription?.cancel();
    _messageController.removeListener(_onInputChanged);
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
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
        currentConversationId: _conversation?.id,
        onNewChat: _createNewChat,
        onSelectConversation: _selectConversation,
        onTogglePin: _togglePin,
        onRenameConversation: _renameConversation,
        onDeleteConversation: _deleteConversation,
        onOpenSettings: () {
          Navigator.pop(context);
          _openSettings();
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _messages.isEmpty ? _buildWelcome() : _buildMessages()),
            _buildInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(tooltip: 'Chats', icon: const Icon(Icons.menu), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_conversation?.title ?? 'CYSTEM', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text('Kimi K3', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(tooltip: 'New chat', icon: const Icon(Icons.add), onPressed: _isGenerating ? null : _createNewChat),
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.auto_awesome, size: 34, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              const SizedBox(height: 20),
              Text('What can I help you with?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Ask questions, share images, or let CYSTEM use your phone tools.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 28),
              _SuggestionCard(icon: Icons.lightbulb_outline, title: 'Explain a complex topic', subtitle: 'Break something difficult down simply', onTap: () => _useSuggestion('Explain a complex topic to me in a simple and easy-to-understand way.')),
              _SuggestionCard(icon: Icons.code, title: 'Help me write code', subtitle: 'Solve a programming problem with me', onTap: () => _useSuggestion('Help me solve a programming problem. Ask me what I am working on first.')),
              _SuggestionCard(icon: Icons.psychology_outlined, title: 'Brainstorm ideas', subtitle: 'Explore creative ideas and possibilities', onTap: () => _useSuggestion('Help me brainstorm some creative ideas. Ask me what I want to brainstorm first.')),
              _SuggestionCard(icon: Icons.edit_outlined, title: 'Help me write something', subtitle: 'Draft, rewrite, or improve my writing', onTap: () => _useSuggestion('Help me write something. Ask me what I want to write first.')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final message = _messages[index];
            final generating = _isGenerating && index == _messages.length - 1 && message.isAssistant;
            return _MessageBubble(
              message: message,
              isGenerating: generating,
              onCopy: message.content.isEmpty ? null : () => _copyMessage(message),
              onEdit: message.isUser ? () => _editMessage(message) : null,
              onRegenerate: message.isAssistant && !message.isTool ? () => _regenerateResponse(message) : null,
              onDelete: () => _deleteMessage(message),
            );
          },
        ),
        if (!_userIsNearBottom && _messages.isNotEmpty)
          Positioned(
            right: 20,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'scroll_to_bottom',
              tooltip: 'Jump to latest',
              onPressed: () {
                _userIsNearBottom = true;
                _scrollToBottom(jump: true);
              },
              child: const Icon(Icons.keyboard_arrow_down),
            ),
          ),
      ],
    );
  }

  Widget _buildInput() {
    final canSend = _messageController.text.trim().isNotEmpty || _pendingAttachments.isNotEmpty;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingAttachments.isNotEmpty) _buildAttachmentStrip(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: _isGenerating ? 'CYSTEM is thinking...' : 'Message CYSTEM',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  prefixIcon: IconButton(tooltip: 'Add image', icon: const Icon(Icons.add), onPressed: _isGenerating ? null : _pickImage),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: IconButton.filled(
                      tooltip: _isGenerating ? 'Stop generating' : 'Send message',
                      icon: Icon(_isGenerating ? Icons.stop_rounded : Icons.arrow_upward_rounded),
                      onPressed: _isGenerating ? _stopGeneration : canSend ? _sendMessage : null,
                    ),
                  ),
                ),
                onSubmitted: (_) {
                  if (!_isGenerating && canSend) _sendMessage();
                },
              ),
            ),
            const SizedBox(height: 5),
            Text('CYSTEM can make phone actions only after you confirm them.', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentStrip() {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 7),
        itemCount: _pendingAttachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final attachment = _pendingAttachments[index];
          return _AttachmentPreview(attachment: attachment, onRemove: () => _removePendingAttachment(attachment.id));
        },
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 25),
              const SizedBox(width: 15),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(subtitle, style: Theme.of(context).textTheme.bodySmall)])),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachment, required this.onRemove});
  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            decodeAttachmentImage(attachment),
            width: 82,
            height: 82,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(width: 82, height: 82, color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined)),
          ),
        ),
        Positioned(right: -7, top: -7, child: IconButton.filledTonal(visualDensity: VisualDensity.compact, iconSize: 17, tooltip: 'Remove image', onPressed: onRemove, icon: const Icon(Icons.close))),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isGenerating, required this.onCopy, required this.onEdit, required this.onRegenerate, required this.onDelete});
  final ChatMessage message;
  final bool isGenerating;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (message.isTool) return _buildToolMessage(context);
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final background = isUser ? scheme.primary : scheme.surfaceContainerLow;
    final foreground = isUser ? scheme.onPrimary : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 13, 10, 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 5),
            bottomRight: Radius.circular(isUser ? 5 : 20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message.attachments.isNotEmpty) _buildImages(context),
            if (message.attachments.isNotEmpty && message.content.isNotEmpty) const SizedBox(height: 10),
            if (!isUser && message.reasoningContent != null && message.reasoningContent!.isNotEmpty)
              _ReasoningSection(reasoning: message.reasoningContent!, textColor: foreground, isGenerating: isGenerating),
            if (message.content.isEmpty && isGenerating) _ThinkingIndicator(color: foreground),
            if (message.content.isNotEmpty)
              isUser
                  ? SelectableText(message.content, style: TextStyle(color: foreground, fontSize: 16, height: 1.4))
                  : MarkdownBody(
                      data: message.content,
                      selectable: true,
                      builders: {'pre': CodeBlockBuilder()},
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: foreground, fontSize: 16, height: 1.45),
                        h1: TextStyle(color: foreground, fontSize: 24, fontWeight: FontWeight.bold),
                        h2: TextStyle(color: foreground, fontSize: 21, fontWeight: FontWeight.bold),
                        h3: TextStyle(color: foreground, fontSize: 18, fontWeight: FontWeight.bold),
                        code: TextStyle(color: foreground, fontFamily: 'monospace'),
                        codeblockDecoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
            if (onCopy != null || onEdit != null || onRegenerate != null)
              Align(alignment: Alignment.centerRight, child: MessageActions(isUser: isUser, onCopy: onCopy, onEdit: onEdit, onRegenerate: onRegenerate, onDelete: onDelete)),
          ],
        ),
      ),
    );
  }

  Widget _buildToolMessage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(left: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.build_circle_outlined, size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 9),
            Expanded(child: Text(message.toolName == null ? message.content : '${message.toolName}: ${message.content}', style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13))),
          ],
        ),
      ),
    );
  }

  Widget _buildImages(BuildContext context) {
    if (message.attachments.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(decodeAttachmentImage(message.attachments.first), height: 240, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 80, child: Icon(Icons.broken_image_outlined))),
      );
    }
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: message.attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) => ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(decodeAttachmentImage(message.attachments[index]), width: 180, height: 180, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _ReasoningSection extends StatelessWidget {
  const _ReasoningSection({required this.reasoning, required this.textColor, required this.isGenerating});
  final String reasoning;
  final Color textColor;
  final bool isGenerating;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          initiallyExpanded: isGenerating,
          leading: Icon(isGenerating ? Icons.psychology : Icons.psychology_outlined, size: 20),
          title: Text(isGenerating ? 'Thinking…' : 'Reasoning', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
          children: [Align(alignment: Alignment.centerLeft, child: SelectableText(reasoning, style: TextStyle(color: textColor.withValues(alpha: 0.78), fontSize: 14, height: 1.4)))],
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: color)),
        const SizedBox(width: 10),
        Text('Thinking…', style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 14)),
      ],
    );
  }
}
