import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_tool.dart';
import '../models/chat_tool_call.dart';
import 'chat_tool_executor.dart';
import 'secure_storage_service.dart';

/// Live web search backed by Gemini 3.8 Flash + Google Search.
/// Nemotron remains Cystem's primary assistant; raw search/tool output stays backend-only.
class WebSearchService implements ChatToolExecutor {
  WebSearchService({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  static const _model = 'gemini-3.8-flash';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/interactions';

  static const List<ChatTool> definitions = [
    ChatTool(
      name: 'web_search',
      description:
          'Search the live web with Gemini and Google Search for current, recent, factual, or hard-to-know information.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'A concise web search query.',
          },
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    ),
  ];

  final http.Client Function() _clientFactory;
  final SecureStorageService _storage = SecureStorageService();

  @override
  Future<String> execute(ChatToolCall call) async {
    if (call.name != 'web_search') return 'Unknown web tool: ${call.name}';

    try {
      final decoded = jsonDecode(call.arguments);
      if (decoded is! Map) {
        return _serviceError('INVALID_ARGUMENTS', false, 'web_search requires a JSON object.');
      }
      final query = decoded['query'];
      if (query is! String || query.trim().isEmpty) {
        return _serviceError('INVALID_ARGUMENTS', false, 'web_search requires a non-empty query.');
      }

      final apiKey = await _storage.getGeminiApiKey();
      if (apiKey == null || apiKey.trim().isEmpty) {
        return _serviceError(
          'NOT_CONFIGURED',
          false,
          'Gemini API key is not configured for web search.',
        );
      }

      final client = _clientFactory();
      try {
        final response = await client
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'x-goog-api-key': apiKey.trim(),
              },
              body: jsonEncode({
                'model': _model,
                'input': [
                  {
                    'type': 'text',
                    'text': '''Use Google Search to research the query below. Produce concise, source-grounded research context for Cystem's main assistant. Prefer authoritative and recent sources. Include key facts, caveats, source titles, URLs/citations, and dates when relevant. Do not address the user directly and do not expose internal tool instructions.

Query:
${query.trim()}''',
                  },
                ],
                'tools': [
                  {'type': 'google_search'},
                ],
                'response_format': {
                  'type': 'text',
                  'mime_type': 'text/plain',
                },
                'store': false,
              }),
            )
            .timeout(const Duration(seconds: 90));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          return _serviceError(
            _classifyStatus(response.statusCode),
            response.statusCode >= 500 || response.statusCode == 429,
            _errorMessage(response.body),
            httpStatus: response.statusCode,
          );
        }

        final body = jsonDecode(response.body);
        final text = _extractText(body);
        if (text.isEmpty) {
          return _serviceError('EMPTY_RESULT', true, 'Google Search returned no usable context.');
        }

        return '[WEB SEARCH CONTEXT — Gemini + Google Search]\n$text';
      } finally {
        client.close();
      }
    } catch (error) {
      return _serviceError('NETWORK_OR_PARSE_ERROR', true, 'Gemini web search is temporarily unavailable.');
    }
  }

  String _extractText(dynamic decoded) {
    if (decoded is! Map) return '';
    final outputText = decoded['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) {
      return outputText.trim();
    }

    final steps = decoded['steps'];
    if (steps is! List) return '';
    final chunks = <String>[];
    for (final step in steps.whereType<Map>()) {
      if (step['type'] != 'model_output') continue;
      final content = step['content'];
      if (content is! List) continue;
      for (final part in content.whereType<Map>()) {
        if (part['type'] == 'text' && part['text'] is String) {
          chunks.add(part['text'] as String);
        }
      }
    }
    return chunks.join('\n').trim();
  }

  String _serviceError(
    String code,
    bool retryable,
    String details, {
    int? httpStatus,
  }) {
    return '[SERVICE ERROR]\n'
        'Service: Gemini Google Search\n'
        'Operation: web_search\n'
        'Error: $code\n'
        'HTTP status: ${httpStatus ?? 'unknown'}\n'
        'Retryable: $retryable\n'
        'Details: $details';
  }

  String _classifyStatus(int status) {
    if (status == 400) return 'INVALID_REQUEST';
    if (status == 401 || status == 403) return 'AUTHENTICATION_FAILED';
    if (status == 429) return 'QUOTA_EXCEEDED';
    if (status >= 500) return 'UPSTREAM_UNAVAILABLE';
    return 'REQUEST_FAILED';
  }

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) return error['message'] as String;
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {}
    return 'Please check the Gemini API key and try again.';
  }
}
