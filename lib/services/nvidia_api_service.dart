import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import 'secure_storage_service.dart';

class NvidiaApiService {
  static const String _baseUrl =
      'https://integrate.api.nvidia.com/v1/chat/completions';

  static const String model =
      'nvidia/nemotron-3-ultra-550b-a55b';

  final SecureStorageService _storageService =
      SecureStorageService();

  Future<String> sendMessage(
    List<ChatMessage> messages,
  ) async {
    final apiKey = await _storageService.getApiKey();

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(
        'No NVIDIA API key found. Add one in Settings.',
      );
    }

    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages.map((message) {
          return {
            'role': message.role.name,
            'content': message.content,
          };
        }).toList(),
        'temperature': 1.0,
        'top_p': 0.95,
        'max_tokens': 16384,
        'stream': false,
        'chat_template_kwargs': {
          'enable_thinking': true,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'NVIDIA API error (${response.statusCode}): '
        '${response.body}',
      );
    }

    final data = jsonDecode(response.body);

    final content =
        data['choices']?[0]?['message']?['content'];

    if (content == null || content is! String) {
      throw Exception(
        'The API returned an unexpected response.',
      );
    }

    return content;
  }
}
