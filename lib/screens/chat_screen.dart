import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _storage = ChatStorageService();
  final _images = ImageAttachmentService();
  final _gallery = ImageGalleryService();
  final _generation = ChatGenerationService(
    toolRegistry: AppToolRegistry.create(),
    toolExecutor: AppToolExecutor(),
  );
  final _scaffold = GlobalKey<ScaffoldState>();

  StreamSubscription<ChatStreamEvent>? _subscription;
  ChatCancellationToken? _cancel;
  List<ChatConversation> _chats = [];
  ChatConversation? _chat;
  List<ChatAttachment> _pending = [];
  bool _loading = true;
  bool _generating = false;
  bool _nearBottom = true;

  List<ChatMessage> get _messages => _chat?.messages ?? const [];
  bool get _canSend => _input.text.trim().isNotEmpty || _pending.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _input.addListener(_changed);
    _scroll.addListener(_scrolled);
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _scrolled() {
    if (_scroll.hasClients) {
      _nearBottom = _scroll.position.maxScrollExtent - _scroll.position.pixels < 180;
    }
  }

  ChatConversation _newChat() {
    final now = DateTime.now();
    return ChatConversation(
      id: now.microsecondsSinceEpoch.toString(),
      title: 'New Chat',
      createdAt: now,
      updatedAt: now,
    );
  }

  void _sort() {
    _chats.sort((a, b) => a.isPinned != b.isPinned
        ? (a.isPinned ? -1 : 1)
        : b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _load() async {
    final chats = await _storage.loadConversations();
    _chats = chats;
    if (_chats.isEmpty) _chats.add(_newChat());
    _sort();
    await _storage.saveConversations(_chats);
    if (!mounted) return;
    setState(() {
      _chat = _chats.first;
      _loading = false;
    });
    _scrollToBottom(jump: true);
  }

  Future<void> _save() async {
    _sort();
    await _storage.saveConversations(_chats);
  }

  Future<void> _newConversation() async {
    if (_generating) return;
    final chat = _newChat();
    setState(() {
      _chats.add(chat);
      _chat = chat;
      _pending = [];
    });
    await _save();
    _scrollToBottom(jump: true);
  }

  Future<void> _select(ChatConversation chat) async {
    if (_generating) return;
    setState(() {
      _chat = chat;
      _pending = [];
    });
    if (mounted && Navigator.of(context).canPop()) Navigator.pop(context);
    _scrollToBottom(jump: true);
  }

  Future<void> _pin(ChatConversation chat) async {
    if (_generating) return;
    setState(() {
      chat.isPinned = !chat.isPinned;
      chat.updatedAt = DateTime.now();
    });
    await _save();
  }

  Future<void> _rename(ChatConversation chat) async {
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

  Future<void> _delete(ChatConversation chat) async {
    if (_generating) return;
    final yes = await showDialog<bool>(
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
    if (yes != true || !mounted) return;
    setState(() {
      _chats.removeWhere((item) => item.id == chat.id);
      if (_chats.isEmpty) _chats.add(_newChat());
      _sort();
      _chat = _chats.first;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final image = await _images.pickImage(source);
      if (image != null && mounted) setState(() => _pending = [..._pending, image]);
    } catch (_) {
      _snack('Could not add image');
    }
  }

  Future<void> _send() async {
    if (!_canSend || _generating || _chat == null) return;
    final text = _input.text.trim();
    final now = DateTime.now();
    final attachments = List<ChatAttachment>.from(_pending);
    setState(() {
      _chat!.messages.add(ChatMessage(
        id: now.microsecondsSinceEpoch.toString(),
        content: text,
        role: MessageRole.user,
        createdAt: now,
        attachments: attachments,
      ));
      _chat!.updatedAt = now;
      _pending = [];
      if (_chat!.title == 'New Chat') {
        final title = text.isEmpty ? 'Image message' : text;
        _chat!.title = title.length > 40 ? '${title.substring(0, 40)}…' : title;
      }
    });
    _input.clear();
    await _save();
    _scrollToBottom(jump: true);
    await _generateResponse();
  }

  Future<void> _generateResponse() async {
    final chat = _chat;
    if (chat == null || _generating) return;
    final id = '${DateTime.now().microsecondsSinceEpoch}_assistant';
    final token = ChatCancellationToken();
    setState(() {
      chat.messages.add(ChatMessage(
        id: id,
        content: '',
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      ));
      _generating = true;
      _cancel = token;
      _nearBottom = true;
    });
    await _save();

    var text = '';
    _subscription = _generation.generate(
      chat.messages.where((message) => message.id != id).toList(),
      cancellationToken: token,
      onToolMessage: (_) async {},
      onGeneratedImage: (image, backendContext) async {
        if (!mounted || token.isCancelled || _chat?.id != chat.id) return;
        final index = chat.messages.indexWhere((message) => message.id == id);
        if (index < 0) return;
        final old = chat.messages[index];
        setState(() {
          chat.messages[index] = old.copyWith(
            attachments: [...old.attachments, image],
            backendContext: backendContext,
          );
          chat.updatedAt = DateTime.now();
        });
        await _save();
        _scrollToBottom();
      },
    ).listen(
      (event) {
        if (event.hasText) text += event.text!;
        if (!mounted || token.isCancelled || _chat?.id != chat.id) return;
        final index = chat.messages.indexWhere((message) => message.id == id);
        if (index < 0) return;
        final old = chat.messages[index];
        final metadata = event.model == null &&
                event.responseId == null &&
                event.finishReason == null &&
                !event.hasUsage
            ? old.apiMetadata
            : ChatApiMetadata(
                model: event.model ?? old.apiMetadata?.model,
                responseId: event.responseId ?? old.apiMetadata?.responseId,
                finishReason: event.finishReason ?? old.apiMetadata?.finishReason,
                promptTokens: event.promptTokens ?? old.apiMetadata?.promptTokens,
                completionTokens: event.completionTokens ?? old.apiMetadata?.completionTokens,
                totalTokens: event.totalTokens ?? old.apiMetadata?.totalTokens,
              );
        setState(() {
          chat.messages[index] = old.copyWith(content: text, apiMetadata: metadata);
          chat.updatedAt = DateTime.now();
        });
        _scrollToBottom();
      },
      onError: (Object error) async {
        if (!mounted || _chat?.id != chat.id) return;
        final cancelled = token.isCancelled || error is ChatGenerationCancelledException;
        setState(() {
          final index = chat.messages.indexWhere((message) => message.id == id);
          if (index >= 0 && chat.messages[index].content.isEmpty && chat.messages[index].attachments.isEmpty) {
            chat.messages.removeAt(index);
          }
          _generating = false;
          _cancel = null;
        });
        await _save();
        if (!cancelled) _snack('Something went wrong. Please try again.');
      },
      onDone: () async {
        if (!mounted || _chat?.id != chat.id) return;
        setState(() {
          _generating = false;
          _cancel = null;
          chat.updatedAt = DateTime.now();
        });
        await _save();
        _subscription = null;
        _scrollToBottom();
      },
      cancelOnError: true,
    );
  }

  Future<void> _stop() async {
    _cancel?.cancel();
    await _subscription?.cancel();
    if (!mounted) return;
    setState(() {
      _generating = false;
      _cancel = null;
    });
    await _save();
  }

  Future<void> _copy(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    _snack('Copied');
  }

  Future<void> _regenerate(ChatMessage message) async {
    if (_generating || _chat == null) return;
    final index = _chat!.messages.indexWhere((item) => item.id == message.id);
    if (index < 0) return;
    setState(() => _chat!.messages = _chat!.messages.take(index).toList());
    await _save();
    await _generateResponse();
  }

  Future<void> _viewImage(ChatAttachment image) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .94),
      builder: (_) => _ImageViewer(
        image: image,
        onDownload: () => _download(image),
        onEdit: () => _editImage(image),
        onOpenSource: image.sourceUrl == null ? null : () => _openSource(image.sourceUrl!),
      ),
    );
  }

  Future<void> _download(ChatAttachment image) async {
    try {
      final ok = await _gallery.saveToGallery(image);
      _snack(ok ? 'Saved to gallery' : 'Could not save image');
    } catch (_) {
      _snack('Could not save image');
    }
  }

  Future<void> _openSource(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Could not open source');
    }
  }

  Future<void> _editImage(ChatAttachment image) async {
    if (_generating || _chat == null) return;
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
      final result = await _generation.editImage(source: image, instruction: instruction);
      final now = DateTime.now();
      if (!mounted || _chat == null) return;
      setState(() {
        _chat!.messages.add(ChatMessage(
          id: '${now.microsecondsSinceEpoch}_edited',
          content: '',
          role: MessageRole.assistant,
          createdAt: now,
          attachments: [result.image],
          backendContext: result.backendContext,
        ));
        _chat!.updatedAt = now;
      });
      await _save();
      _scrollToBottom(jump: true);
    } catch (_) {
      _snack('Image edit failed. Please try again.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || (!_nearBottom && !jump)) return;
      final position = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(position);
      } else {
        _scroll.animateTo(
          position,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _settings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _subscription?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: _Thinking(label: 'Loading')));
    }
    return Scaffold(
      key: _scaffold,
      drawer: ChatDrawer(
        conversations: _chats,
        currentConversationId: _chat?.id,
        onNewChat: _newConversation,
        onSelectConversation: _select,
        onTogglePin: _pin,
        onRenameConversation: _rename,
        onDeleteConversation: _delete,
        onOpenSettings: () {
          Navigator.pop(context);
          _settings();
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: _messages.isEmpty ? _welcome() : _list()),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final surface = Theme.of(context).colorScheme.surfaceContainer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _scaffold.currentState?.openDrawer(),
            icon: const Icon(Icons.menu_rounded),
            style: IconButton.styleFrom(backgroundColor: surface, shape: const CircleBorder()),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _chat?.title ?? 'CYSTEM',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                const Text(
                  'CYSTEM  •  NEMOTRON',
                  style: TextStyle(fontSize: 9, letterSpacing: 1.1, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _generating ? null : _newConversation,
            icon: const Icon(Icons.add_rounded),
            style: IconButton.styleFrom(backgroundColor: surface, shape: const CircleBorder()),
          ),
        ],
      ),
    );
  }

  Widget _welcome() {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: .1),
                border: Border.all(color: AppTheme.primary.withValues(alpha: .2)),
              ),
              child: const Icon(Icons.auto_awesome_rounded, size: 32, color: AppTheme.primarySoft),
            ),
            const SizedBox(height: 22),
            const Text(
              'What are we doing today?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, letterSpacing: -.7),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask anything, search the web, share an image, or create one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 26),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: const [
                _Chip(icon: Icons.lightbulb_outline_rounded, label: 'Explore an idea'),
                _Chip(icon: Icons.code_rounded, label: 'Write code'),
                _Chip(icon: Icons.language_rounded, label: 'Search the web'),
                _Chip(icon: Icons.image_outlined, label: 'Create an image'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: _messages.length,
          itemBuilder: (_, index) {
            final message = _messages[index];
            if (message.isTool) return const SizedBox.shrink();
            return _Message(
              message: message,
              thinking: _generating &&
                  index == _messages.length - 1 &&
                  message.isAssistant &&
                  message.content.isEmpty,
              onCopy: message.isAssistant && message.content.isNotEmpty ? () => _copy(message) : null,
              onRegenerate: message.isAssistant && message.content.isNotEmpty ? () => _regenerate(message) : null,
              onViewImage: _viewImage,
              onDownload: _download,
              onEditImage: _editImage,
            );
          },
        ),
        if (!_nearBottom)
          Positioned(
            right: 18,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'bottom',
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
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pending.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pending.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.memory(
                        decodeAttachmentImage(_pending[index]),
                        width: 68,
                        height: 68,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        iconSize: 15,
                        onPressed: () => setState(() => _pending.removeAt(index)),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: .7)),
              boxShadow: const [BoxShadow(blurRadius: 18, offset: Offset(0, 6), color: Color(0x24000000))],
            ),
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _generating ? 'CYSTEM is thinking…' : 'Message CYSTEM',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(4, 13, 4, 8),
                prefixIcon: IconButton(
                  onPressed: _generating ? null : _pickImage,
                  icon: const Icon(Icons.add_rounded),
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 4),
                  child: IconButton.filled(
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
          Text(
            'CYSTEM can make mistakes. Check important information.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      onPressed: null,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(width: 7),
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.message,
    required this.thinking,
    required this.onCopy,
    required this.onRegenerate,
    required this.onViewImage,
    required this.onDownload,
    required this.onEditImage,
  });

  final ChatMessage message;
  final bool thinking;
  final VoidCallback? onCopy;
  final VoidCallback? onRegenerate;
  final Future<void> Function(ChatAttachment) onViewImage;
  final Future<void> Function(ChatAttachment) onDownload;
  final Future<void> Function(ChatAttachment) onEditImage;

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: EdgeInsets.only(left: user ? 42 : 0, right: user ? 0 : 18, bottom: 20),
        child: Column(
          crossAxisAlignment: user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            for (final image in message.attachments)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(19),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      GestureDetector(
                        onTap: () => onViewImage(image),
                        child: Image.memory(
                          decodeAttachmentImage(image),
                          width: 340,
                          height: 320,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            height: 100,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .65),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ImageButton(Icons.fullscreen_rounded, () => onViewImage(image)),
                            _ImageButton(Icons.download_rounded, () => onDownload(image)),
                            _ImageButton(Icons.edit_rounded, () => onEditImage(image)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (message.content.isNotEmpty)
              Container(
                padding: user ? const EdgeInsets.symmetric(horizontal: 15, vertical: 11) : EdgeInsets.zero,
                decoration: user
                    ? BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: .16),
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
            if (thinking)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: _Thinking(label: 'Thinking'),
              ),
            if (!user && (onCopy != null || onRegenerate != null))
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onCopy != null)
                    IconButton(tooltip: 'Copy', onPressed: onCopy, icon: const Icon(Icons.copy_rounded, size: 16)),
                  if (onRegenerate != null)
                    IconButton(tooltip: 'Regenerate', onPressed: onRegenerate, icon: const Icon(Icons.refresh_rounded, size: 17)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageButton extends StatelessWidget {
  const _ImageButton(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({
    required this.image,
    required this.onDownload,
    required this.onEdit,
    required this.onOpenSource,
  });

  final ChatAttachment image;
  final VoidCallback onDownload;
  final VoidCallback onEdit;
  final VoidCallback? onOpenSource;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          if (onOpenSource != null)
            IconButton(tooltip: 'Open source', onPressed: onOpenSource, icon: const Icon(Icons.open_in_new_rounded)),
          IconButton(tooltip: 'Download', onPressed: onDownload, icon: const Icon(Icons.download_rounded)),
          IconButton(tooltip: 'Edit', onPressed: onEdit, icon: const Icon(Icons.edit_rounded)),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: .5,
          maxScale: 5,
          child: Image.memory(decodeAttachmentImage(image), fit: BoxFit.contain),
        ),
      ),
    );
  }
}
