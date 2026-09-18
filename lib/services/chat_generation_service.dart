import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/chat_stream_event.dart';
import '../models/chat_tool_call.dart';
import 'chat_cancellation_token.dart';
import 'chat_tool_argument_validator.dart';
import 'chat_tool_executor.dart';
import 'chat_tool_registry.dart';
import 'gemini_image_generation_service.dart';
import 'gemini_vision_service.dart';
import 'nvidia_api_service.dart';
import 'web_search_service.dart';

class ChatGenerationService {
  ChatGenerationService({NvidiaApiService? apiService, ChatToolRegistry? toolRegistry, ChatToolExecutor? toolExecutor, ChatToolArgumentValidator? argumentValidator, GeminiVisionService? visionService, GeminiImageGenerationService? imageGenerationService, WebSearchService? webSearchService}) : _apiService = apiService ?? NvidiaApiService(), _toolRegistry = toolRegistry ?? ChatToolRegistry(), _toolExecutor = toolExecutor ?? const UnavailableToolExecutor(), _argumentValidator = argumentValidator ?? const ChatToolArgumentValidator(), _visionService = visionService ?? GeminiVisionService(), _imageGenerationService = imageGenerationService ?? GeminiImageGenerationService(), _webSearchService = webSearchService ?? WebSearchService();

  static const int maxToolRounds = 8;
  final NvidiaApiService _apiService;
  final ChatToolRegistry _toolRegistry;
  final ChatToolExecutor _toolExecutor;
  final ChatToolArgumentValidator _argumentValidator;
  final GeminiVisionService _visionService;
  final GeminiImageGenerationService _imageGenerationService;
  final WebSearchService _webSearchService;
  ChatToolRegistry get toolRegistry => _toolRegistry;

  Future<GeminiImageGenerationResult> editImage({required ChatAttachment source, required String instruction}) => _imageGenerationService.editImage(source: source, instruction: instruction);

