import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/models/chat_completion_result.dart';
import 'package:cystem/models/chat_message.dart';
import 'package:cystem/services/nvidia_api_service.dart';
import 'package:cystem/services/structured_output_service.dart';

void main() {
  final service = StructuredOutputService(null as dynamic);

  ChatCompletionResult result(String content, {String? finishReason}) {
    return ChatCompletionResult(
      message: ChatMessage(
        id: 'm',
        content: content,
        role: MessageRole.assistant,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      responseId: 'r',
      model: 'moonshotai/kimi-k3',
      finishReason: finishReason ?? 'stop',
      promptTokens: 1,
      completionTokens: 1,
      totalTokens: 2,
    );
  }

  const schema = {
    'type': 'object',
    'properties': {
      'name': {'type': 'string'},
      'age': {'type': 'integer'},
      'role': {
        'type': 'string',
        'enum': ['user', 'admin'],
      },
    },
    'required': ['name', 'age'],
    'additionalProperties': false,
  };

  test('accepts valid structured JSON', () {
    final value = service.parseObject(
      result('{"name":"Aman","age":20,"role":"user"}'),
      schema: schema,
    );
    expect(value['name'], 'Aman');
    expect(value['age'], 20);
  });

  test('rejects missing required property', () {
    expect(
      () => service.parseObject(result('{"name":"Aman"}'), schema: schema),
      throwsA(isA<NvidiaApiException>()),
    );
  });

  test('rejects wrong type', () {
    expect(
      () => service.parseObject(
        result('{"name":"Aman","age":"20"}'),
        schema: schema,
      ),
      throwsA(isA<NvidiaApiException>()),
    );
  });

  test('rejects additional properties', () {
    expect(
      () => service.parseObject(
        result('{"name":"Aman","age":20,"extra":true}'),
        schema: schema,
      ),
      throwsA(isA<NvidiaApiException>()),
    );
  });

  test('rejects truncated completion', () {
    expect(
      () => service.parseObject(
        result('{"name":"Aman"', finishReason: 'length'),
        schema: schema,
      ),
      throwsA(isA<NvidiaApiException>()),
    );
  });
}
