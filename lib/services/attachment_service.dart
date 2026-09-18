import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../models/chat_attachment.dart';

/// Handles local media selection and conversion into ChatAttachment objects.
///
/// The current API content format supports image attachments. Video selection
/// is exposed separately so the Nano Omni pipeline can be added without
/// changing the UI-facing picker contract.
class AttachmentService {
  AttachmentService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<ChatAttachment?> pickImage({
    ImageSource source = ImageSource.gallery,
    int? imageQuality,
    double? maxWidth,
    double? maxHeight,
  }) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );

    if (file == null) return null;
    return fromXFile(file, type: ChatAttachmentType.image);
  }

  Future<List<ChatAttachment>> pickImages({
    int? imageQuality,
    double? maxWidth,
    double? maxHeight,
  }) async {
    final files = await _picker.pickMultiImage(
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );

    return Future.wait(
      files.map((file) => fromXFile(file, type: ChatAttachmentType.image)),
    );
  }

  Future<XFile?> pickVideo({ImageSource source = ImageSource.gallery}) {
    return _picker.pickVideo(source: source);
  }

  Future<ChatAttachment> fromXFile(
    XFile file, {
    required ChatAttachmentType type,
    String? mimeType,
  }) async {
    final bytes = await file.readAsBytes();
    final resolvedMimeType = mimeType ?? _mimeTypeFor(file.path);

    return ChatAttachment(
      id: '${DateTime.now().microsecondsSinceEpoch}_${file.name}',
      type: type,
      mimeType: resolvedMimeType,
      data: base64Encode(bytes),
      fileName: file.name,
    );
  }

  Future<ChatAttachment> fromFile(
    File file, {
    required ChatAttachmentType type,
    String? fileName,
    String? mimeType,
  }) async {
    final bytes = await file.readAsBytes();
    final name = fileName ?? file.path.split(Platform.pathSeparator).last;

    return ChatAttachment(
      id: '${DateTime.now().microsecondsSinceEpoch}_$name',
      type: type,
      mimeType: mimeType ?? _mimeTypeFor(name),
      data: base64Encode(bytes),
      fileName: name,
    );
  }

  String _mimeTypeFor(String path) {
    final extension = path.split('.').last.toLowerCase();

    const types = <String, String>{
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'gif': 'image/gif',
      'heic': 'image/heic',
      'heif': 'image/heif',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'm4v': 'video/x-m4v',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'm4a': 'audio/mp4',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'json': 'application/json',
    };

    return types[extension] ?? 'application/octet-stream';
  }
}
