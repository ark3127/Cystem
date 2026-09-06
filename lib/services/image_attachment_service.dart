import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../models/chat_attachment.dart';

class ImageAttachmentService {
  ImageAttachmentService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<ChatAttachment?> pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 2048,
      maxHeight: 2048,
    );

    if (file == null) return null;

    final bytes = await file.readAsBytes();
    final mimeType = _mimeType(file.mimeType, file.name);

    if (!_supportedMimeTypes.contains(mimeType)) {
      throw UnsupportedError('This image format is not supported. Please choose a JPEG, PNG, WEBP, or GIF image.');
    }

    // Gemini inline image requests have a 20 MB total request limit. Keep a
    // little headroom for the visual prompt and JSON envelope.
    if (bytes.length > 18 * 1024 * 1024) {
      throw UnsupportedError('That image is too large. Please choose a smaller image.');
    }

    return ChatAttachment(
      id: '${DateTime.now().microsecondsSinceEpoch}_${file.name}',
      type: ChatAttachmentType.image,
      mimeType: mimeType,
      data: base64Encode(bytes),
      fileName: file.name,
    );
  }

  String _mimeType(String? reported, String name) {
    if (reported != null && reported.startsWith('image/')) return reported.toLowerCase();
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static const Set<String> _supportedMimeTypes = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'};
}

Uint8List decodeAttachmentImage(ChatAttachment attachment) => base64Decode(attachment.data);
