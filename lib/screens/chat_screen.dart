import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme/app_theme.dart';
import '../models/chat_attachment.dart';
import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../models/chat_stream_event.dart';
import '../services/chat_cancellation_token.dart';
import '../services/chat_generation_service.dart';
import '../services/chat_storage_service.dart';
import '../services/image_attachment_service.dart';
import '../services/app_tool_registry.dart';
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
    toolRegistry: AppToolRegistry.create(),
    toolExecutor: AppToolExecutor(),
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
    return ChatConversation(id: now.microsecondsSinceEpoch.toString(), title: 'New Chat', createdAt: now, updatedAt: now);
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
        content: TextField(controller: controller, autofocus: true, maxLength: 100, decoration: const InputDecoration(hintText: 'Chat name')),
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
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
              ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, ImageSource.camera)),
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
      if (mounted) _showSnack('Could not add image: $error');
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
    final userMessage = ChatMessage(id: now.microsecondsSinceEpoch.toString(), content: text, role: MessageRole.user, createdAt: now, attachments: attachments);
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
    final assistant = ChatMessage(id: assistantId, content: '', role: MessageRole.assistant, createdAt: DateTime.now());
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
            ? ChatApiMetadata(responseId: event.responseId ?? old.apiMetadata?.responseId, model: event.model ?? old.apiMetadata?.model, finishReason: event.finishReason ?? old.apiMetadata?.finishReason, promptTokens: event.promptTokens ?? old.apiMetadata?.promptTokens, completionTokens: event.completionTokens ?? old.apiMetadata?.completionTokens, totalTokens: event.totalTokens ?? old.apiMetadata?.totalTokens)
            : old.apiMetadata;
        setState(() {
          conversation.messages[index] = old.copyWith(content: generatedText, reasoningContent: generatedReasoning.isEmpty ? old.reasoningContent : generatedReasoning, apiMetadata: metadata);
          conversation.updatedAt = DateTime.now();
        });
        _scrollToBottom();
      },
      onError: (Object error) async {
        if (!mounted || _conversation?.id != conversation.id) return;
        final cancelled = cancellationToken.isCancelled || error is ChatGenerationCancelledException;
        setState(() {
          final index = conversation.messages.indexWhere((m) => m.id == assistantId);
          if (index != -1 && conversation.messages[index].content.isEmpty && conversation.messages[index].reasoningContent == null) conversation.messages.removeAt(index);
          _isGenerating = false;
          if (identical(_generationCancellationToken, cancellationToken)) _generationCancellationToken = null;
        });
        await _saveAllConversations();
        if (!cancelled) _showSnack('Something went wrong: $error');
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
        final index = _conversation!.messages.indexWhere((message) => message.role == MessageRole.assistant && message.content.isEmpty && message.reasoningContent == null && message.toolCalls.isEmpty);
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
      _conversation!.messages[index] = ChatMessage(id: message.id, content: edited, role: MessageRole.user, createdAt: message.createdAt, attachments: message.attachments);
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
          IconButton(tooltip: 'Chats', icon: const Icon(Icons.menu_rounded), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
          Expanded(
            child: GestureDetector(
              onTap: _openSettings,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  children: [
                    Container(width: 30, height: 30, decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.14), shape: BoxShape.circle), child: const Icon(Icons.auto_awesome_rounded, size: 16, color: AppTheme.primary)),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_conversation?.title ?? 'CYSTEM', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const Text('Nemotron 3 Super', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(tooltip: 'New chat', icon: const Icon(Icons.add_rounded), onPressed: _isGenerating ? null : _createNewChat),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            children: [
              Container(width: 64, height: 64, decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.13), shape: BoxShape.circle), child: const Icon(Icons.auto_awesome_rounded, size: 30, color: AppTheme.primary)),
              const SizedBox(height: 20),
              Text('How can I help?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Ask anything, share an image, or let CYSTEM use its tools when you need them.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 28),
              _SuggestionCard(icon: Icons.lightbulb_outline_rounded, title: 'Explain something', subtitle: 'Make a difficult topic simple', onTap: () => _useSuggestion('Explain a complex topic to me in a simple and easy-to-understand way.')),
              _SuggestionCard(icon: Icons.code_rounded, title: 'Help with code', subtitle: 'Solve a programming problem', onTap: () => _useSuggestion('Help me solve a programming problem. Ask me what I am working on first.')),
              _SuggestionCard(icon: Icons.psychology_outlined, title: 'Brainstorm', subtitle: 'Explore ideas and possibilities', onTap: () => _useSuggestion('Help me brainstorm some creative ideas. Ask me what I want to brainstorm first.')),
              _SuggestionCard(icon: Icons.edit_outlined, title: 'Write something', subtitle: 'Draft, rewrite, or improve text', onTap: () => _useSuggestion('Help me write something. Ask me what I want to write first.')),
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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
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
            bottom: 18,
            child: FloatingActionButton.small(
              heroTag: 'scroll_to_bottom',
              backgroundColor: AppTheme.surfaceInteractive,
              foregroundColor: AppTheme.textPrimary,
              tooltip: 'Jump to latest',
              onPressed: () {
                _userIsNearBottom = true;
                _scrollToBottom(jump: true);
              },
              child: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ),
      ],
    );
  }

  Widget _buildInput() {
    final canSend = _messageController.text.trim().isNotEmpty || _pendingAttachments.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingAttachments.isNotEmpty) _buildAttachmentStrip(),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: AppTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 7,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: _isGenerating ? 'CYSTEM is thinking…' : 'Message CYSTEM',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(4, 13, 4, 7),
                prefixIcon: IconButton(tooltip: 'Add', icon: const Icon(Icons.add_circle_outline_rounded), onPressed: _isGenerating ? null : _pickImage),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 4),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: IconButton.filled(
                      key: ValueKey(_isGenerating),
                      tooltip: _isGenerating ? 'Stop generating' : 'Send message',
                      icon: Icon(_isGenerating ? Icons.stop_rounded : Icons.arrow_upward_rounded, size: 20),
                      onPressed: _isGenerating ? _stopGeneration : canSend ? _sendMessage : null,
                    ),
                  ),
                ),
              ),
              onSubmitted: (_) {
                if (!_isGenerating && canSend) _sendMessage();
              },
            ),
          ),
          const SizedBox(height: 6),
          Text('CYSTEM may use tools to help. Phone actions always require your confirmation.', style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildAttachmentStrip() {
    return SizedBox(
      height: 86,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            child: Row(
              children: [
                Container(width: 38, height: 38, decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 20, color: AppTheme.primary)),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 3), Text(subtitle, style: Theme.of(context).textTheme.bodySmall)])),
                const Icon(Icons.arrow_forward_rounded, size: 17),
              ],
            ),
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
          child: Image.memory(decodeAttachmentImage(attachment), width: 78, height: 78, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 78, height: 78, color: AppTheme.surfaceInteractive, child: const Icon(Icons.broken_image_outlined))),
        ),
        Positioned(right: -7, top: -7, child: IconButton.filledTonal(visualDensity: VisualDensity.compact, iconSize: 16, tooltip: 'Remove image', onPressed: onRemove, icon: const Icon(Icons.close))),
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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: EdgeInsets.only(left: isUser ? 44 : 0, right: isUser ? 0 : 44, bottom: 18),
        padding: EdgeInsets.fromLTRB(isUser ? 15 : 2, 4, isUser ? 10 : 2, 4),
        decoration: BoxDecoration(
          color: isUser ? scheme.primary.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(isUser ? 20 : 8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message.attachments.isNotEmpty) _buildImages(context),
            if (message.attachments.isNotEmpty && message.content.isNotEmpty) const SizedBox(height: 10),
            if (!isUser && message.reasoningContent != null && message.reasoningContent!.isNotEmpty) _ReasoningSection(reasoning: message.reasoningContent!, isGenerating: isGenerating),
            if (message.content.isEmpty && isGenerating) const _ThinkingIndicator(),
            if (message.content.isNotEmpty)
              isUser
                  ? SelectableText(message.content, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, height: 1.45))
                  : MarkdownBody(
                      data: message.content,
                      selectable: true,
                      onTapLink: (_, href, __) {
                        if (href != null) Clipboard.setData(ClipboardData(text: href));
                      },
                      builders: {'pre': CodeBlockBuilder()},
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, height: 1.48),
                        h1: const TextStyle(color: AppTheme.textPrimary, fontSize: 25, fontWeight: FontWeight.w700, height: 1.2),
                        h2: const TextStyle(color: AppTheme.textPrimary, fontSize: 21, fontWeight: FontWeight.w700, height: 1.25),
                        h3: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                        a: const TextStyle(color: AppTheme.primarySoft, decoration: TextDecoration.none),
                        code: const TextStyle(color: AppTheme.primarySoft, fontFamily: 'monospace', fontSize: 14),
                        blockquote: const TextStyle(color: AppTheme.textSecondary, fontSize: 15, height: 1.45),
                        listBullet: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                      ),
                    ),
            if (onCopy != null || onEdit != null || onRegenerate != null)
              Align(alignment: Alignment.centerLeft, child: MessageActions(isUser: isUser, onCopy: onCopy, onEdit: onEdit, onRegenerate: onRegenerate, onDelete: onDelete)),
          ],
        ),
      ),
    );
  }

  Widget _buildToolMessage(BuildContext context) {
    final isWeb = message.toolName == 'web_search';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(isWeb ? Icons.language_rounded : Icons.build_circle_outlined, size: 17, color: AppTheme.primary)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isWeb ? 'Web search' : (message.toolName ?? 'Tool'), style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                MarkdownBody(data: message.content, selectable: true, styleSheet: MarkdownStyleSheet(p: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4), a: const TextStyle(color: AppTheme.primarySoft, fontSize: 13))),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImages(BuildContext context) {
    if (message.attachments.length == 1) {
      return ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(decodeAttachmentImage(message.attachments.first), height: 240, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 80, child: Icon(Icons.broken_image_outlined))));
    }
    return SizedBox(height: 180, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: message.attachments.length, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, index) => ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(decodeAttachmentImage(message.attachments[index]), width: 180, height: 180, fit: BoxFit.cover))));
  }
}

class _ReasoningSection extends StatelessWidget {
  const _ReasoningSection({required this.reasoning, required this.isGenerating});
  final String reasoning;
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
          initiallyExpanded: false,
          dense: true,
          leading: Icon(isGenerating ? Icons.psychology_rounded : Icons.psychology_outlined, size: 19, color: AppTheme.textSecondary),
          title: Text(isGenerating ? 'Reasoning…' : 'Reasoning', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          children: [Align(alignment: Alignment.centerLeft, child: SelectableText(reasoning, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.45)))],
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)), SizedBox(width: 10), Text('Thinking…', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14))]);
  }
}
