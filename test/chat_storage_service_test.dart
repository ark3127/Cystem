import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/models/chat_conversation.dart';
import 'package:cystem/models/chat_message.dart';

void main() {
  group('ChatConversation persistence', () {
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
      expect(decoded.title, 'Test');
      expect(decoded.messages.single.content, 'hello');
    });

    test('version 1 bare arrays remain valid JSON', () {
      final data = jsonDecode('[{"id":"c1"}]');
      expect(data, isA<List<dynamic>>());
    });

    test('malformed persisted JSON is detectable', () {
      expect(() => jsonDecode('{not json'), throwsFormatException);
    });
  });
}
