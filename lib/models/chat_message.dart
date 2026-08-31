class ChatMessage {
  final String id;
  final String content;
  final MessageRole role;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.content,
    required this.role,
    required this.createdAt,
  });

  bool get isUser => role == MessageRole.user;

  bool get isAssistant => role == MessageRole.assistant;
}

enum MessageRole {
  user,
  assistant,
}
