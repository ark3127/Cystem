import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_tool.dart';
import '../models/chat_tool_call.dart';
import 'chat_tool_executor.dart';
import 'secure_storage_service.dart';

/// Web search tool backed by Tavily Search API.
class WebSearchService implements ChatToolExecutor {
  WebSearchService({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  static const List<ChatTool> definitions = [
    ChatTool(
      name: 'web_search',
      description:
          'Search the live web for current, factual, recent, or hard-to-know information. If the user asks to find/show an existing image rather than generate one, search for images too and return usable image URLs.',
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
        return _serviceError(
          code: 'INVALID_ARGUMENTS',
          httpStatus: 400,
          retryable: false,
          details: 'web_search requires a JSON object.',
        );
      }
      final query = decoded['query'];
      if (query is! String || query.trim().isEmpty) {
        return _serviceError(
          code: 'INVALID_ARGUMENTS',
          httpStatus: 400,
          retryable: false,
          details: 'web_search requires a non-empty query.',
        );
      }

      final apiKey = await _storage.getTavilySearchApiKey();
      if (apiKey == null || apiKey.trim().isEmpty) {
        return _serviceError(
          code: 'NOT_CONFIGURED',
          retryable: false,
          details: 'Tavily API key is not configured.',
        );
      }

      final client = _clientFactory();
      try {
        final response = await client
            .post(
              Uri.https('api.tavily.com', '/search'),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'Authorization': 'Bearer ${apiKey.trim()}',
              },
              body: jsonEncode({
                'query': query.trim(),
                'search_depth': 'basic',
                'topic': 'general',
                'max_results': 6,
                'include_answer': false,
                'include_raw_content': false,
                'include_images': true,
              }),
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode != 200) {
          return _serviceError(
            code: _classifyStatus(response.statusCode, response.body),
            httpStatus: response.statusCode,
            retryable: response.statusCode >= 500 || response.statusCode == 429,
            details: _errorMessage(response.body),
          );
        }

        final body = jsonDecode(response.body);
        final results = body is Map ? body['results'] : null;
        final images = body is Map ? body['images'] : null;
        if (results is! List || results.isEmpty) {
          return 'No web results found for "$query".';
        }

        final buffer = StringBuffer('Search results for "$query":\n\n');
        var index = 0;
        for (final item in results) {
          if (item is! Map) continue;
          final title = item['title'];
          final url = item['url'];
          final content = item['content'];
          if (title is! String || url is! String) continue;
          index++;
          final snippet = content is String ? _clean(content) : '';
          buffer.writeln('[$index] [$title]($url)');
          if (snippet.isNotEmpty) buffer.writeln(snippet);
          buffer.writeln();
          if (index >= 6) break;
        }

        if (images is List && images.isNotEmpty) {
          buffer.writeln('WEB IMAGE RESULTS:\n');
          var imageIndex = 0;
          for (final item in images) {
            String? imageUrl;
            String description = '';
            if (item is String) {
              imageUrl = item;
            } else if (item is Map) {
              final value = item['url'] ?? item['image_url'];
              if (value is String) imageUrl = value;
              if (item['description'] is String) {
                description = _clean(item['description'] as String);
              }
            }
            if (imageUrl == null || !imageUrl.startsWith('http')) continue;
            imageIndex++;
            final alt = description.isEmpty ? 'Web image $imageIndex' : description;
            buffer.writeln('![$alt]($imageUrl)');
            if (imageIndex >= 6) break;
          }
        }
        return buffer.toString().trim();
      } finally {
        client.close();
      }
    } catch (error) {
      return _serviceError(
        code: 'NETWORK_OR_PARSE_ERROR',
        retryable: true,
        details: error.toString(),
      );
    }
  }

  String _serviceError({
    required String code,
    required bool retryable,
    required String details,
    int? httpStatus,
  }) {
    return '[SERVICE ERROR]\n'
        'Service: Tavily\n'
        'Operation: web_search\n'
        'Error: $code\n'
        'HTTP status: ${httpStatus ?? 'unknown'}\n'
        'Retryable: $retryable\n'
        'Details: $details';
  }

  String _classifyStatus(int status, String body) {
    if (status == 401 || status == 403) return 'AUTHENTICATION_FAILED';
    if (status == 429) return 'QUOTA_EXCEEDED';
    if (status >= 500) return 'UPSTREAM_UNAVAILABLE';
    return 'REQUEST_FAILED';
  }

  String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {}
    return 'Tavily did not provide additional error details.';
  }
}
