import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/chat_completion_result.dart';
import '../models/chat_message.dart';
import '../models/chat_response_format.dart';
import '../models/chat_stream_event.dart';
import '../models/chat_tool.dart';
import '../models/chat_tool_call.dart';
import 'app_settings_service.dart';
import 'chat_cancellation_token.dart';
import 'secure_storage_service.dart';

class NvidiaApiException implements Exception {
  final int? statusCode;
  final String message;

  const NvidiaApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class NvidiaApiService {
  NvidiaApiService({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  static const String _baseUrl =
      'https://integrate.api.nvidia.com/v1/chat/completions';
  static const String _statusBaseUrl =
      'https://integrate.api.nvidia.com/v1/status';
  static const String model = 'nvidia/nemotron-3-super-120b-a12b';
  static const Duration requestTimeout = Duration(minutes: 5);
  static const Duration pollInterval = Duration(seconds: 1);
  static const int maxPollAttempts = 300;

  final http.Client Function() _clientFactory;
  final SecureStorageService _secureStorageService = SecureStorageService();
  final AppSettingsService _settingsService = AppSettingsService();

  Future<ChatCompletionResult> completeMessage(
    List<ChatMessage> messages, {
    String? reasoningEffort,
    double? temperature,
    int? maxTokens,
    int? seed,
    bool clearSeed = false,
    List<ChatTool> tools = const [],
    dynamic toolChoice,
    ChatResponseFormat? responseFormat,
  }) async {
    final apiKey = await _apiKey();
    final body = await _buildBody(
      messages,
      reasoningEffort: reasoningEffort,
      temperature: temperature,
      maxTokens: maxTokens,
      seed: seed,
      clearSeed: clearSeed,
      tools: tools,
      toolChoice: toolChoice,
      responseFormat: responseFormat,
      stream: false,
    );
    final client = _clientFactory();
    try {
      final response = await client
          .post(
            Uri.parse(_baseUrl),
            headers: _headers(apiKey, 'application/json'),
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
      final resolved = await _resolvePendingJsonResponse(
        client,
        response,
        apiKey,
      );
      return _parseCompletion(resolved);
    } on NvidiaApiException {
      rethrow;
    } on TimeoutException {
      throw const NvidiaApiException(
        'NVIDIA request timed out. Please try again.',
      );
    } on SocketException {
      throw const NvidiaApiException(
        'Could not connect to NVIDIA NIM. Check your internet connection.',
      );
    } on http.ClientException catch (error) {
      throw NvidiaApiException(
        'Network error while connecting to NVIDIA NIM: ${error.message}',
      );
    } on FormatException {
      throw const NvidiaApiException(
        'NVIDIA returned invalid JSON for the chat completion.',
      );
    } finally {
      client.close();
    }
  }

  Stream<ChatStreamEvent> streamMessage(
    List<ChatMessage> messages, {
    String? reasoningEffort,
    double? temperature,
    int? maxTokens,
    int? seed,
    bool clearSeed = false,
    List<ChatTool> tools = const [],
    dynamic toolChoice,
    ChatResponseFormat? responseFormat,
    ChatCancellationToken? cancellationToken,
  }) {
    http.Client? client;
    late final StreamController<ChatStreamEvent> controller;
    void cancelHttp() => client?.close();

    controller = StreamController<ChatStreamEvent>(onListen: () async {
      client = _clientFactory();
      final token = cancellationToken;
      token?.addCancellationListener(cancelHttp);
      try {
        token?.throwIfCancelled();
        final apiKey = await _apiKey();
        final body = await _buildBody(
          messages,
          reasoningEffort: reasoningEffort,
          temperature: temperature,
          maxTokens: maxTokens,
          seed: seed,
          clearSeed: clearSeed,
          tools: tools,
          toolChoice: toolChoice,
          responseFormat: responseFormat,
          stream: true,
        );
        final request = http.Request('POST', Uri.parse(_baseUrl));
        request.headers.addAll(_headers(apiKey, 'text/event-stream'));
        request.body = jsonEncode(body);
        final response = await client!.send(request).timeout(requestTimeout);

        if (response.statusCode == 202) {
          final pendingBody = await response.stream
              .bytesToString()
              .timeout(requestTimeout);
          final resolved = await _pollPendingResponse(
            client!,
            pendingBody,
            apiKey,
            token,
          );
          token?.throwIfCancelled();
          controller.add(_completionToEvent(_parseCompletion(resolved)));
          await controller.close();
          return;
        }
        if (response.statusCode != 200) {
          final errorBody = await response.stream
              .bytesToString()
              .timeout(requestTimeout);
          throw _createApiException(response.statusCode, errorBody);
        }

        final streamedToolCalls = <int, _ToolCallAccumulator>{};
        String buffer = '';
        var done = false;

        await for (final chunk in response.stream
            .transform(utf8.decoder)
            .timeout(requestTimeout)) {
          token?.throwIfCancelled();
          buffer += chunk;
          while (true) {
            final separator = _findEventSeparator(buffer);
            if (separator == -1) break;
            final eventBlock = buffer.substring(0, separator);
            buffer = buffer.substring(
              separator + _separatorLength(buffer, separator),
            );
            final data = _extractSseData(eventBlock);
            if (data == null || data.isEmpty) continue;
            if (data == '[DONE]') {
              done = true;
              break;
            }
            _emitSseJson(data, streamedToolCalls, controller);
          }
          if (done) break;
        }

        if (!done && buffer.trim().isNotEmpty) {
          final data = _extractSseData(buffer);
          if (data != null && data.isNotEmpty && data != '[DONE]') {
            _emitSseJson(data, streamedToolCalls, controller);
          }
        }
        if (!done) {
          throw const NvidiaApiException(
            'NVIDIA ended the stream before the completion marker was received.',
          );
        }

        final finalToolCalls = streamedToolCalls.values
            .where((call) => call.id != null && call.name != null)
            .map(
              (call) => ChatToolCall(
                id: call.id!,
                name: call.name!,
                arguments: call.arguments.isEmpty ? '{}' : call.arguments,
              ),
            )
            .toList();
        if (finalToolCalls.isNotEmpty) {
          controller.add(ChatStreamEvent(toolCalls: finalToolCalls));
        }
        if (!controller.isClosed) await controller.close();
      } on ChatGenerationCancelledException {
        if (!controller.isClosed) await controller.close();
      } on TimeoutException catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(
            const NvidiaApiException(
              'NVIDIA request timed out. Please try again.',
            ),
            stackTrace,
          );
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
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        cancellationToken?.removeCancellationListener(cancelHttp);
        client?.close();
        client = null;
      }
    }, onCancel: () {
      client?.close();
      client = null;
    });
    return controller.stream;
  }

  Future<String> _apiKey() async {
    final apiKey = await _secureStorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw const NvidiaApiException(
        'No NVIDIA API key found. Add one in Settings.',
      );
    }
    return apiKey;
  }

  Future<Map<String, dynamic>> _buildBody(
    List<ChatMessage> messages, {
    required bool stream,
    String? reasoningEffort,
    double? temperature,
    int? maxTokens,
    int? seed,
    bool clearSeed = false,
    List<ChatTool> tools = const [],
    dynamic toolChoice,
    ChatResponseFormat? responseFormat,
  }) async {
    final savedSettings = await _settingsService.load();
    final effectiveSeed = clearSeed ? null : (seed ?? savedSettings.seed);
    final apiMessages = <Map<String, dynamic>>[];
    final systemPrompt = savedSettings.systemPrompt.trim();
    if (systemPrompt.isNotEmpty) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }
    apiMessages.addAll(messages.map((message) => message.toApiJson()));

    final effectiveReasoning = reasoningEffort ?? savedSettings.reasoningEffort;
    final effectiveMaxTokens =
        (maxTokens ?? savedSettings.maxTokens).clamp(1, 32768);

    return {
      'model': model,
      'messages': apiMessages,
      'temperature':
          (temperature ?? savedSettings.temperature).clamp(0.0, 1.0),
      'top_p': 0.95,
      'max_tokens': effectiveMaxTokens,
      'reasoning_effort': effectiveReasoning,
      'reasoning_budget': effectiveReasoning == 'none'
          ? 0
          : effectiveMaxTokens,
      if (effectiveSeed != null) 'seed': effectiveSeed,
      if (tools.isNotEmpty)
        'tools': tools.map((tool) => tool.toApiJson()).toList(),
      if (toolChoice != null) 'tool_choice': toolChoice,
      if (responseFormat != null)
        'response_format': responseFormat.toApiJson(),
      'stream': stream,
    };
  }

  Map<String, String> _headers(String apiKey, String accept) => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': accept,
      };

