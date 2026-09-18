import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_attachment.dart';
import '../services/attachment_service.dart';

/// Reusable attachment picker for the chat composer.
///
/// Returns a selected attachment, or null when the sheet is dismissed.
class AttachmentPickerSheet extends StatelessWidget {
  const AttachmentPickerSheet({super.key, this.service});

  final AttachmentService? service;

  static Future<ChatAttachment?> show(
    BuildContext context, {
    AttachmentService? service,
  }) {
    return showModalBottomSheet<ChatAttachment?>(
      context: context,
      showDragHandle: true,
      builder: (_) => AttachmentPickerSheet(service: service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attachments = service ?? AttachmentService();

    Future<void> pick(Future<ChatAttachment?> Function() action) async {
      try {
        final result = await action();
        if (context.mounted) Navigator.of(context).pop(result);
      } catch (_) {
        if (context.mounted) Navigator.of(context).pop(null);
      }
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Add attachment'),
            subtitle: Text('Choose an image, video, document, or audio file'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Photo from gallery'),
            onTap: () => pick(
              () => attachments.pickImage(source: ImageSource.gallery),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take a photo'),
            onTap: () => pick(
              () => attachments.pickImage(source: ImageSource.camera),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('Video'),
            onTap: () => pick(
              () => attachments.pickVideoAttachment(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('Document'),
            onTap: () => pick(attachments.pickDocument),
          ),
          ListTile(
            leading: const Icon(Icons.audio_file_outlined),
            title: const Text('Audio'),
            onTap: () => pick(attachments.pickAudio),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
