import 'chat_message.dart';

/// Parsed non-streaming Kimi K3 chat-completion result.
class ChatCompletionResult {
  final ChatMessage message;
  final String? responseId;
  final String? model;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  const ChatCompletionResult({
    required this.message,
    this.responseId,
    this.model,
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  bool get hasUsage =>
      promptTokens != null || completionTokens != null || totalTokens != null;
}