  Future<String> _resolvePendingJsonResponse(
    http.Client client,
    http.Response response,
    String apiKey,
  ) async {
    if (response.statusCode == 202) {
      return _pollPendingResponse(client, response.body, apiKey, null);
    }
    if (response.statusCode != 200) {
      throw _createApiException(response.statusCode, response.body);
    }
    return response.body;
  }

  Future<String> _pollPendingResponse(
    http.Client client,
    String pendingBody,
    String apiKey,
    ChatCancellationToken? token,
  ) async {
    final decoded = jsonDecode(pendingBody);
    final requestId =
        decoded is Map ? (decoded['requestId'] ?? decoded['request_id']) : null;
    if (requestId is! String || requestId.isEmpty) {
      throw const NvidiaApiException(
        'NVIDIA returned HTTP 202 without a requestId.',
        statusCode: 202,
      );
    }

    for (var attempt = 0; attempt < maxPollAttempts; attempt++) {
      token?.throwIfCancelled();
      if (attempt > 0) await Future<void>.delayed(pollInterval);
      final response = await client
          .get(
            Uri.parse('$_statusBaseUrl/$requestId'),
            headers: _headers(apiKey, 'application/json'),
          )
          .timeout(requestTimeout);
      if (response.statusCode == 200) return response.body;
      if (response.statusCode == 202) continue;
      throw _createApiException(response.statusCode, response.body);
    }

    throw const NvidiaApiException(
      'NVIDIA kept the request pending for too long. Please try again.',
      statusCode: 202,
    );
  }

