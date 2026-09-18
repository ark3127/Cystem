import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_attachment.dart';

class AttachmentService {
  AttachmentService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<ChatAttachment?> pickImage({
    ImageSource source = ImageSource.gallery,
    int imageQuality = 85,
    ChatAttachmentType type = ChatAttachmentType.image,
  }) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: imageQuality,
    );
    if (file == null) return null;
    return fromXFileAuto(file, type: type);
  }

  Future<List<ChatAttachment>> pickImages({int imageQuality = 85}) async {
    final files = await _picker.pickMultiImage(imageQuality: imageQuality);
    return Future.wait(
      files.map(
        (file) => fromXFileAuto(
          file,
          type: ChatAttachmentType.image,
        ),
      ),
    );
  }

  Future<ChatAttachment?> pickImageAttachment({
    ImageSource source = ImageSource.gallery,
    int imageQuality = 85,
  }) {
    return pickImage(source: source, imageQuality: imageQuality);
  }

  Future<XFile?> pickVideo({
    ImageSource source = ImageSource.gallery,
    Duration? maxDuration,
  }) {
    return _picker.pickVideo(source: source, maxDuration: maxDuration);
  }

  Future<ChatAttachment?> pickVideoAttachment({
    ImageSource source = ImageSource.gallery,
    Duration? maxDuration,
  }) async {
    final file = await pickVideo(
      source: source,
      maxDuration: maxDuration,
    );
    if (file == null) return null;
    return fromXFileAuto(file, type: ChatAttachmentType.video);
  }

  Future<ChatAttachment?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'doc',
        'docx',
        'txt',
        'csv',
        'json',
        'xml',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'zip',
        'rar',
      ],
    );
    return _fromPlatformFile(result, ChatAttachmentType.document);
  }

  Future<ChatAttachment?> pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'],
    );
    return _fromPlatformFile(result, ChatAttachmentType.audio);
  }

  Future<ChatAttachment?> pickAnyFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    return _fromPlatformFile(
      result,
      typeForPath(result?.files.single.name ?? ''),
    );
  }

  Future<ChatAttachment?> _fromPlatformFile(
    FilePickerResult? result,
    ChatAttachmentType type,
  ) async {
    if (result == null || result.files.isEmpty) return null;

    final platformFile = result.files.single;
    final mimeType = mimeTypeForPath(platformFile.name);

    final path = platformFile.path;
    if (path != null) {
      return fromFile(
        File(path),
        type: type,
        mimeType: mimeType,
      );
    }

    final bytes = platformFile.bytes;
    if (bytes != null) {
      return fromBytes(
        bytes: bytes,
        fileName: platformFile.name,
        type: type,
        mimeType: mimeType,
      );
    }

    return null;
  }

  Future<ChatAttachment> fromXFileAuto(
    XFile file, {
    ChatAttachmentType? type,
    String? mimeType,
  }) {
    return fromFile(
      File(file.path),
      type: type ?? typeForPath(file.path),
      mimeType: mimeType ?? mimeTypeForPath(file.path),
    );
  }

  Future<ChatAttachment> fromXFile(
    XFile file, {
    required ChatAttachmentType type,
    String? mimeType,
  }) {
    return fromXFileAuto(file, type: type, mimeType: mimeType);
  }

  Future<ChatAttachment> fromFile(
    File file, {
    required ChatAttachmentType type,
    String? mimeType,
  }) async {
    final bytes = await file.readAsBytes();
    final fileName = file.path.split(Platform.pathSeparator).last;

    return ChatAttachment(
      id: '${DateTime.now().microsecondsSinceEpoch}_$fileName',
      type: type,
      fileName: fileName,
      mimeType: mimeType ?? mimeTypeForPath(file.path),
      fileSize: bytes.length,
      data: base64Encode(bytes),
    );
  }

  Future<ChatAttachment> fromBytes({
    required List<int> bytes,
    required String fileName,
    required ChatAttachmentType type,
    String? mimeType,
  }) async {
    return ChatAttachment(
      id: '${DateTime.now().microsecondsSinceEpoch}_$fileName',
      type: type,
      fileName: fileName,
      mimeType: mimeType ?? mimeTypeForPath(fileName),
      fileSize: bytes.length,
      data: base64Encode(bytes),
    );
  }

  ChatAttachmentType typeForPath(String path) {
    final extension = _extension(path);
    if (_imageExtensions.contains(extension)) return ChatAttachmentType.image;
    if (_videoExtensions.contains(extension)) return ChatAttachmentType.video;
    if (_audioExtensions.contains(extension)) return ChatAttachmentType.audio;
    if (_documentExtensions.contains(extension)) return ChatAttachmentType.document;
    if (_textExtensions.contains(extension)) return ChatAttachmentType.text;
    return ChatAttachmentType.unknown;
  }

  ChatAttachmentType typeForMimeType(String mimeType) {
    final mime = mimeType.toLowerCase().trim();
    if (mime.startsWith('image/')) return ChatAttachmentType.image;
    if (mime.startsWith('video/')) return ChatAttachmentType.video;
    if (mime.startsWith('audio/')) return ChatAttachmentType.audio;
    if (mime.startsWith('text/')) return ChatAttachmentType.text;
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
    return ChatAttachmentType.unknown;
  }

  String mimeTypeForPath(String path) {
    switch (_extension(path)) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
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
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/vnd.rar';
      default:
        return 'application/octet-stream';
    }
  }

  String _extension(String path) {
    final cleanPath = path.split('?').first;
    final dotIndex = cleanPath.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == cleanPath.length - 1) return '';
    return cleanPath.substring(dotIndex + 1).toLowerCase();
  }

  static const _imageExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic',
  };

  static const _videoExtensions = {
    'mp4', 'mov', 'mkv',
  };

  static const _audioExtensions = {
    'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac',
  };

  static const _documentExtensions = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'zip', 'rar',
  };

  static const _textExtensions = {
    'txt', 'csv', 'json', 'xml', 'md',
  };
}
