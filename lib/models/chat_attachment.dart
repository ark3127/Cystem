enum ChatAttachmentType {
  image,
}

class ChatAttachment {
  final String id;
  final ChatAttachmentType type;
  final String mimeType;
  final String data;
  final String? fileName;
  /// Containing/source page for web images. Generated and local images leave this null.
  final String? sourceUrl;

  const ChatAttachment({
    required this.id,
    required this.type,
    required this.mimeType,
    required this.data,
    this.fileName,
    this.sourceUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'mimeType': mimeType,
      'data': data,
      if (fileName != null) 'fileName': fileName,
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
    };
  }

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as String,
      type: ChatAttachmentType.values.byName(json['type'] as String),
      mimeType: json['mimeType'] as String,
      data: json['data'] as String,
      fileName: json['fileName'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
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
