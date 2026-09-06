import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../models/chat_attachment.dart';

class ImageAttachmentService {
  ImageAttachmentService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<ChatAttachment?> pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 4096,
      maxHeight: 4096,
    );

    if (file == null) return null;

    final bytes = await file.readAsBytes();
    final mimeType = _mimeType(file.mimeType, file.name);

    return ChatAttachment(
      id: '${DateTime.now().microsecondsSinceEpoch}_${file.name}',
      type: ChatAttachmentType.image,
      mimeType: mimeType,
      data: base64Encode(bytes),
      fileName: file.name,
    );
  }

  String _mimeType(String? reported, String name) {
    if (reported != null && reported.startsWith('image/')) {
      return reported;
    }

    final lower = name.toLowerCase();

    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';

    return 'image/jpeg';
  }
}

Uint8List decodeAttachmentImage(ChatAttachment attachment) {
  return base64Decode(attachment.data);
}
