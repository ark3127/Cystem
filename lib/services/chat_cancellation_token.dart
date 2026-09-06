/// Cooperative cancellation state shared by the UI, API stream and tool loop.
class ChatCancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() => _isCancelled = true;

  void throwIfCancelled() {
    if (_isCancelled) throw const ChatGenerationCancelledException();
  }
}

class ChatGenerationCancelledException implements Exception {
  const ChatGenerationCancelledException();

  @override
  String toString() => 'Generation cancelled.';
}
