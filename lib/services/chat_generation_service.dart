import '../models/chat_message.dart';
import '../models/chat_stream_event.dart';
import '../models/chat_tool_call.dart';
import 'chat_tool_executor.dart';
import 'chat_tool_registry.dart';
import 'nvidia_api_service.dart';

/// Orchestrates Kimi K3 responses and model-requested tools.
///
/// The API service remains responsible only for HTTP/SSE. This layer handles
/// the multi-turn tool loop: assistant tool call -> local execution -> tool
/// result -> next K3 request.
class ChatGenerationService {
  ChatGenerationService({
    NvidiaApiService? apiService,
    ChatToolRegistry? toolRegistry,
    ChatToolExecutor? toolExecutor,
  })  : _apiService = apiService ?? NvidiaApiService(),
        _toolRegistry = toolRegistry ?? ChatToolRegistry(),
        _toolExecutor = toolExecutor ?? const UnavailableToolExecutor();

  static const int maxToolRounds = 8;

  final NvidiaApiService _apiService;
  final ChatToolRegistry _toolRegistry;
  final ChatToolExecutor _toolExecutor;

  ChatToolRegistry get toolRegistry => _toolRegistry;

  Stream<ChatStreamEvent> generate(
    List<ChatMessage> messages, {
    Future<void> Function(ChatMessage message)? onToolMessage,
  }) async* {
    var rounds = 0;

    while (true) {
      if (rounds++ >= maxToolRounds) {
        throw const NvidiaApiException(
          'The tool-call loop exceeded the safety limit.',
        );
      }

      final events = <ChatStreamEvent>[];
      await for (final event in _apiService.streamMessage(
        List<ChatMessage>.of(messages),
        tools: _toolRegistry.tools,
      )) {
        events.add(event);
        yield event;
      }

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
        final result = await _toolExecutor.execute(call);
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

  String _assistantText(List<ChatStreamEvent> events) => events
      .where((event) => event.hasText)
      .map((event) => event.text!)
      .join();

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
