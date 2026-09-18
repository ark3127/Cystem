import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/models/chat_message.dart';
import 'package:cystem/models/chat_tool_call.dart';

void main() {
  test('round-trips reasoning, tool calls and API metadata', () {
    final original = ChatMessage(
      id: 'm1',
      content: 'done',
      role: MessageRole.assistant,
      createdAt: DateTime.utc(2026, 1, 1),
      reasoningContent: 'reasoned',
      toolCalls: const [
        ChatToolCall(
          id: 'call_1',
          name: 'open_url',
          arguments: '{"url":"https://example.com"}',
        ),
      ],
      apiMetadata: const ChatApiMetadata(
        responseId: 'resp_1',
        model: 'moonshotai/kimi-k3',
        finishReason: 'stop',
        promptTokens: 10,
        completionTokens: 5,
        totalTokens: 15,
      ),
    );

    final decoded = ChatMessage.fromJson(original.toJson());

    expect(decoded.reasoningContent, 'reasoned');
    expect(decoded.toolCalls.single.name, 'open_url');
    expect(decoded.apiMetadata?.totalTokens, 15);
  });
}
