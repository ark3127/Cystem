import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/models/chat_tool.dart';
import 'package:cystem/models/chat_tool_call.dart';
import 'package:cystem/services/chat_tool_argument_validator.dart';

void main() {
  const validator = ChatToolArgumentValidator();
  const tool = ChatTool(
    name: 'example',
    description: 'Example tool',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string'},
        'count': {'type': 'integer'},
      },
      'required': ['query'],
      'additionalProperties': false,
    },
  );

  test('accepts valid arguments', () {
    expect(
      () => validator.validate(
        tool,
        const ChatToolCall(id: '1', name: 'example', arguments: '{"query":"hello","count":2}'),
      ),
      returnsNormally,
    );
  });

  test('rejects missing required arguments', () {
    expect(
      () => validator.validate(
        tool,
        const ChatToolCall(id: '1', name: 'example', arguments: '{}'),
      ),
      throwsA(isA<ChatToolArgumentValidationException>()),
    );
  });

  test('rejects unknown arguments', () {
    expect(
      () => validator.validate(
        tool,
        const ChatToolCall(id: '1', name: 'example', arguments: '{"query":"hello","evil":true}'),
      ),
      throwsA(isA<ChatToolArgumentValidationException>()),
    );
  });

  test('rejects wrong argument types', () {
    expect(
      () => validator.validate(
        tool,
        const ChatToolCall(id: '1', name: 'example', arguments: '{"query":123}'),
      ),
      throwsA(isA<ChatToolArgumentValidationException>()),
    );
  });
}
