enum ChatAttachmentType {
  image,
}

class ChatAttachment {
  final String id;
  final ChatAttachmentType type;
  final String mimeType;
  final String data;
  final String? fileName;

  const ChatAttachment({
    required this.id,
    required this.type,
    required this.mimeType,
    required this.data,
    this.fileName,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'mimeType': mimeType,
      'data': data,
      if (fileName != null) 'fileName': fileName,
    };
  }

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as String,
      type: ChatAttachmentType.values.byName(json['type'] as String),
      mimeType: json['mimeType'] as String,
      data: json['data'] as String,
      fileName: json['fileName'] as String?,
    );
  }

  Map<String, dynamic> toApiContentPart() {
    return {
      'type': 'image_url',
      'image_url': {
        'url': data.startsWith('data:')
            ? data
            : 'data:$mimeType;base64,$data',
      },
    };
  }
}
