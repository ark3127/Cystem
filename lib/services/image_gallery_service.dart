import 'dart:io';
import 'dart:typed_data';

import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_attachment.dart';
import 'image_attachment_service.dart';

class ImageGalleryService {
  Future<bool> saveToGallery(ChatAttachment attachment) async {
    final bytes = decodeAttachmentImage(attachment);
    final directory = await getTemporaryDirectory();
    final extension = _extension(attachment.mimeType, attachment.fileName);
    final file = File('${directory.path}/cystem_${DateTime.now().microsecondsSinceEpoch}.$extension');
    await file.writeAsBytes(bytes, flush: true);
    final saved = await GallerySaver.saveImage(file.path);
    return saved == true;
  }

  Future<File> copyToTemporaryFile(ChatAttachment attachment) async {
    final Uint8List bytes = decodeAttachmentImage(attachment);
    final directory = await getTemporaryDirectory();
    final extension = _extension(attachment.mimeType, attachment.fileName);
    final file = File('${directory.path}/cystem_${DateTime.now().microsecondsSinceEpoch}.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _extension(String mimeType, String? fileName) {
    final name = fileName?.split('.').last.toLowerCase();
    if (name != null && name.isNotEmpty && name.length <= 5) return name;
    return switch (mimeType.toLowerCase()) {
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'png',
    };
  }
}
