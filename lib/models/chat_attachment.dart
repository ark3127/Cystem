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
  final String mimeType;
  final String data;
  final String? fileName;
  final String? sourceUrl;
  final int? fileSize;

  const ChatAttachment({
    required this.id,
    required this.type,
    required this.mimeType,
    required this.data,
    this.fileName,
    this.sourceUrl,
    this.fileSize,
  });

  bool get isImage => type == ChatAttachmentType.image;

  bool get isVideo => type == ChatAttachmentType.video;

  bool get isAudio => type == ChatAttachmentType.audio;

  bool get isDocument => type == ChatAttachmentType.document;

  bool get isText => type == ChatAttachmentType.text;

  bool get isUnknown => type == ChatAttachmentType.unknown;

  bool get isBase64Data =>
      !data.startsWith('http://') &&
      !data.startsWith('https://') &&
      !data.startsWith('data:');

  String get displayName {
    if (fileName != null && fileName!.trim().isNotEmpty) {
      return fileName!;
    }

    switch (type) {
      case ChatAttachmentType.image:
        return 'Image';
      case ChatAttachmentType.video:
        return 'Video';
      case ChatAttachmentType.audio:
        return 'Audio';
      case ChatAttachmentType.document:
        return 'Document';
      case ChatAttachmentType.text:
        return 'Text file';
      case ChatAttachmentType.unknown:
        return 'Attachment';
    }
  }

  String get extension {
    if (fileName != null && fileName!.contains('.')) {
      return fileName!.split('.').last.toLowerCase();
    }

    final mimeParts = mimeType.split('/');

    if (mimeParts.length == 2) {
      return mimeParts.last.toLowerCase();
    }

    return '';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'mimeType': mimeType,
      'data': data,
      if (fileName != null) 'fileName': fileName,
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
      if (fileSize != null) 'fileSize': fileSize,
    };
  }

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String? ?? 'unknown';

    final type = ChatAttachmentType.values.firstWhere(
      (item) => item.name == rawType,
      orElse: () => ChatAttachmentType.unknown,
    );

    return ChatAttachment(
      id: json['id'] as String,
      type: type,
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      data: json['data'] as String? ?? '',
      fileName: json['fileName'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      fileSize: (json['fileSize'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toApiContentPart() {
    final normalizedData = data.startsWith('data:')
        ? data
        : 'data:$mimeType;base64,$data';

    if (isImage) {
      return {
        'type': 'image_url',
        'image_url': {
          'url': normalizedData,
        },
      };
    }

    if (isText || mimeType.startsWith('text/')) {
      return {
        'type': 'text',
        'text': data,
      };
    }

    return {
      'type': 'text',
      'text': '''
Attached file:
Name: $displayName
Type: $mimeType
Size: ${fileSize ?? 'unknown'} bytes

This file must be processed by the media/file perception pipeline.
''',
    };
  }

  Map<String, dynamic> toNanoOmniJson() {
    return {
      'id': id,
      'type': type.name,
      'mimeType': mimeType,
      'fileName': fileName,
      'fileSize': fileSize,
      'data': data,
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
    };
  }
}