  ChatCompletionResult _parseCompletion(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const NvidiaApiException(
        'NVIDIA returned an invalid chat-completion response.',
      );
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const NvidiaApiException(
        'NVIDIA returned a chat-completion response without a choice.',
      );
    }
    final choice = choices.first as Map;
    final rawMessage = choice['message'];
    if (rawMessage is! Map) {
      throw const NvidiaApiException(
        'NVIDIA returned a chat-completion without an assistant message.',
      );
    }

    final toolCalls = <ChatToolCall>[];
    final rawToolCalls = rawMessage['tool_calls'];
    if (rawToolCalls is List) {
      for (final rawCall in rawToolCalls) {
        if (rawCall is! Map) continue;
        final id = rawCall['id'];
        final function = rawCall['function'];
        if (id is! String || function is! Map) continue;
        final name = function['name'];
        final arguments = function['arguments'];
        if (name is String && arguments is String) {
          toolCalls.add(
            ChatToolCall(id: id, name: name, arguments: arguments),
          );
        }
      }
    }

    final message = ChatMessage(
      id: 'api_${DateTime.now().microsecondsSinceEpoch}',
      content: rawMessage['content'] is String
          ? rawMessage['content'] as String
          : '',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      reasoningContent: rawMessage['reasoning_content'] is String
          ? rawMessage['reasoning_content'] as String
          : null,
      toolCalls: toolCalls,
    );

    final usage = decoded['usage'];
    int? promptTokens;
    int? completionTokens;
    int? totalTokens;
    if (usage is Map) {
      if (usage['prompt_tokens'] is num) {
        promptTokens = (usage['prompt_tokens'] as num).toInt();
      }
      if (usage['completion_tokens'] is num) {
        completionTokens = (usage['completion_tokens'] as num).toInt();
      }
      if (usage['total_tokens'] is num) {
        totalTokens = (usage['total_tokens'] as num).toInt();
      }
    }

    return ChatCompletionResult(
      message: message,
      responseId: decoded['id'] is String ? decoded['id'] as String : null,
      model: decoded['model'] is String ? decoded['model'] as String : null,
      finishReason:
          choice['finish_reason'] is String
              ? choice['finish_reason'] as String
              : null,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }

  ChatStreamEvent _completionToEvent(ChatCompletionResult result) =>
      ChatStreamEvent(
        text: result.message.content,
        reasoning: result.message.reasoningContent,
        toolCalls: result.message.toolCalls,
        responseId: result.responseId,
        model: result.model,
        finishReason: result.finishReason,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        totalTokens: result.totalTokens,
      );

