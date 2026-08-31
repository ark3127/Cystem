import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import 'secure_storage_service.dart';

class NvidiaApiService {
  static const String _endpoint =
      'https://integrate.api.nvidia.com/v1/chat/completions';

  static const String model =
      'nvidia/nemotron-3-ultra-550b-a55b';

  final SecureStorageService _storageService =
      SecureStorageService();

  Stream<String> streamMessage(
    List<ChatMessage> messages,
  ) async* {
    final apiKey = await _storageService.getApiKey();

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(
        'No NVIDIA API key found. Add one in Settings.',
      );
    }

    final request = http.Request(
      'POST',
      Uri.parse(_endpoint),
    );

    request.headers.addAll({
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    });

    request.body = jsonEncode({
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
      'stream': true,
      'chat_template_kwargs': {
        'enable_thinking': true,
      },
    });

    final streamedResponse = await request.send();

    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      final errorBody =
          await streamedResponse.stream.bytesToString();

      throw Exception(
        'NVIDIA API error '
        '(${streamedResponse.statusCode}): '
        '$errorBody',
      );
    }

    await for (final line
        in streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) {
        continue;
      }

      final data = line.substring(6).trim();

      if (data == '[DONE]') {
        break;
      }

      try {
        final json = jsonDecode(data);

        final choices = json['choices'];

        if (choices is! List || choices.isEmpty) {
          continue;
        }

        final delta = choices.first['delta'];

        if (delta is! Map<String, dynamic>) {
          continue;
        }

        final content = delta['content'];

        if (content is String && content.isNotEmpty) {
          yield content;
        }
      } catch (_) {
        // Ignore malformed SSE chunks.
      }
    }
  }
}
