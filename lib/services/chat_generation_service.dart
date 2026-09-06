import '../models/chat_message.dart';
import '../models/chat_stream_event.dart';
import '../models/chat_tool_call.dart';
import 'chat_cancellation_token.dart';
import 'chat_tool_argument_validator.dart';
import 'chat_tool_executor.dart';
import 'chat_tool_registry.dart';
import 'nvidia_api_service.dart';

/// Orchestrates Nemotron responses and model-requested tools.
class ChatGenerationService {
  ChatGenerationService({
    NvidiaApiService? apiService,
    ChatToolRegistry? toolRegistry,
    ChatToolExecutor? toolExecutor,
    ChatToolArgumentValidator? argumentValidator,
  })  : _apiService = apiService ?? NvidiaApiService(),
        _toolRegistry = toolRegistry ?? ChatToolRegistry(),
        _toolExecutor = toolExecutor ?? const UnavailableToolExecutor(),
        _argumentValidator = argumentValidator ?? const ChatToolArgumentValidator();

  static const int maxToolRounds = 8;

  final NvidiaApiService _apiService;
  final ChatToolRegistry _toolRegistry;
  final ChatToolExecutor _toolExecutor;
  final ChatToolArgumentValidator _argumentValidator;

  ChatToolRegistry get toolRegistry => _toolRegistry;

  Stream<ChatStreamEvent> generate(
    List<ChatMessage> messages, {
    Future<void> Function(ChatMessage message)? onToolMessage,
    Future<void> Function(ChatToolCall call)? onToolStart,
    ChatCancellationToken? cancellationToken,
  }) async* {
    final token = cancellationToken ?? ChatCancellationToken();
    var rounds = 0;

    while (true) {
      token.throwIfCancelled();
      if (rounds++ >= maxToolRounds) {
        throw const NvidiaApiException('The tool-call loop exceeded the safety limit.');
      }

      final events = <ChatStreamEvent>[];
      await for (final event in _apiService.streamMessage(
        List<ChatMessage>.of(messages),
        tools: _toolRegistry.tools,
        cancellationToken: token,
      )) {
        token.throwIfCancelled();
        events.add(event);
        yield event;
      }

      token.throwIfCancelled();
      final toolCalls = _completedToolCalls(events);
      if (toolCalls.isEmpty) return;

      final assistantMessage = ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}_tool_assistant',
        content: _assistantText(events),
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
        reasoningContent: _assistantReasoning(events),
        toolCalls: toolCalls,
        apiMetadata: _metadata(events),
      );
      messages.add(assistantMessage);
      if (onToolMessage != null) await onToolMessage(assistantMessage);

      for (final call in toolCalls) {
        token.throwIfCancelled();
        final tool = _toolRegistry.find(call.name);
        if (tool == null) {
          throw NvidiaApiException('Nemotron requested an unavailable tool: ${call.name}.');
        }
        try {
          _argumentValidator.validate(tool, call);
        } on FormatException catch (error) {
          throw NvidiaApiException('Invalid JSON arguments for ${call.name}: $error');
        }

        if (onToolStart != null) await onToolStart(call);
        if (onToolMessage != null) {
          final label = call.name == 'web_search'
              ? '⏳ Searching the web…'
              : '⏳ Running ${call.name}…';
          await onToolMessage(ChatMessage(
            id: '${DateTime.now().microsecondsSinceEpoch}_tool_status_${call.id}',
            content: label,
            role: MessageRole.tool,
            createdAt: DateTime.now(),
            toolCallId: call.id,
            toolName: call.name,
          ));
        }

        String result;
        try {
          result = await _toolExecutor.execute(call);
        } catch (error) {
          token.throwIfCancelled();
          result = call.name == 'web_search'
              ? 'Web search failed: $error\n\nPlease try the search again with a different query.'
              : 'Tool execution failed: $error';
        }
        token.throwIfCancelled();
        final toolMessage = ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}_tool_result_${call.id}',
          content: result,
          role: MessageRole.tool,
          createdAt: DateTime.now(),
          toolCallId: call.id,
          toolName: call.name,
        );
        messages.add(toolMessage);
        if (onToolMessage != null) await onToolMessage(toolMessage);
      }
    }
  }

  List<ChatToolCall> _completedToolCalls(List<ChatStreamEvent> events) {
    final byId = <String, ChatToolCall>{};
    for (final event in events) {
      for (final call in event.toolCalls) {
        byId[call.id] = call;
      }
    }
    return byId.values.toList();
  }

  String _assistantText(List<ChatStreamEvent> events) =>
      events.where((event) => event.hasText).map((event) => event.text!).join();

  String? _assistantReasoning(List<ChatStreamEvent> events) {
    final value = events
        .where((event) => event.hasReasoning)
        .map((event) => event.reasoning!)
        .join();
    return value.isEmpty ? null : value;
  }

  ChatApiMetadata? _metadata(List<ChatStreamEvent> events) {
    ChatStreamEvent? latest;
    for (final event in events.reversed) {
      if (event.responseId != null ||
          event.model != null ||
          event.finishReason != null ||
          event.hasUsage) {
        latest = event;
        break;
      }
    }
    if (latest == null) return null;
    return ChatApiMetadata(
      responseId: latest.responseId,
      model: latest.model,
      finishReason: latest.finishReason,
      promptTokens: latest.promptTokens,
      completionTokens: latest.completionTokens,
      totalTokens: latest.totalTokens,
    );
  }
}
