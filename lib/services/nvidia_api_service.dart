import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import 'secure_storage_service.dart';

class NvidiaApiException implements Exception {
  final int? statusCode;
  final String message;

  const NvidiaApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class NvidiaApiService {
  NvidiaApiService();

  static const String _baseUrl =
      'https://integrate.api.nvidia.com/v1/chat/completions';

  static const String model = 'moonshotai/kimi-k3';

  final SecureStorageService _secureStorageService =
      SecureStorageService();

  Stream<String> streamMessage(
    List<ChatMessage> messages, {
    String reasoningEffort = 'max',
    double temperature = 1.0,
    int maxTokens = 16384,
  }) {
    http.Client? client;
    late final StreamController<String> controller;

    controller = StreamController<String>(
      onListen: () async {
        client = http.Client();

        try {
          final apiKey = await _secureStorageService.getApiKey();

          if (apiKey == null || apiKey.isEmpty) {
            throw const NvidiaApiException(
              'No NVIDIA API key found. Add one in Settings.',
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
            'model': model,
            'messages': messages
                .map((message) => message.toApiJson())
                .toList(),
            'temperature': temperature.clamp(0.0, 1.0),
            'max_tokens': maxTokens.clamp(1, 65536),
            'reasoning_effort': reasoningEffort,
            'stream': true,
            'stream_options': {
              'include_usage': true,
            },
          });

          final response = await client!.send(request);

          if (response.statusCode != 200) {
            final errorBody = await response.stream.bytesToString();
            throw _createApiException(response.statusCode, errorBody);
          }

          String buffer = '';

          await for (final chunk
              in response.stream.transform(utf8.decoder)) {
            buffer += chunk;

            final lines = buffer.split('\n');
            buffer = lines.removeLast();

            for (final rawLine in lines) {
              final line = rawLine.trim();

              if (!line.startsWith('data:')) {
                continue;
              }

              final data = line.substring(5).trim();

              if (data == '[DONE]') {
                if (!controller.isClosed) {
                  await controller.close();
                }
                return;
              }

              if (data.isEmpty) {
                continue;
              }

              try {
                final decoded = jsonDecode(data);
                final choices = decoded['choices'];

                if (choices is! List || choices.isEmpty) {
                  continue;
                }

                final choice = choices.first;
                if (choice is! Map<String, dynamic>) {
                  continue;
                }

                final delta = choice['delta'];
                if (delta is! Map<String, dynamic>) {
                  continue;
                }

                final content = delta['content'];

                if (content is String && content.isNotEmpty) {
                  controller.add(content);
                }
              } on FormatException {
                // Ignore malformed/incomplete SSE JSON frames.
              }
            }
          }

          if (!controller.isClosed) {
            await controller.close();
          }
        } on SocketException catch (error, stackTrace) {
          if (!controller.isClosed) {
            controller.addError(
              const NvidiaApiException(
                'Could not connect to NVIDIA NIM. Check your internet connection.',
              ),
              stackTrace,
            );
          }
        } on http.ClientException catch (error, stackTrace) {
          if (!controller.isClosed) {
            controller.addError(
              NvidiaApiException(
                'Network error while connecting to NVIDIA NIM: ${error.message}',
              ),
              stackTrace,
            );
          }
        } catch (error, stackTrace) {
          if (!controller.isClosed) {
            controller.addError(error, stackTrace);
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

  NvidiaApiException _createApiException(
    int statusCode,
    String responseBody,
  ) {
    String? apiMessage;

    try {
      final decoded = jsonDecode(responseBody);
      final error = decoded['error'];

      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.isNotEmpty) {
          apiMessage = message;
        }
      }
    } catch (_) {
      // Fall back to the HTTP status-specific message below.
    }

    final message = switch (statusCode) {
      400 => 'NVIDIA rejected the request. ${apiMessage ?? 'Check the request parameters.'}',
      401 => 'NVIDIA API key is invalid or unauthorized.',
      403 => 'NVIDIA denied access to the Kimi K3 API.',
      404 => 'Kimi K3 was not found at the NVIDIA NIM endpoint.',
      408 => 'NVIDIA request timed out. Please try again.',
      409 => 'NVIDIA reported a request conflict. Please try again.',
      429 => 'NVIDIA rate limit reached. Please wait and try again.',
      >= 500 => 'NVIDIA NIM is temporarily unavailable. Please try again later.',
      _ => 'NVIDIA API returned HTTP $statusCode. ${apiMessage ?? ''}'.trim(),
    };

    return NvidiaApiException(message, statusCode: statusCode);
  }
}
