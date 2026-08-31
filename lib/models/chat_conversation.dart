import 'chat_message.dart';

class ChatConversation {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  bool isPinned;
  List<ChatMessage> messages;

  ChatConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPinned': isPinned,
      'messages': messages
          .map((message) => message.toJson())
          .toList(),
    };
  }

  factory ChatConversation.fromJson(
    Map<String, dynamic> json,
  ) {
    return ChatConversation(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: DateTime.parse(
        json['createdAt'] as String,
      ),
      updatedAt: DateTime.parse(
        json['updatedAt'] as String,
      ),
      isPinned: json['isPinned'] as bool? ?? false,
      messages: (json['messages'] as List<dynamic>? ?? [])
          .map(
            (message) => ChatMessage.fromJson(
              Map<String, dynamic>.from(message as Map),
            ),
          )
          .toList(),
    );
  }
}
