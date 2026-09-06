import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/chat_conversation.dart';

class ChatStorageService {
  static const String _fileName = 'cystem_conversations.json';
  static const int _storageVersion = 2;

  Future<File> _getStorageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<ChatConversation>> loadConversations() async {
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

      // Version 1 stored the conversations as a bare JSON array.
      // Version 2 uses an envelope so future migrations can be added safely.
      if (data is List) {
        return _decodeConversations(data);
      }

      if (data is Map<String, dynamic>) {
        final version = data['version'];
        final rawConversations = data['conversations'];

        if (version is int && version <= _storageVersion &&
            rawConversations is List) {
          return _decodeConversations(rawConversations);
        }
      }

      return [];
    } catch (_) {
      return [];
    }
  }

  List<ChatConversation> _decodeConversations(List<dynamic> data) {
    return data
        .whereType<Map>()
        .map(
          (conversation) => ChatConversation.fromJson(
            Map<String, dynamic>.from(conversation),
          ),
        )
        .toList();
  }

  Future<void> saveConversations(
    List<ChatConversation> conversations,
  ) async {
    final file = await _getStorageFile();

    final data = {
      'version': _storageVersion,
      'conversations': conversations
          .map((conversation) => conversation.toJson())
          .toList(),
    };

    await file.writeAsString(
      jsonEncode(data),
      flush: true,
    );
  }
}
