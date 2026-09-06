import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/chat_stream_event.dart';
import '../models/chat_tool.dart';
import '../models/chat_tool_call.dart';
import 'app_settings_service.dart';
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

  final SecureStorageService _secureStorageService = SecureStorageService();
  final AppSettingsService _settingsService = AppSettingsService();

  Stream<ChatStreamEvent> streamMessage(
    List<ChatMessage> messages, {
    String? reasoningEffort,
    double? temperature,
    int? maxTokens,
    int? seed,
    bool clearSeed = false,
    List<ChatTool> tools = const [],
    dynamic toolChoice,
  }) {
    http.Client? client;
    late final StreamController<ChatStreamEvent> controller;

    controller = StreamController<ChatStreamEvent>(
      onListen: () async {
        client = http.Client();

        try {
          final apiKey = await _secureStorageService.getApiKey();
          if (apiKey == null || apiKey.isEmpty) {
            throw const NvidiaApiException(
              'No NVIDIA API key found. Add one in Settings.',
            );
          }

          final savedSettings = await _settingsService.load();
          final effectiveReasoningEffort =
              reasoningEffort ?? savedSettings.reasoningEffort;
          final effectiveTemperature =
              temperature ?? savedSettings.temperature;
          final effectiveMaxTokens = maxTokens ?? savedSettings.maxTokens;
          final effectiveSeed = clearSeed ? null : (seed ?? savedSettings.seed);

          final apiMessages = <Map<String, dynamic>>[];
          final systemPrompt = savedSettings.systemPrompt.trim();
          if (systemPrompt.isNotEmpty) {
            apiMessages.add({'role': 'system', 'content': systemPrompt});
          }
          apiMessages.addAll(messages.map((message) => message.toApiJson()));

          final body = <String, dynamic>{
            'model': model,
            'messages': apiMessages,
            'temperature': effectiveTemperature.clamp(0.0, 1.0),
            'max_tokens': effectiveMaxTokens.clamp(1, 65536),
            'reasoning_effort': effectiveReasoningEffort,
            if (effectiveSeed != null) 'seed': effectiveSeed,
            if (tools.isNotEmpty)
              'tools': tools.map((tool) => tool.toApiJson()).toList(),
            if (toolChoice != null) 'tool_choice': toolChoice,
            'stream': true,
            'stream_options': {'include_usage': true},
          };

          final request = http.Request('POST', Uri.parse(_baseUrl));
          request.headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          });
          request.body = jsonEncode(body);

          final response = await client!.send(request);
          if (response.statusCode != 200) {
            final errorBody = await response.stream.bytesToString();
            throw _createApiException(response.statusCode, errorBody);
          }

          String buffer = '';
          final streamedToolCalls = <int, _ToolCallAccumulator>{};

          await for (final chunk in response.stream.transform(utf8.decoder)) {
            buffer += chunk;
            final lines = buffer.split('\n');
            buffer = lines.removeLast();

            for (final rawLine in lines) {
              final line = rawLine.trim();
              if (!line.startsWith('data:')) continue;
              final data = line.substring(5).trim();

              if (data == '[DONE]') {
                if (!controller.isClosed) await controller.close();
                return;
              }
              if (data.isEmpty) continue;

              try {
                final decoded = jsonDecode(data);
                if (decoded is! Map) continue;

                final choices = decoded['choices'];
                final usage = decoded['usage'];
                final responseId = decoded['id'] is String
                    ? decoded['id'] as String
                    : null;
                final responseModel = decoded['model'] is String
                    ? decoded['model'] as String
                    : null;

                String? text;
                String? reasoning;
                String? finishReason;

                if (choices is List &&
                    choices.isNotEmpty &&
                    choices.first is Map) {
                  final choice = choices.first as Map;
                  if (choice['finish_reason'] is String) {
                    finishReason = choice['finish_reason'] as String;
                  }

                  final delta = choice['delta'];
                  if (delta is Map) {
                    if (delta['content'] is String) {
                      text = delta['content'] as String;
                    }
                    if (delta['reasoning_content'] is String) {
                      reasoning = delta['reasoning_content'] as String;
                    }

                    final rawToolCalls = delta['tool_calls'];
                    if (rawToolCalls is List) {
                      for (var position = 0;
                          position < rawToolCalls.length;
                          position++) {
                        final rawCall = rawToolCalls[position];
                        if (rawCall is! Map) continue;

                        final rawIndex = rawCall['index'];
                        final index = rawIndex is num
                            ? rawIndex.toInt()
                            : position;
                        final accumulator = streamedToolCalls.putIfAbsent(
                          index,
                          _ToolCallAccumulator.new,
                        );

                        final id = rawCall['id'];
                        if (id is String && id.isNotEmpty) {
                          accumulator.id = id;
                        }

                        final function = rawCall['function'];
                        if (function is Map) {
                          final name = function['name'];
                          if (name is String && name.isNotEmpty) {
                            accumulator.name = name;
                          }
                          final arguments = function['arguments'];
                          if (arguments is String) {
                            accumulator.arguments += arguments;
                          }
                        }
                      }
                    }
                  }
                }

                final toolCalls = streamedToolCalls.values
                    .where((call) => call.id != null && call.name != null)
                    .map((call) => ChatToolCall(
                          id: call.id!,
                          name: call.name!,
                          arguments: call.arguments.isEmpty
                              ? '{}'
                              : call.arguments,
                        ))
                    .toList();

                int? promptTokens;
                int? completionTokens;
                int? totalTokens;
                if (usage is Map) {
                  if (usage['prompt_tokens'] is num) {
                    promptTokens = (usage['prompt_tokens'] as num).toInt();
                  }
                  if (usage['completion_tokens'] is num) {
                    completionTokens =
                        (usage['completion_tokens'] as num).toInt();
                  }
                  if (usage['total_tokens'] is num) {
                    totalTokens = (usage['total_tokens'] as num).toInt();
                  }
                }

                if (text != null ||
                    reasoning != null ||
                    toolCalls.isNotEmpty ||
                    finishReason != null ||
                    usage is Map ||
                    responseId != null ||
                    responseModel != null) {
                  controller.add(ChatStreamEvent(
                    text: text,
                    reasoning: reasoning,
                    toolCalls: toolCalls,
                    responseId: responseId,
                    model: responseModel,
                    finishReason: finishReason,
                    promptTokens: promptTokens,
                    completionTokens: completionTokens,
                    totalTokens: totalTokens,
                  ));
                }
              } on FormatException {
                // Ignore malformed/incomplete SSE JSON frames.
              }
            }
          }

          if (!controller.isClosed) await controller.close();
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
          if (!controller.isClosed) controller.addError(error, stackTrace);
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

  NvidiaApiException _createApiException(int statusCode, String responseBody) {
    String? apiMessage;
    try {
      final decoded = jsonDecode(responseBody);
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.isNotEmpty) apiMessage = message;
      }
    } catch (_) {}

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

class _ToolCallAccumulator {
  String? id;
  String? name;
  String arguments = '';
}