  Stream<ChatStreamEvent> generate(List<ChatMessage> messages, {Future<void> Function(ChatMessage message)? onToolMessage, Future<void> Function(ChatToolCall call)? onToolStart, Future<void> Function(ChatAttachment image, String? backendContext)? onGeneratedImage, ChatCancellationToken? cancellationToken, bool forceWebSearch = false}) async* {
    final token = cancellationToken ?? ChatCancellationToken();
    final wantsImage = _latestUserRequestsImage(messages);
    final wantsWebImages = _latestUserRequestsWebImage(messages);
    // forceWebSearch (from an explicit "search the web" toggle in the UI)
    // always wins over the regex guess, and skips it entirely so a user who
    // deliberately asked for a search always gets a real attempt.
    final wantsWebSearch = !wantsImage && !wantsWebImages && (forceWebSearch || _latestUserRequestsWebSearch(messages));
    final prepared = <ChatMessage>[];
    for (final message in messages) {
      token.throwIfCancelled();
      if (message.isUser && message.attachments.isNotEmpty) {
        final vision = await _visionService.analyzeImages(message.attachments);
        token.throwIfCancelled();
        prepared.add(message.copyWith(content: _withVisionContext(message.content, vision), attachments: const []));
      } else {
        prepared.add(message.copyWith(attachments: const []));
      }
    }
    if (wantsWebImages) {
      final images = await _webSearchService.searchImages(_latestUserText(messages));
      token.throwIfCancelled();
      for (final image in images) await onGeneratedImage?.call(image, null);
      return;
    }
    if (wantsWebSearch) {
      final result = await _webSearchService.search(_latestUserText(messages));
      token.throwIfCancelled();
      // A failed search (quota, auth, network, etc.) is an app-level fact,
      // not conversational content. Never forward the raw service-error
      // string to Nemotron: without a real tool call to anchor it, the
      // model has no reliable way to know it's an error report rather than
      // something to riff on, and it will improvise (wrong identity, wrong
      // knowledge-cutoff claims, exposed internal error codes). Instead,
      // report the failure directly and skip the model call entirely.
      if (_isServiceError(result)) {
        yield ChatStreamEvent(text: _userFacingSearchError(result));
        return;
      }
      prepared.add(
        ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}_search',
          content: '[WEB SEARCH CONTEXT — PRIVATE]\n$result\n[END WEB SEARCH CONTEXT]',
          // `system`, not `user`: this is app-injected context, never
          // something the human typed, and must not be mistaken for it.
          role: MessageRole.system,
          createdAt: DateTime.now(),
        ),
      );
    }
    var rounds = 0;
    while (true) {
      token.throwIfCancelled();
      if (rounds++ >= maxToolRounds) throw const NvidiaApiException('Tool-call safety limit exceeded.');
      final events = <ChatStreamEvent>[];
      await for (final event in _apiService.streamMessage(_messagesForNemotron(prepared, imageRequest: wantsImage), tools: (wantsImage || wantsWebSearch) ? const [] : _toolRegistry.tools, cancellationToken: token)) {
        token.throwIfCancelled();
        events.add(event);
        yield ChatStreamEvent(text: wantsImage ? null : event.text, toolCalls: event.toolCalls, responseId: event.responseId, model: event.model, finishReason: event.finishReason, promptTokens: event.promptTokens, completionTokens: event.completionTokens, totalTokens: event.totalTokens);
      }
      final calls = _completedToolCalls(events);
      if (calls.isEmpty) {
        if (wantsImage) {
          final prompt = _assistantText(events).trim();
          if (prompt.isEmpty) throw const NvidiaApiException('Nemotron produced no image prompt.');
          final generated = await _imageGenerationService.generateImage(prompt);
          token.throwIfCancelled();
          await onGeneratedImage?.call(generated.image, generated.backendContext);
        }
        return;
      }
      prepared.add(ChatMessage(id: '${DateTime.now().microsecondsSinceEpoch}_assistant_tool', content: _assistantText(events), role: MessageRole.assistant, createdAt: DateTime.now(), reasoningContent: _assistantReasoning(events), toolCalls: calls, apiMetadata: _metadata(events)));
      for (final call in calls) {
        token.throwIfCancelled();
        final tool = _toolRegistry.find(call.name);
        if (tool == null) throw NvidiaApiException('Unavailable tool: ${call.name}.');
        _argumentValidator.validate(tool, call);
        await onToolStart?.call(call);
        String result;
        try { result = await _toolExecutor.execute(call); } catch (error) { result = 'Tool execution failed: $error'; }
        prepared.add(ChatMessage(id: '${DateTime.now().microsecondsSinceEpoch}_tool_${call.id}', content: result, role: MessageRole.tool, createdAt: DateTime.now(), toolCallId: call.id, toolName: call.name));
      }
    }
  }

  List<ChatMessage> _messagesForNemotron(List<ChatMessage> messages, {required bool imageRequest}) => messages.asMap().entries.map((entry) {
    final message = entry.value;
    var content = message.content;
    final context = message.backendContext?.trim();
    if (context != null && context.isNotEmpty) content += '\n\n[PRIVATE GEMINI CONTEXT]\n$context\n[END PRIVATE GEMINI CONTEXT]';
    if (imageRequest && entry.key == messages.length - 1 && message.isUser) content += '\n\n[PRIVATE IMAGE PROMPT TASK]\nCreate only a detailed prompt for the image model. Do not answer the user, mention Gemini, mention this task, or claim an image was generated.\n[END PRIVATE IMAGE PROMPT TASK]';
    return message.copyWith(content: content);
  }).toList();

  bool _isServiceError(String result) => result.startsWith('[SERVICE ERROR]');

  /// Turns a `[SERVICE ERROR]` block into a short, on-brand message shown
  /// directly to the user — without leaking status codes or the fact that
  /// Gemini is the underlying search provider.
  String _userFacingSearchError(String serviceError) {
    final retryable = serviceError.contains('Retryable: true');
    return retryable
        ? "I couldn't reach web search just now (it's temporarily unavailable) — please try again in a moment."
        : "Web search isn't available right now. Check the Gemini API key in Settings if this keeps happening.";
  }

  String _latestUserText(List<ChatMessage> messages) { for (var i = messages.length - 1; i >= 0; i--) if (messages[i].isUser) return messages[i].content.trim(); return ''; }
  bool _latestUserRequestsImage(List<ChatMessage> messages) => _match(_latestUserText(messages), r'\b(generate|create|draw|make|render|design|produce|paint|illustrate)\b[\s\S]{0,100}\b(image|picture|photo|illustration|artwork|wallpaper|logo|poster|diagram)\b|\b(image|picture|photo|illustration|artwork|wallpaper|logo|poster|diagram)\b[\s\S]{0,50}\b(generate|create|draw|make|render|design|produce)\b');
  bool _latestUserRequestsWebImage(List<ChatMessage> messages) => _match(_latestUserText(messages), r'\b(find|show|get|search|look up|fetch)\b[\s\S]{0,100}\b(images?|pictures?|photos?|wallpaper|illustration)\b|\b(images?|pictures?|photos?)\b[\s\S]{0,70}\b(from|on|using)\b[\s\S]{0,40}\b(internet|web|online)\b');
  bool _latestUserRequestsWebSearch(List<ChatMessage> messages) => _match(_latestUserText(messages), r"\b(search|look up|browse|find out|check)\b[\s\S]{0,70}\b(internet|web|online|news|latest|current|today|recent)\b|\b(internet|web)\b[\s\S]{0,40}\b(search|browse|look up)\b|\bwhat(?:'s| is)\b[\s\S]{0,30}\b(happening|latest|recent)\b");
  bool _match(String text, String pattern) => text.isNotEmpty && RegExp(pattern, caseSensitive: false).hasMatch(text);
  String _withVisionContext(String text, String analysis) => '${text.trim().isEmpty ? '(No text was provided with the image.)' : text.trim()}\n\n[PRIVATE GEMINI VISION CONTEXT]\n$analysis\n[END PRIVATE GEMINI VISION CONTEXT]';
  List<ChatToolCall> _completedToolCalls(List<ChatStreamEvent> events) { final calls = <String, ChatToolCall>{}; for (final event in events) for (final call in event.toolCalls) calls[call.id] = call; return calls.values.toList(); }
  String _assistantText(List<ChatStreamEvent> events) => events.where((event) => event.hasText).map((event) => event.text!).join();
  String? _assistantReasoning(List<ChatStreamEvent> events) { final value = events.where((event) => event.hasReasoning).map((event) => event.reasoning!).join(); return value.isEmpty ? null : value; }
  ChatApiMetadata? _metadata(List<ChatStreamEvent> events) { for (final event in events.reversed) if (event.responseId != null || event.model != null || event.finishReason != null || event.hasUsage) return ChatApiMetadata(responseId: event.responseId, model: event.model, finishReason: event.finishReason, promptTokens: event.promptTokens, completionTokens: event.completionTokens, totalTokens: event.totalTokens); return null; }
}
