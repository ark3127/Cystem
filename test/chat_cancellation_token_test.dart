import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/services/chat_cancellation_token.dart';

void main() {
  test('cancels and notifies listeners once', () {
    final token = ChatCancellationToken();
    var calls = 0;
    token.addCancellationListener(() => calls++);

    token.cancel();
    token.cancel();

    expect(token.isCancelled, isTrue);
    expect(calls, 1);
  });

  test('throws after cancellation', () {
    final token = ChatCancellationToken()..cancel();
    expect(token.throwIfCancelled, throwsA(isA<ChatGenerationCancelledException>()));
  });
}
