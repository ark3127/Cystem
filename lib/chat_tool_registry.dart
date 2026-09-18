import '../models/chat_tool.dart';

/// Registry for tools exposed to Kimi K3.
class ChatToolRegistry {
  final List<ChatTool> _tools = [];

  List<ChatTool> get tools => List.unmodifiable(_tools);

  void register(ChatTool tool) {
    _tools.removeWhere((item) => item.name == tool.name);
    _tools.add(tool);
  }

  void unregister(String name) {
    _tools.removeWhere((item) => item.name == name);
  }

  ChatTool? find(String name) {
    for (final tool in _tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  List<Map<String, dynamic>> toApiJson() {
    return _tools.map((tool) => tool.toApiJson()).toList();
  }
}