  void _emitSseJson(
    String data,
    Map<int, _ToolCallAccumulator> streamedToolCalls,
    StreamController<ChatStreamEvent> controller,
  ) {
    final decoded = jsonDecode(data);
    if (decoded is! Map) {
      throw const NvidiaApiException('NVIDIA returned an invalid SSE event.');
    }
    final choices = decoded['choices'];
    final usage = decoded['usage'];
    final responseId = decoded['id'] is String ? decoded['id'] as String : null;
    final responseModel =
        decoded['model'] is String ? decoded['model'] as String : null;
    String? text;
    String? reasoning;
    String? finishReason;

    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final choice = choices.first as Map;
      if (choice['finish_reason'] is String) {
        finishReason = choice['finish_reason'] as String;
      }
      final delta = choice['delta'];
      if (delta is Map) {
        if (delta['content'] is String) text = delta['content'] as String;
        if (delta['reasoning_content'] is String) {
          reasoning = delta['reasoning_content'] as String;
        }
        final rawToolCalls = delta['tool_calls'];
        if (rawToolCalls is List) {
          for (var position = 0; position < rawToolCalls.length; position++) {
            final rawCall = rawToolCalls[position];
            if (rawCall is! Map) continue;
            final rawIndex = rawCall['index'];
            final index = rawIndex is num ? rawIndex.toInt() : position;
            final accumulator = streamedToolCalls.putIfAbsent(
              index,
              _ToolCallAccumulator.new,
            );
            final id = rawCall['id'];
            if (id is String && id.isNotEmpty) accumulator.id = id;
            final function = rawCall['function'];
            if (function is Map) {
              final name = function['name'];
              if (name is String && name.isNotEmpty) accumulator.name = name;
              final arguments = function['arguments'];
              if (arguments is String) accumulator.arguments += arguments;
            }
          }
        }
      }
    }

    int? promptTokens;
    int? completionTokens;
    int? totalTokens;
    if (usage is Map) {
      if (usage['prompt_tokens'] is num) {
        promptTokens = (usage['prompt_tokens'] as num).toInt();
      }
      if (usage['completion_tokens'] is num) {
        completionTokens = (usage['completion_tokens'] as num).toInt();
      }
      if (usage['total_tokens'] is num) {
        totalTokens = (usage['total_tokens'] as num).toInt();
      }
    }

    if (text != null ||
        reasoning != null ||
        finishReason != null ||
        usage is Map ||
        responseId != null ||
        responseModel != null) {
      controller.add(
        ChatStreamEvent(
          text: text,
          reasoning: reasoning,
          responseId: responseId,
          model: responseModel,
          finishReason: finishReason,
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: totalTokens,
        ),
      );
    }
  }

  int _findEventSeparator(String buffer) {
    final crlf = buffer.indexOf('\r\n\r\n');
    final lf = buffer.indexOf('\n\n');
    if (crlf == -1) return lf;
    if (lf == -1) return crlf;
    return crlf < lf ? crlf : lf;
  }

  int _separatorLength(String buffer, int index) =>
      buffer.startsWith('\r\n\r\n', index) ? 4 : 2;

  String? _extractSseData(String eventBlock) {
    final dataLines = <String>[];
    for (final rawLine in eventBlock.split(RegExp(r'\r?\n'))) {
      if (rawLine.startsWith(':')) continue;
      if (rawLine.startsWith('data:')) {
        var value = rawLine.substring(5);
        if (value.startsWith(' ')) value = value.substring(1);
        dataLines.add(value);
      }
    }
    return dataLines.isEmpty ? null : dataLines.join('\n');
  }

  NvidiaApiException _createApiException(
    int statusCode,
    String responseBody,
  ) {
    String? apiMessage;
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = error['message'];
          if (message is String && message.isNotEmpty) apiMessage = message;
        }
      }
    } catch (_) {}

    final message = switch (statusCode) {
      400 =>
        'NVIDIA rejected the request. ${apiMessage ?? 'Check the request parameters.'}',
      401 => 'NVIDIA API key is invalid or unauthorized.',
      403 => 'NVIDIA denied access to the Nemotron API.',
      404 => 'Nemotron 3 Super was not found at the NVIDIA NIM endpoint.',
      408 => 'NVIDIA request timed out. Please try again.',
      409 => 'NVIDIA reported a request conflict. Please try again.',
      422 =>
        'NVIDIA rejected the request as invalid. ${apiMessage ?? 'Check the request parameters.'}',
      429 => 'NVIDIA rate limit reached. Please wait and try again.',
      >= 500 =>
        'NVIDIA NIM is temporarily unavailable. Please try again later.',
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
