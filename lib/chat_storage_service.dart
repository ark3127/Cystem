import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/chat_conversation.dart';

class ChatStorageService {
  static const String _fileName = 'cystem_conversations.json';
  static const String _backupFileName = 'cystem_conversations.json.bak';
  static const String _tempFileName = 'cystem_conversations.json.tmp';
  static const int _storageVersion = 2;

  Future<Directory> _getStorageDirectory() =>
      getApplicationDocumentsDirectory();

  Future<File> _getStorageFile() async {
    final directory = await _getStorageDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<File> _getBackupFile() async {
    final directory = await _getStorageDirectory();
    return File('${directory.path}/$_backupFileName');
  }

  Future<File> _getTempFile() async {
    final directory = await _getStorageDirectory();
    return File('${directory.path}/$_tempFileName');
  }

  Future<List<ChatConversation>> loadConversations() async {
    final file = await _getStorageFile();
    final backup = await _getBackupFile();

    final primary = await _tryLoad(file);
    if (primary != null) return primary;

    final recovered = await _tryLoad(backup);
    return recovered ?? [];
  }

  Future<List<ChatConversation>?> _tryLoad(File file) async {
    try {
      if (!await file.exists()) return null;

      final contents = await file.readAsString();
      if (contents.trim().isEmpty) return [];

      final data = jsonDecode(contents);

      // Version 1 stored the conversations as a bare JSON array.
      if (data is List) return _decodeConversations(data);

      // Version 2 uses an envelope so future migrations can be added safely.
      if (data is Map<String, dynamic>) {
        final version = data['version'];
        final rawConversations = data['conversations'];

        if (version is int &&
            version <= _storageVersion &&
            rawConversations is List) {
          return _decodeConversations(rawConversations);
        }
      }
    } catch (_) {
      return null;
    }

    return null;
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
    final backup = await _getBackupFile();
    final temp = await _getTempFile();

    final data = {
      'version': _storageVersion,
      'conversations': conversations
          .map((conversation) => conversation.toJson())
          .toList(),
    };

    // Complete the new snapshot before replacing the live file.
    await temp.writeAsString(jsonEncode(data), flush: true);

    if (await file.exists()) {
      try {
        await file.copy(backup.path);
      } catch (_) {
        // Backup is best-effort; the new snapshot is still valid.
      }
    }

    try {
      await temp.rename(file.path);
    } catch (_) {
      // Fall back for platforms/filesystems where rename cannot replace the
      // existing destination.
      await file.writeAsString(await temp.readAsString(), flush: true);
      if (await temp.exists()) await temp.delete();
    }
  }
}
