import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/services/retry_service.dart';

void main() {
  test('retries transient failures and eventually succeeds', () async {
    var attempts = 0;
    final result = await const RetryService().run(
      () async {
        attempts++;
        if (attempts < 3) throw StateError('temporary');
        return 'ok';
      },
      initialDelay: Duration.zero,
    );

    expect(result, 'ok');
    expect(attempts, 3);
  });

  test('does not retry when predicate rejects the error', () async {
    var attempts = 0;

    await expectLater(
      const RetryService().run<void>(
        () async {
          attempts++;
          throw StateError('permanent');
        },
        shouldRetry: (_) => false,
        initialDelay: Duration.zero,
      ),
      throwsA(isA<StateError>()),
    );

    expect(attempts, 1);
  });
}
