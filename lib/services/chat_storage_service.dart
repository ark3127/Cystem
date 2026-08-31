import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/chat_conversation.dart';

class ChatStorageService {
  static const String _fileName =
      'cystem_conversations.json';

  Future<File> _getStorageFile() async {
    final directory =
        await getApplicationDocumentsDirectory();

    return File(
      '${directory.path}/$_fileName',
    );
  }

  Future<List<ChatConversation>>
      loadConversations() async {
    try {
      final file = await _getStorageFile();

      if (!await file.exists()) {
        return [];
      }

      final contents = await file.readAsString();

      if (contents.trim().isEmpty) {
        return [];
      }

      final data = jsonDecode(contents);

      if (data is! List) {
        return [];
      }

      return data
          .map(
            (conversation) =>
                ChatConversation.fromJson(
              Map<String, dynamic>.from(
                conversation as Map,
              ),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConversations(
    List<ChatConversation> conversations,
  ) async {
    final file = await _getStorageFile();

    final data = conversations
        .map(
          (conversation) =>
              conversation.toJson(),
        )
        .toList();

    await file.writeAsString(
      jsonEncode(data),
      flush: true,
    );
  }
}
