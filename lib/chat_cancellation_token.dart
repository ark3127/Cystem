/// Cooperative cancellation state shared by the UI, API stream and tool loop.
class ChatCancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void addCancellationListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeCancellationListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_isCancelled) throw const ChatGenerationCancelledException();
  }
}

class ChatGenerationCancelledException implements Exception {
  const ChatGenerationCancelledException();

  @override
  String toString() => 'Generation cancelled.';
}
