import '../models/chat_tool.dart';
import '../models/chat_tool_call.dart';
import 'chat_tool_executor.dart';
import 'chat_tool_registry.dart';
import 'phone_tool_service.dart';
import 'web_search_service.dart';

/// All tools exposed to Nemotron.
class AppToolRegistry {
  AppToolRegistry._();

  static ChatToolRegistry create() {
    final registry = ChatToolRegistry();
    for (final tool in PhoneToolService.definitions) {
      registry.register(tool);
    }
    for (final tool in WebSearchService.definitions) {
      registry.register(tool);
    }
    return registry;
  }
}

/// Routes tool calls to the matching service.
class AppToolExecutor implements ChatToolExecutor {
  AppToolExecutor({PhoneToolService? phone, WebSearchService? web})
      : _phone = phone ?? PhoneToolService(),
        _web = web ?? WebSearchService();

  final PhoneToolService _phone;
  final WebSearchService _web;

  @override
  Future<String> execute(ChatToolCall call) async {
    if (WebSearchService.definitions.any((tool) => tool.name == call.name)) {
      return _web.execute(call);
    }
    if (PhoneToolService.definitions.any((tool) => tool.name == call.name)) {
      return _phone.execute(call);
    }
    return 'Unknown tool: ${call.name}';
  }
}

// Keep the old name available for any external references.
class AppToolService extends AppToolExecutor {}
