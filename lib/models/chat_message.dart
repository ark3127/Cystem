import 'chat_attachment.dart';
import 'chat_tool_call.dart';

enum MessageRole {
  user,
  assistant,
  tool,
}

class ChatApiMetadata {
  final String? responseId;
  final String? model;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  const ChatApiMetadata({
    this.responseId,
    this.model,
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  Map<String, dynamic> toJson() {
    return {
      if (responseId != null) 'responseId': responseId,
      if (model != null) 'model': model,
      if (finishReason != null) 'finishReason': finishReason,
      if (promptTokens != null) 'promptTokens': promptTokens,
      if (completionTokens != null) 'completionTokens': completionTokens,
      if (totalTokens != null) 'totalTokens': totalTokens,
    };
  }

  factory ChatApiMetadata.fromJson(Map<String, dynamic> json) {
    return ChatApiMetadata(
      responseId: json['responseId'] as String?,
      model: json['model'] as String?,
      finishReason: json['finishReason'] as String?,
      promptTokens: json['promptTokens'] as int?,
      completionTokens: json['completionTokens'] as int?,
      totalTokens: json['totalTokens'] as int?,
    );
  }
}

class ChatMessage {
  final String id;
  final String content;
  final MessageRole role;
  final DateTime createdAt;
  final String? reasoningContent;
  final List<ChatToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;
  final List<ChatAttachment> attachments;
  final String? backendContext;
  final ChatApiMetadata? apiMetadata;

  const ChatMessage({
    required this.id,
    required this.content,
    required this.role,
    required this.createdAt,
    this.reasoningContent,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    this.attachments = const [],
    this.backendContext,
    this.apiMetadata,
  });

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isTool => role == MessageRole.tool;

  ChatMessage copyWith({
    String? content,
    String? reasoningContent,
    List<ChatToolCall>? toolCalls,
    String? toolCallId,
    String? toolName,
    List<ChatAttachment>? attachments,
    String? backendContext,
    ChatApiMetadata? apiMetadata,
  }) {
    return ChatMessage(
      id: id,
      content: content ?? this.content,
      role: role,
      createdAt: createdAt,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      attachments: attachments ?? this.attachments,
      backendContext: backendContext ?? this.backendContext,
      apiMetadata: apiMetadata ?? this.apiMetadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'role': role.name,
      'createdAt': createdAt.toIso8601String(),
      if (reasoningContent != null) 'reasoningContent': reasoningContent,
      if (toolCalls.isNotEmpty)
        'toolCalls': toolCalls.map((call) => call.toJson()).toList(),
      if (toolCallId != null) 'toolCallId': toolCallId,
      if (toolName != null) 'toolName': toolName,
      if (attachments.isNotEmpty)
        'attachments': attachments.map((item) => item.toJson()).toList(),
      if (backendContext != null) 'backendContext': backendContext,
      if (apiMetadata != null) 'apiMetadata': apiMetadata!.toJson(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawToolCalls = json['toolCalls'] as List<dynamic>? ?? const [];
    final rawAttachments = json['attachments'] as List<dynamic>? ?? const [];
    final rawMetadata = json['apiMetadata'];

    return ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      role: MessageRole.values.byName(json['role'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      reasoningContent: json['reasoningContent'] as String?,
      toolCalls: rawToolCalls
          .map((call) => ChatToolCall.fromJson(
                Map<String, dynamic>.from(call as Map),
              ))
          .toList(),
      toolCallId: json['toolCallId'] as String?,
      toolName: json['toolName'] as String?,
      attachments: rawAttachments
          .map((item) => ChatAttachment.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
      backendContext: json['backendContext'] as String?,
      apiMetadata: rawMetadata is Map
          ? ChatApiMetadata.fromJson(
              Map<String, dynamic>.from(rawMetadata),
            )
          : null,
    );
  }

  Map<String, dynamic> toApiJson() {
    if (isTool) {
      return {
        'role': 'tool',
        'tool_call_id': toolCallId,
        if (toolName != null) 'name': toolName,
        'content': content,
      };
    }

    if (attachments.isEmpty) {
      return {
        'role': role.name,
        'content': content,
        if (reasoningContent != null && isAssistant)
          'reasoning_content': reasoningContent,
        if (toolCalls.isNotEmpty && isAssistant)
          'tool_calls': toolCalls.map((call) => call.toApiJson()).toList(),
      };
    }

    return {
      'role': role.name,
      'content': [
        if (content.isNotEmpty)
          {
            'type': 'text',
            'text': content,
          },
        ...attachments.map((attachment) => attachment.toApiContentPart()),
      ],
      if (reasoningContent != null && isAssistant)
        'reasoning_content': reasoningContent,
      if (toolCalls.isNotEmpty && isAssistant)
        'tool_calls': toolCalls.map((call) => call.toApiJson()).toList(),
    };
  }
}
