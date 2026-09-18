/// OpenAI-compatible function tool definition used by Kimi K3.
class ChatTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const ChatTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toApiJson() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parameters,
      },
    };
  }
}
