import '../models/chat_tool.dart';
import 'chat_tool_registry.dart';
import 'phone_tool_service.dart';

/// Builds the tool registry exposed to Kimi K3 for device actions.
class PhoneToolRegistry {
  PhoneToolRegistry._();

  static ChatToolRegistry create() {
    final registry = ChatToolRegistry();
    for (final tool in PhoneToolService.definitions) {
      registry.register(tool);
    }
    return registry;
  }

  static List<ChatTool> get definitions => PhoneToolService.definitions;
}
