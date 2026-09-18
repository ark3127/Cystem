import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/models/chat_tool_call.dart';

void main() {
  test('serializes a tool call in OpenAI-compatible form', () {
    const call = ChatToolCall(
      id: 'call_1',
      name: 'make_phone_call',
      arguments: '{"phone_number":"123"}',
    );

    expect(call.toApiJson(), {
      'id': 'call_1',
      'type': 'function',
      'function': {
        'name': 'make_phone_call',
        'arguments': '{"phone_number":"123"}',
      },
    });
  });
}
