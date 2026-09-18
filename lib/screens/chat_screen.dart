import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
import '../widgets/attachment_picker_sheet.dart';
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
  bool _webSearchMode = false;

  List<ChatMessage> get _messages => _chat?.messages ?? const [];

  bool get _canSend =>
      _input.text.trim().isNotEmpty || _pending.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _input.addListener(_changed);
    _scroll.addListener(_scrolled);
    _load();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _scrolled() {
    if (_scroll.hasClients) {
      _nearBottom =
          _scroll.position.maxScrollExtent - _scroll.position.pixels < 180;
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
    _chats.sort(
      (a, b) => a.isPinned != b.isPinned
          ? (a.isPinned ? -1 : 1)
          : b.updatedAt.compareTo(a.updatedAt),
    );
  }

  Future<void> _load() async {
    final chats = await _storage.loadConversations();

    _chats = chats;

    if (_chats.isEmpty) {
      _chats.add(_newChat());
    }

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

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }

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
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
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
        content: Text(
          'Delete "${chat.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (yes != true || !mounted) return;

    setState(() {
      _chats.removeWhere((item) => item.id == chat.id);

      if (_chats.isEmpty) {
        _chats.add(_newChat());
      }

      _sort();
      _chat = _chats.first;
    });

    await _save();
    _scrollToBottom(jump: true);
  }

  Future<void> _pickAttachment() async {
    if (_generating) return;

    try {
      final attachment =
          await showModalBottomSheet<ChatAttachment?>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const AttachmentPickerSheet(),
      );

      if (!mounted || attachment == null) return;

      setState(() {
        _pending = [..._pending, attachment];
      });
    } catch (_) {
      _snack('Could not add attachment');
    }
  }

  Future<void> _send() async {
    if (!_canSend || _generating || _chat == null) return;

    final text = _input.text.trim();
    final now = DateTime.now();
    final attachments = List<ChatAttachment>.from(_pending);

    setState(() {
      _chat!.messages.add(
        ChatMessage(
          id: now.microsecondsSinceEpoch.toString(),
          content: text,
          role: MessageRole.user,
          createdAt: now,
          attachments: attachments,
        ),
      );

      _chat!.updatedAt = now;
      _pending = [];

      if (_chat!.title == 'New Chat') {
        final title = text.isEmpty ? 'Attachment message' : text;

        _chat!.title = title.length > 40
            ? '${title.substring(0, 40)}…'
            : title;
      }
    });

    _input.clear();

    final useWebSearch = _webSearchMode;

    setState(() {
      _webSearchMode = false;
    });

    await _save();
    _scrollToBottom(jump: true);

    await _generateResponse(
      forceWebSearch: useWebSearch,
    );
  }

  Future<void> _generateResponse({
    bool forceWebSearch = false,
  }) async {
    final chat = _chat;

    if (chat == null || _generating) return;

    final id =
        '${DateTime.now().microsecondsSinceEpoch}_assistant';

    final token = ChatCancellationToken();

    setState(() {
      chat.messages.add(
        ChatMessage(
          id: id,
          content: '',
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
        ),
      );

      _generating = true;
      _cancel = token;
      _nearBottom = true;
    });

    await _save();

    var text = '';

    _subscription = _generation
        .generate(
          chat.messages
              .where((message) => message.id != id)
              .toList(),
          cancellationToken: token,
          forceWebSearch: forceWebSearch,
          onToolMessage: (_) async {},
          onGeneratedImage: (image, backendContext) async {
            if (!mounted ||
                token.isCancelled ||
                _chat?.id != chat.id) {
              return;
            }

            final index = chat.messages.indexWhere(
              (message) => message.id == id,
            );

            if (index < 0) return;

            final old = chat.messages[index];

            setState(() {
              chat.messages[index] = old.copyWith(
                attachments: [
                  ...old.attachments,
                  image,
                ],
                backendContext: backendContext,
              );

              chat.updatedAt = DateTime.now();
            });

            await _save();
            _scrollToBottom();
          },
        )
        .listen(
          (event) {
            if (event.hasText) {
              text += event.text!;
            }

            if (!mounted ||
                token.isCancelled ||
                _chat?.id != chat.id) {
              return;
            }

            final index = chat.messages.indexWhere(
              (message) => message.id == id,
            );

            if (index < 0) return;

            final old = chat.messages[index];

            final metadata = event.model == null &&
                    event.responseId == null &&
                    event.finishReason == null &&
                    !event.hasUsage
                ? old.apiMetadata
                : ChatApiMetadata(
                    model: event.model ?? old.apiMetadata?.model,
                    responseId: event.responseId ??
                        old.apiMetadata?.responseId,
                    finishReason: event.finishReason ??
                        old.apiMetadata?.finishReason,
                    promptTokens: event.promptTokens ??
                        old.apiMetadata?.promptTokens,
                    completionTokens: event.completionTokens ??
                        old.apiMetadata?.completionTokens,
                    totalTokens: event.totalTokens ??
                        old.apiMetadata?.totalTokens,
                  );

            setState(() {
              chat.messages[index] = old.copyWith(
                content: text,
                apiMetadata: metadata,
              );

              chat.updatedAt = DateTime.now();
            });

            _scrollToBottom();
          },
          onError: (Object error) async {
            if (!mounted || _chat?.id != chat.id) return;

            final cancelled = token.isCancelled ||
                error is ChatGenerationCancelledException;

            setState(() {
              final index = chat.messages.indexWhere(
                (message) => message.id == id,
              );

              if (index >= 0 &&
                  chat.messages[index].content.isEmpty &&
                  chat.messages[index].attachments.isEmpty) {
                chat.messages.removeAt(index);
              }

              _generating = false;
              _cancel = null;
            });

            await _save();

            if (!cancelled) {
              _snack(
                'Something went wrong. Please try again.',
              );
            }
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
    await Clipboard.setData(
      ClipboardData(text: message.content),
    );

    _snack('Copied');
  }

  Future<void> _regenerate(ChatMessage message) async {
    if (_generating || _chat == null) return;

    final index = _chat!.messages.indexWhere(
      (item) => item.id == message.id,
    );

    if (index < 0) return;

    setState(() {
      _chat!.messages = _chat!.messages.take(index).toList();
    });

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
        onOpenSource: image.sourceUrl == null
            ? null
            : () => _openSource(image.sourceUrl!),
      ),
    );
  }

  Future<void> _download(ChatAttachment image) async {
    try {
      final ok = await _gallery.saveToGallery(image);

      _snack(
        ok ? 'Saved to gallery' : 'Could not save image',
      );
    } catch (_) {
      _snack('Could not save image');
    }
  }

  Future<void> _openSource(String url) async {
    final uri = Uri.tryParse(url);

    if (uri == null ||
        !await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        )) {
      _snack('Could not open source');
    }
  }

  void _scrollToBottom({bool jump = false}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (jump) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final messages = _messages;
    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        title: Text(_chat?.title ?? 'CYSTEM'),
        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed: _newConversation,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: message.role == MessageRole.user
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: SelectableText(message.content),
                  ),
                );
              },
            ),
          ),
          if (_pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('${_pending.length} attachment(s) selected'),
            ),
          SafeArea(
            child: Row(
              children: [
                IconButton(
                  onPressed: _generating ? null : _pickAttachment,
                  icon: const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_generating,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Message CYSTEM…',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  onPressed: _canSend && !_generating ? _send : null,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({
    required this.image,
    required this.onDownload,
    required this.onOpenSource,
  });

  final ChatAttachment image;
  final VoidCallback onDownload;
  final VoidCallback? onOpenSource;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Text(image.fileName),
      actions: [
        TextButton(onPressed: onDownload, child: const Text('Save')),
        if (onOpenSource != null)
          TextButton(onPressed: onOpenSource, child: const Text('Open source')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
