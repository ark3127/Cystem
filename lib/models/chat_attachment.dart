enum ChatAttachmentType {
  image,
  video,
  audio,
  document,
  text,
  unknown,
}

class ChatAttachment {
  final String id;
  final ChatAttachmentType type;
  final String? mimeType;
  final String? data;
  final String? fileName;
  final String? sourceUrl;
  final int? fileSize;

  const ChatAttachment({
    required this.id,
    required this.type,
    this.mimeType,
    this.data,
    this.fileName,
    this.sourceUrl,
    this.fileSize,
  });

  bool get isImage => type == ChatAttachmentType.image;

  bool get isVideo => type == ChatAttachmentType.video;

  bool get isAudio => type == ChatAttachmentType.audio;

  bool get isDocument => type == ChatAttachmentType.document;

  bool get isText => type == ChatAttachmentType.text;

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as String? ?? '',
      type: _typeFromString(json['type'] as String?),
      mimeType: json['mimeType'] as String?,
      data: json['data'] as String?,
      fileName: json['fileName'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      fileSize: json['fileSize'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'mimeType': mimeType,
      'data': data,
      'fileName': fileName,
      'sourceUrl': sourceUrl,
      'fileSize': fileSize,
    };
  }

  static ChatAttachmentType _typeFromString(String? value) {
    switch (value) {
      case 'image':
        return ChatAttachmentType.image;
      case 'video':
        return ChatAttachmentType.video;
      case 'audio':
        return ChatAttachmentType.audio;
      case 'document':
        return ChatAttachmentType.document;
      case 'text':
        return ChatAttachmentType.text;
      default:
        return ChatAttachmentType.unknown;
    }
  }

  ChatAttachment copyWith({
    String? id,
    ChatAttachmentType? type,
    String? mimeType,
    String? data,
    String? fileName,
    String? sourceUrl,
    int? fileSize,
  }) {
    return ChatAttachment(
      id: id ?? this.id,
      type: type ?? this.type,
      mimeType: mimeType ?? this.mimeType,
      data: data ?? this.data,
      fileName: fileName ?? this.fileName,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      fileSize: fileSize ?? this.fileSize,
    );
  }
}
