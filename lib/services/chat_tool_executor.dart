import '../models/chat_tool_call.dart';

/// Executes a model-requested tool.
abstract interface class ChatToolExecutor {
  Future<String> execute(ChatToolCall call);
}

/// Fallback executor used when no device tool provider is installed.
class UnavailableToolExecutor implements ChatToolExecutor {
  const UnavailableToolExecutor();

  @override
  Future<String> execute(ChatToolCall call) async {
    return 'Tool execution is not available: ${call.name}';
  }
}
