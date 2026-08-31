enum MessageRole {
  user,
  assistant,
}

class ChatMessage {
  final String id;
  final String content;
  final MessageRole role;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.content,
    required this.role,
    required this.createdAt,
  });

  bool get isUser => role == MessageRole.user;

  bool get isAssistant => role == MessageRole.assistant;

  ChatMessage copyWith({
    String? content,
  }) {
    return ChatMessage(
      id: id,
      content: content ?? this.content,
      role: role,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'role': role.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ChatMessage.fromJson(
    Map<String, dynamic> json,
  ) {
    return ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      role: MessageRole.values.byName(
        json['role'] as String,
      ),
      createdAt: DateTime.parse(
        json['createdAt'] as String,
      ),
    );
  }
}
