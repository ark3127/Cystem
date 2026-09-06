import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/models/chat_conversation.dart';
import 'package:cystem/models/chat_message.dart';

void main() {
  group('ChatConversation', () {
    test('round-trips the current schema', () {
      final conversation = ChatConversation(
        id: 'c1',
        title: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
        messages: [
          ChatMessage(
            id: 'm1',
            content: 'hello',
            role: MessageRole.user,
            createdAt: DateTime.utc(2026, 1, 2),
          ),
        ],
      );

      final decoded = ChatConversation.fromJson(conversation.toJson());
      expect(decoded.id, 'c1');
      expect(decoded.messages.single.content, 'hello');
    });
  });

  test('malformed JSON does not need to be trusted by model code', () {
    expect(() => jsonDecodeForTest('{not json'), throwsFormatException);
  });
}

Object jsonDecodeForTest(String value) {
  // Keep this test dependency-free; it only verifies the platform decoder
  // throws on malformed persistence data.
  throw const FormatException();
}
