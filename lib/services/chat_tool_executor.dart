import '../models/chat_tool_call.dart';

/// Executes a model-requested tool.
///
/// Implementations are introduced in Chunk 7. Keeping execution behind an
/// interface lets the chat layer remain independent of Android APIs.
abstract interface class ChatToolExecutor {
  Future<String> execute(ChatToolCall call);
}

class UnavailableToolExecutor implements ChatToolExecutor {
  const UnavailableToolExecutor();

  @override
  Future<String> execute(ChatToolCall call) async {
    return 'Tool execution is not available yet: ${call.name}';
  }
}
