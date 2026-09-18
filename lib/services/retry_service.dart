import 'dart:math';

/// Small, dependency-free retry helper for transient operations.
class RetryService {
  const RetryService();

  Future<T> run<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 300),
    bool Function(Object error)? shouldRetry,
  }) async {
    if (maxAttempts < 1) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'Must be at least 1.');
    }

    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (error, stackTrace) {
        lastError = error;
        lastStack = stackTrace;

        final retry = shouldRetry?.call(error) ?? true;
        if (!retry || attempt == maxAttempts) rethrow;

        final multiplier = pow(2, attempt - 1).toInt();
        await Future<void>.delayed(initialDelay * multiplier);
      }
    }

    Error.throwWithStackTrace(lastError!, lastStack!);
  }
}
