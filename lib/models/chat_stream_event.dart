import 'chat_tool_call.dart';

/// A single semantic event emitted while Kimi K3 streams a response.
class ChatStreamEvent {
  final String? text;
  final String? reasoning;
  final List<ChatToolCall> toolCalls;
  final String? responseId;
  final String? model;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  const ChatStreamEvent({
    this.text,
    this.reasoning,
    this.toolCalls = const [],
    this.responseId,
    this.model,
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  bool get hasText => text != null && text!.isNotEmpty;
  bool get hasReasoning => reasoning != null && reasoning!.isNotEmpty;
  bool get hasToolCalls => toolCalls.isNotEmpty;
  bool get hasUsage =>
      promptTokens != null || completionTokens != null || totalTokens != null;
}
