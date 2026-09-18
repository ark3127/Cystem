import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../models/chat_attachment.dart';

class AttachmentService {
  AttachmentService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  // ---------------------------------------------------------------------------
  // Image picking
  // ---------------------------------------------------------------------------

  Future<ChatAttachment?> pickImage({
    ImageSource source = ImageSource.gallery,
    int imageQuality = 85,
    ChatAttachmentType type = ChatAttachmentType.image,
  }) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      imageQuality: imageQuality,
    );

    if (file == null) {
      return null;
    }

    return fromXFileAuto(
      file,
      type: type,
    );
  }

  Future<List<ChatAttachment>> pickImages({
    int imageQuality = 85,
  }) async {
    final List<XFile> files = await _picker.pickMultiImage(
      imageQuality: imageQuality,
    );

    final List<ChatAttachment> attachments = [];

    for (final XFile file in files) {
      attachments.add(
        await fromXFileAuto(
          file,
          type: ChatAttachmentType.image,
        ),
      );
    }

    return attachments;
  }

  Future<ChatAttachment?> pickImageAttachment({
    ImageSource source = ImageSource.gallery,
    int imageQuality = 85,
  }) {
    return pickImage(
      source: source,
      imageQuality: imageQuality,
      type: ChatAttachmentType.image,
    );
  }

  // ---------------------------------------------------------------------------
  // Video picking
  // ---------------------------------------------------------------------------

  Future<XFile?> pickVideo({
    ImageSource source = ImageSource.gallery,
    Duration? maxDuration,
  }) async {
    return _picker.pickVideo(
      source: source,
      maxDuration: maxDuration,
    );
  }

  Future<ChatAttachment?> pickVideoAttachment({
    ImageSource source = ImageSource.gallery,
    Duration? maxDuration,
  }) async {
    final XFile? file = await pickVideo(
      source: source,
      maxDuration: maxDuration,
    );

    if (file == null) {
      return null;
    }

    return fromXFileAuto(
      file,
      type: ChatAttachmentType.video,
    );
  }

  // ---------------------------------------------------------------------------
  // Convert XFile / File into ChatAttachment
  // ---------------------------------------------------------------------------

  Future<ChatAttachment> fromXFileAuto(
    XFile file, {
    ChatAttachmentType? type,
    String? mimeType,
  }) async {
    final File localFile = File(file.path);

    return fromFile(
      localFile,
      type: type ?? typeForPath(file.path),
      mimeType: mimeType ?? mimeTypeForPath(file.path),
    );
  }

  Future<ChatAttachment> fromXFile(
    XFile file, {
    required ChatAttachmentType type,
    String? mimeType,
  }) async {
    return fromXFileAuto(
      file,
      type: type,
      mimeType: mimeType,
    );
  }

  Future<ChatAttachment> fromFile(
    File file, {
    required ChatAttachmentType type,
    String? mimeType,
  }) async {
    final List<int> bytes = await file.readAsBytes();
    final String fileName = file.path.split(Platform.pathSeparator).last;

    final String resolvedMimeType =
        mimeType ?? mimeTypeForPath(file.path);

    return ChatAttachment(
      id: '${DateTime.now().microsecondsSinceEpoch}_$fileName',
      type: type,
      fileName: fileName,
      filePath: file.path,
      mimeType: resolvedMimeType,
      fileSize: bytes.length,
      base64Data: base64Encode(bytes),
    );
  }

  Future<ChatAttachment> fromBytes({
    required List<int> bytes,
    required String fileName,
    required ChatAttachmentType type,
    String? mimeType,
    String? filePath,
  }) async {
    return ChatAttachment(
      id: '${DateTime.now().microsecondsSinceEpoch}_$fileName',
      type: type,
      fileName: fileName,
      filePath: filePath,
      mimeType: mimeType ?? mimeTypeForPath(fileName),
      fileSize: bytes.length,
      base64Data: base64Encode(bytes),
    );
  }

  // ---------------------------------------------------------------------------
  // Type detection
  // ---------------------------------------------------------------------------

  ChatAttachmentType typeForPath(String path) {
    final String extension = _extension(path);

    if (_imageExtensions.contains(extension)) {
      return ChatAttachmentType.image;
    }

    if (_videoExtensions.contains(extension)) {
      return ChatAttachmentType.video;
    }

    if (_audioExtensions.contains(extension)) {
      return ChatAttachmentType.audio;
    }

    if (_documentExtensions.contains(extension)) {
      return ChatAttachmentType.document;
    }

    if (_textExtensions.contains(extension)) {
      return ChatAttachmentType.text;
    }

    return ChatAttachmentType.unknown;
  }

  ChatAttachmentType typeForMimeType(String mimeType) {
    final String mime = mimeType.toLowerCase().trim();

    if (mime.startsWith('image/')) {
      return ChatAttachmentType.image;
    }

    if (mime.startsWith('video/')) {
      return ChatAttachmentType.video;
    }

    if (mime.startsWith('audio/')) {
      return ChatAttachmentType.audio;
    }

    if (mime == 'application/pdf' ||
        mime.contains('word') ||
        mime.contains('excel') ||
        mime.contains('spreadsheet') ||
        mime.contains('powerpoint') ||
        mime.contains('presentation') ||
        mime.contains('zip') ||
        mime.contains('rar')) {
      return ChatAttachmentType.document;
    }

    if (mime.startsWith('text/')) {
      return ChatAttachmentType.text;
    }

    return ChatAttachmentType.unknown;
  }

  // ---------------------------------------------------------------------------
  // MIME detection
  // ---------------------------------------------------------------------------

  String mimeTypeForPath(String path) {
    final String extension = _extension(path);

    switch (extension) {
      // Images
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';

      // Videos
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      case '3gp':
        return 'video/3gpp';

      // Audio
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';

      // Documents
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/vnd.rar';

      // Text
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';
      case 'md':
        return 'text/markdown';

      default:
        return 'application/octet-stream';
    }
  }

  String _extension(String path) {
    final String cleanPath = path.split('?').first;
    final int dotIndex = cleanPath.lastIndexOf('.');

    if (dotIndex == -1 || dotIndex == cleanPath.length - 1) {
      return '';
    }

    return cleanPath.substring(dotIndex + 1).toLowerCase();
  }

  // ---------------------------------------------------------------------------
  // Supported extensions
  // ---------------------------------------------------------------------------

  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
  };

  static const Set<String> _videoExtensions = {
    'mp4',
    'mov',
    'mkv',
    'avi',
    'webm',
    '3gp',
  };

  static const Set<String> _audioExtensions = {
    'mp3',
    'wav',
    'm4a',
    'aac',
    'ogg',
    'flac',
  };

  static const Set<String> _documentExtensions = {
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'zip',
    'rar',
  };

  static const Set<String> _textExtensions = {
    'txt',
    'csv',
    'json',
    'xml',
    'md',
  };
}
