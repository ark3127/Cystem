import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/models/chat_message.dart';
import 'package:cystem/models/chat_response_format.dart';
import 'package:cystem/models/chat_tool.dart';
import 'package:cystem/models/chat_tool_call.dart';

void main() {
  group('ChatResponseFormat', () {
    test('serializes JSON schema format', () {
      final format = ChatResponseFormat.jsonSchema(
        name: 'person',
        schema: {
          'type': 'object',
          'properties': {'name': {'type': 'string'}},
          'required': ['name'],
          'additionalProperties': false,
        },
      );

      expect(format.toApiJson()['type'], 'json_schema');
      expect(
        (format.toApiJson()['json_schema'] as Map)['name'],
        'person',
      );
    });
  });

  group('ChatTool', () {
    test('serializes as an OpenAI-compatible function tool', () {
      const tool = ChatTool(
        name: 'test_tool',
        description: 'A test tool',
        parameters: {
          'type': 'object',
          'properties': {'value': {'type': 'string'}},
        },
      );

      expect(tool.toApiJson(), {
        'type': 'function',
        'function': {
          'name': 'test_tool',
          'description': 'A test tool',
          'parameters': {
            'type': 'object',
            'properties': {'value': {'type': 'string'}},
          },
        },
      });
    });
  });

  group('ChatToolCall', () {
    test('round-trips JSON', () {
      const call = ChatToolCall(
        id: 'call_1',
        name: 'test_tool',
        arguments: '{"value":"ok"}',
      );

      final decoded = ChatToolCall.fromJson(call.toJson());
      expect(decoded.id, call.id);
      expect(decoded.name, call.name);
      expect(decoded.arguments, call.arguments);
    });
  });

  group('ChatMessage', () {
    test('preserves reasoning, tool calls, and API metadata', () {
      final message = ChatMessage(
        id: 'm1',
        content: 'done',
        role: MessageRole.assistant,
        createdAt: DateTime.utc(2026, 1, 1),
        reasoningContent: 'thinking',
        toolCalls: const [
          ChatToolCall(
            id: 'call_1',
            name: 'test_tool',
            arguments: '{}',
          ),
        ],
        apiMetadata: const ChatApiMetadata(
          responseId: 'resp_1',
          model: 'moonshotai/kimi-k3',
          finishReason: 'stop',
          promptTokens: 10,
          completionTokens: 20,
          totalTokens: 30,
        ),
      );

      final decoded = ChatMessage.fromJson(message.toJson());
      expect(decoded.content, 'done');
      expect(decoded.reasoningContent, 'thinking');
      expect(decoded.toolCalls.single.name, 'test_tool');
      expect(decoded.apiMetadata?.totalTokens, 30);
    });
  });
}
