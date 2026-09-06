class ChatToolCall {
  final String id;
  final String name;
  final String arguments;

  const ChatToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'arguments': arguments,
    };
  }

  factory ChatToolCall.fromJson(Map<String, dynamic> json) {
    return ChatToolCall(
      id: json['id'] as String,
      name: json['name'] as String,
      arguments: json['arguments'] as String,
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'id': id,
      'type': 'function',
      'function': {
        'name': name,
        'arguments': arguments,
      },
    };
  }
}
