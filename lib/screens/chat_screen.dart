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
import '../services/app_tool_registry.dart';
import '../services/chat_cancellation_token.dart';
import '../services/chat_generation_service.dart';
import '../services/chat_storage_service.dart';
import '../services/image_attachment_service.dart';
import '../services/image_gallery_service.dart';
import '../widgets/chat_drawer.dart';
import 'settings_screen.dart';

/// Modern phone-first CYSTEM chat surface.
///
/// Specialist/tool output and model reasoning are deliberately not rendered.
/// They remain backend data where required for continuity and diagnostics.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _storage = ChatStorageService();
  final _imageService = ImageAttachmentService();
  final _galleryService = ImageGalleryService();
  final _generationService = ChatGenerationService(
    toolRegistry: AppToolRegistry.create(),
    toolExecutor: AppToolExecutor(),
  );
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  StreamSubscription<ChatStreamEvent>? _subscription;
  ChatCancellationToken? _cancelToken;
  List<ChatConversation> _conversations = [];
  ChatConversation? _conversation;
  List<ChatAttachment> _pendingAttachments = [];
  bool _loading = true;
  bool _generating = false;
  bool _nearBottom = true;

  List<ChatMessage> get _messages => _conversation?.messages ?? const [];
  bool get _canSend =>
      _messageController.text.trim().isNotEmpty || _pendingAttachments.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_refreshInput);
    _scrollController.addListener(_handleScroll);
    _load();
  }

  void _refreshInput() {
    if (mounted) setState(() {});
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    _nearBottom =
        _scrollController.position.maxScrollExtent - _scrollController.position.pixels < 180;
  }

  Future<void> _load() async {
    final conversations = await _storage.loadConversations();
    _sort(conversations);
    if (conversations.isEmpty) {
      final chat = _newConversation();
      conversations.add(chat);
      await _storage.saveConversations(conversations);
    }
    if (!mounted) return;
    setState(() {
      _conversations = conversations;
      _conversation = conversations.first;
      _loading = false;
    });
    _scrollToBottom(jump: true);
  }

  ChatConversation _newConversation() {
    final now = DateTime.now();
    return ChatConversation(
      id: now.microsecondsSinceEpoch.toString(),
      title: 'New Chat',
      createdAt: now,
      updatedAt: now,
    );
  }

  void _sort(List<ChatConversation> items) {
    items.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Future<void> _save() async {
    _sort(_conversations);
    await _storage.saveConversations(_conversations);
  }

  Future<void> _newChat() async {
    if (_generating) return;
    final chat = _newConversation();
    setState(() {
      _conversations.add(chat);
      _conversation = chat;
      _pendingAttachments = [];
    });
    await _save();
    _scrollToBottom(jump: true);
  }

  Future<void> _selectChat(ChatConversation chat) async {
    if (_generating) return;
    setState(() {
      _conversation = chat;
      _pendingAttachments = [];
    });
    if (mounted && Navigator.of(context).canPop()) Navigator.pop(context);
    _scrollToBottom(jump: true);
  }

  Future<void> _pinChat(ChatConversation chat) async {
    if (_generating) return;
    setState(() {
      chat.isPinned = !chat.isPinned;
      chat.updatedAt = DateTime.now();
    });
    await _save();
  }

  Future<void> _renameChat(ChatConversation chat) async {
    if (_generating) return;
    final controller = TextEditingController(text: chat.title);
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(controller: controller, autofocus: true, maxLength: 80),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    setState(() {
      chat.title = value;
      chat.updatedAt = DateTime.now();
    });
    await _save();
  }

  Future<void> _deleteChat(ChatConversation chat) async {
    if (_generating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text('Delete "${chat.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _conversations.removeWhere((item) => item.id == chat.id);
      if (_conversations.isEmpty) _conversations.add(_newConversation());
      _sort(_conversations);
      _conversation = _conversations.first;
    });
    await _save();
    _scrollToBottom(jump: true);
  }

  Future<void> _pickImage() async {
    if (_generating) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
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
      final image = await _imageService.pickImage(source);
      if (image != null && mounted) {
        setState(() => _pendingAttachments = [..._pendingAttachments, image]);
      }
    } catch (error) {
      _snack('Could not add image.');
    }
  }

  Future<void> _send() async {
    if (!_canSend || _generating || _conversation == null) return;
    final text = _messageController.text.trim();
    final attachments = List<ChatAttachment>.of(_pendingAttachments);
    final now = DateTime.now();
    final message = ChatMessage(
      id: now.microsecondsSinceEpoch.toString(),
      content: text,
      role: MessageRole.user,
      createdAt: now,
      attachments: attachments,
    );
    setState(() {
      _conversation!.messages.add(message);
      _conversation!.updatedAt = now;
      _pendingAttachments = [];
      if (_conversation!.title == 'New Chat') {
        final title = text.isEmpty ? 'Image message' : text;
        _conversation!.title = title.length > 42 ? '${title.substring(0, 42)}…' : title;
      }
    });
    _messageController.clear();
    await _save();
    _scrollToBottom(jump: true);
    await _generate();
  }

  Future<void> _generate() async {
    final conversation = _conversation;
    if (conversation == null || _generating) return;

    final assistantId = '${DateTime.now().microsecondsSinceEpoch}_assistant';
    final assistant = ChatMessage(
      id: assistantId,
      content: '',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
    );
    final token = ChatCancellationToken();
    setState(() {
      conversation.messages.add(assistant);
      conversation.updatedAt = DateTime.now();
      _generating = true;
      _cancelToken = token;
      _nearBottom = true;
    });
    await _save();
    _scrollToBottom(jump: true);

    final messages = conversation.messages.where((m) => m.id != assistantId).toList();
    var generatedText = '';

    _subscription = _generationService.generate(
      messages,
      cancellationToken: token,
      onToolMessage: (_) async {},
      onGeneratedImage: (image, backendContext) async {
        if (!mounted || token.isCancelled || _conversation?.id != conversation.id) return;
        final index = conversation.messages.indexWhere((m) => m.id == assistantId);
        if (index == -1) return;
        final old = conversation.messages[index];
        setState(() {
          conversation.messages[index] = old.copyWith(
            attachments: [...old.attachments, image],
            backendContext: backendContext,
          );
          conversation.updatedAt = DateTime.now();
        });
        await _save();
        _scrollToBottom();
      },
    ).listen(
      (event) {
        if (event.hasText) generatedText += event.text!;
        if (!mounted || token.isCancelled || _conversation?.id != conversation.id) return;
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
          // Reasoning is intentionally ignored at the UI/storage boundary.
          conversation.messages[index] = old.copyWith(content: generatedText, apiMetadata: metadata);
          conversation.updatedAt = DateTime.now();
        });
        _scrollToBottom();
      },
      onError: (Object error) async {
        if (!mounted || _conversation?.id != conversation.id) return;
        final cancelled = token.isCancelled || error is ChatGenerationCancelledException;
        setState(() {
          final index = conversation.messages.indexWhere((m) => m.id == assistantId);
          if (index != -1 && conversation.messages[index].content.isEmpty && conversation.messages[index].attachments.isEmpty) {
            conversation.messages.removeAt(index);
          }
          _generating = false;
          if (identical(_cancelToken, token)) _cancelToken = null;
        });
        await _save();
        if (!cancelled) _snack('Something went wrong. Please try again.');
      },
      onDone: () async {
        if (!mounted || _conversation?.id != conversation.id) return;
        setState(() {
          _generating = false;
          if (identical(_cancelToken, token)) _cancelToken = null;
          conversation.updatedAt = DateTime.now();
        });
        await _save();
        _subscription = null;
        _scrollToBottom();
      },
      cancelOnError: true,
    );
  }

  Future<void> _stop() async {
    _cancelToken?.cancel();
    await _subscription?.cancel();
    if (!mounted) return;
    setState(() {
      _generating = false;
      _cancelToken = null;
    });
    await _save();
  }

  Future<void> _copy(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    _snack('Copied');
  }

  Future<void> _regenerate(ChatMessage message) async {
    if (_generating || _conversation == null) return;
    final index = _conversation!.messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return;
    setState(() => _conversation!.messages = _conversation!.messages.take(index).toList());
    await _save();
    await _generate();
  }

  Future<void> _viewImage(ChatAttachment image) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (_) => _ImageViewer(
        image: image,
        onDownload: () => _downloadImage(image),
        onEdit: () => _editImage(image),
      ),
    );
  }

  Future<void> _downloadImage(ChatAttachment image) async {
    try {
      final saved = await _galleryService.saveToGallery(image);
      _snack(saved ? 'Saved to gallery' : 'Could not save image');
    } catch (_) {
      _snack('Could not save image');
    }
  }

  Future<void> _editImage(ChatAttachment image) async {
    if (_generating || _conversation == null) return;
    final controller = TextEditingController();
    final instruction = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit image'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Describe the change…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Edit')),
        ],
      ),
    );
    controller.dispose();
    if (instruction == null || instruction.isEmpty || !mounted) return;

    setState(() => _generating = true);
    try {
      final result = await _generationService.editImage(source: image, instruction: instruction);
      if (!mounted || _conversation == null) return;
      final now = DateTime.now();
      setState(() {
        _conversation!.messages.add(ChatMessage(
          id: '${now.microsecondsSinceEpoch}_edited',
          content: '',
          role: MessageRole.assistant,
          createdAt: now,
          attachments: [result.image],
          backendContext: result.backendContext,
        ));
        _conversation!.updatedAt = now;
      });
      await _save();
      _scrollToBottom(jump: true);
    } catch (_) {
      _snack('Image edit failed. Please try again.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || (!_nearBottom && !jump)) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _subscription?.cancel();
    _messageController.removeListener(_refreshInput);
    _messageController.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: _ThinkingIndicator(label: 'Loading')));
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: ChatDrawer(
        conversations: _conversations,
        currentConversationId: _conversation?.id,
        onNewChat: _newChat,
        onSelectConversation: _selectChat,
        onTogglePin: _pinChat,
        onRenameConversation: _renameChat,
        onDeleteConversation: _deleteChat,
        onOpenSettings: () {
          Navigator.pop(context);
          _openSettings();
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: _messages.isEmpty ? _welcome() : _messageList()),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: Row(
        children: [
          _HeaderButton(icon: Icons.menu_rounded, onTap: () => _scaffoldKey.currentState?.openDrawer()),
          Expanded(
            child: Column(
              children: [
                Text(_conversation?.title ?? 'CYSTEM', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w650, fontSize: 15)),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF73E6A5), shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    const Text('CYSTEM', style: TextStyle(fontSize: 10, color: AppTheme.textMuted, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          _HeaderButton(icon: Icons.add_rounded, onTap: _generating ? null : _newChat),
        ],
      ),
    );
  }

  Widget _welcome() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [AppTheme.primary.withValues(alpha: 0.26), AppTheme.primary.withValues(alpha: 0.06)]),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 32, color: AppTheme.primarySoft),
              ),
              const SizedBox(height: 22),
              const Text('What are we doing today?', textAlign: TextAlign.center, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, letterSpacing: -0.7)),
              const SizedBox(height: 8),
              Text('Ask anything. Add an image. Search the web. Create something.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 28),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                alignment: WrapAlignment.center,
                children: [
                  _PromptChip(icon: Icons.explore_outlined, text: 'Explore an idea', onTap: () => _usePrompt('Help me explore an idea.')),
                  _PromptChip(icon: Icons.code_rounded, text: 'Write code', onTap: () => _usePrompt('Help me write some code.')),
                  _PromptChip(icon: Icons.language_rounded, text: 'Search the web', onTap: () => _usePrompt('Search the web for the latest important news today.')),
                  _PromptChip(icon: Icons.image_outlined, text: 'Create an image', onTap: () => _usePrompt('Create an image of a futuristic city at night.')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _usePrompt(String prompt) {
    if (_generating) return;
    _messageController.text = prompt;
    _messageController.selection = TextSelection.collapsed(offset: prompt.length);
    _send();
  }

  Widget _messageList() {
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          itemCount: _messages.length,
          itemBuilder: (_, index) {
            final message = _messages[index];
            final isThinking = _generating && index == _messages.length - 1 && message.isAssistant && message.content.isEmpty;
            if (message.isTool) return const SizedBox.shrink();
            return _MessageCard(
              message: message,
              thinking: isThinking,
              onCopy: message.content.isEmpty ? null : () => _copy(message),
              onRegenerate: message.isAssistant && message.content.isNotEmpty ? () => _regenerate(message) : null,
              onViewImage: _viewImage,
              onDownloadImage: _downloadImage,
              onEditImage: _editImage,
            );
          },
        ),
        if (!_nearBottom)
          Positioned(
            right: 18,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'latest',
              onPressed: () {
                _nearBottom = true;
                _scrollToBottom(jump: true);
              },
              child: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ),
      ],
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingAttachments.isNotEmpty) _attachmentStrip(),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(27),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7)),
              boxShadow: const [BoxShadow(blurRadius: 20, offset: Offset(0, 7), color: Color(0x25000000))],
            ),
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: _generating ? 'CYSTEM is thinking…' : 'Message CYSTEM',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(4, 13, 4, 8),
                prefixIcon: IconButton(tooltip: 'Add image', onPressed: _generating ? null : _pickImage, icon: const Icon(Icons.add_rounded)),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 4),
                  child: IconButton.filled(
                    tooltip: _generating ? 'Stop' : 'Send',
                    onPressed: _generating ? _stop : (_canSend ? _send : null),
                    icon: Icon(_generating ? Icons.stop_rounded : Icons.arrow_upward_rounded, size: 19),
                  ),
                ),
              ),
              onSubmitted: (_) {
                if (!_generating && _canSend) _send();
              },
            ),
          ),
          const SizedBox(height: 5),
          Text('CYSTEM can make mistakes. Check important information.', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _attachmentStrip() {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 7),
        itemCount: _pendingAttachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final image = _pendingAttachments[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.memory(decodeAttachmentImage(image), width: 70, height: 70, fit: BoxFit.cover),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  iconSize: 15,
                  onPressed: () => setState(() => _pendingAttachments.removeAt(index)),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 21),
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        shape: const CircleBorder(),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.icon, required this.text, required this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 17),
      label: Text(text),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator({this.label = 'Thinking'});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 3, height: 3),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(width: 7),
              const _Dot(),
              const SizedBox(width: 3),
              const _Dot(),
              const SizedBox(width: 3),
              const _Dot(),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle));
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.thinking,
    required this.onCopy,
    required this.onRegenerate,
    required this.onViewImage,
    required this.onDownloadImage,
    required this.onEditImage,
  });

  final ChatMessage message;
  final bool thinking;
  final VoidCallback? onCopy;
  final VoidCallback? onRegenerate;
  final Future<void> Function(ChatAttachment) onViewImage;
  final Future<void> Function(ChatAttachment) onDownloadImage;
  final Future<void> Function(ChatAttachment) onEditImage;

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: EdgeInsets.only(left: user ? 42 : 0, right: user ? 0 : 20, bottom: 20),
        child: Column(
          crossAxisAlignment: user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.attachments.isNotEmpty) _images(context),
            if (message.content.isNotEmpty)
              Container(
                padding: user ? const EdgeInsets.symmetric(horizontal: 15, vertical: 11) : EdgeInsets.zero,
                decoration: user
                    ? BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(7),
                        ),
                      )
                    : null,
                child: user
                    ? SelectableText(message.content, style: const TextStyle(fontSize: 16, height: 1.45))
                    : MarkdownBody(data: message.content, selectable: true),
              ),
            if (thinking) const Padding(padding: EdgeInsets.only(top: 2), child: _ThinkingIndicator()),
            if (!user && (onCopy != null || onRegenerate != null))
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onCopy != null) _MiniAction(icon: Icons.copy_rounded, tooltip: 'Copy', onTap: onCopy!),
                    if (onRegenerate != null) _MiniAction(icon: Icons.refresh_rounded, tooltip: 'Regenerate', onTap: onRegenerate!),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _images(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: message.attachments.map((image) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  GestureDetector(
                    onTap: () => onViewImage(image),
                    child: Image.memory(
                      decodeAttachmentImage(image),
                      width: 340,
                      height: 320,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(height: 120, child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.64), borderRadius: BorderRadius.circular(18)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ImageAction(icon: Icons.fullscreen_rounded, onTap: () => onViewImage(image)),
                          _ImageAction(icon: Icons.download_rounded, onTap: () => onDownloadImage(image)),
                          _ImageAction(icon: Icons.edit_rounded, onTap: () => onEditImage(image)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(tooltip: tooltip, onPressed: onTap, icon: Icon(icon, size: 16));
}

class _ImageAction extends StatelessWidget {
  const _ImageAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(onPressed: onTap, icon: Icon(icon, size: 18, color: Colors.white));
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.image, required this.onDownload, required this.onEdit});
  final ChatAttachment image;
  final VoidCallback onDownload;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: onDownload, icon: const Icon(Icons.download_rounded)),
          IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_rounded)),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(decodeAttachmentImage(image), fit: BoxFit.contain),
        ),
      ),
    );
  }
}
