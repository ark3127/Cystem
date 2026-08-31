import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import 'secure_storage_service.dart';

class NvidiaApiService {
  NvidiaApiService();

  static const String _baseUrl =
      'https://integrate.api.nvidia.com/v1/chat/completions';

  static const String _model =
      'nvidia/nemotron-3-ultra-550b-a55b';

  final SecureStorageService _secureStorageService =
      SecureStorageService();

  Stream<String> streamMessage(
    List<ChatMessage> messages,
  ) {
    http.Client? client;

    late final StreamController<String> controller;

    controller = StreamController<String>(
      onListen: () async {
        client = http.Client();

        try {
          final apiKey =
              await _secureStorageService.getApiKey();

          if (apiKey == null || apiKey.isEmpty) {
            throw Exception(
              'No NVIDIA API key found. '
              'Add one in Settings.',
            );
          }

          final request = http.Request(
            'POST',
            Uri.parse(_baseUrl),
          );

          request.headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          });

          request.body = jsonEncode({
            'model': _model,
            'messages': messages.map((message) {
              return {
                'role': message.isUser
                    ? 'user'
                    : 'assistant',
                'content': message.content,
              };
            }).toList(),
            'temperature': 0.7,
            'top_p': 1.0,
            'max_tokens': 4096,
            'stream': true,
          });

          final response =
              await client!.send(request);

          if (response.statusCode != 200) {
            final errorBody =
                await response.stream.bytesToString();

            throw Exception(
              'NVIDIA API error '
              '${response.statusCode}: $errorBody',
            );
          }

          String buffer = '';

          await for (final chunk
              in response.stream.transform(
            utf8.decoder,
          )) {
            buffer += chunk;

            final lines = buffer.split('\n');

            buffer = lines.removeLast();

            for (final rawLine in lines) {
              final line = rawLine.trim();

              if (!line.startsWith('data:')) {
                continue;
              }

              final data =
                  line.substring(5).trim();

              if (data == '[DONE]') {
                if (!controller.isClosed) {
                  await controller.close();
                }
                return;
              }

              try {
                final decoded =
                    jsonDecode(data);

                final content = decoded
                    ['choices']?[0]
                    ['delta']?['content'];

                if (content != null &&
                    content is String &&
                    content.isNotEmpty) {
                  controller.add(content);
                }
              } catch (_) {
                // Ignore incomplete or malformed
                // streaming chunks.
              }
            }
          }

          if (!controller.isClosed) {
            await controller.close();
          }
        } catch (error, stackTrace) {
          if (!controller.isClosed) {
            controller.addError(
              error,
              stackTrace,
            );
          }
        } finally {
          client?.close();
          client = null;
        }
      },
      onCancel: () {
        client?.close();
        client = null;
      },
    );

    return controller.stream;
  }
}
