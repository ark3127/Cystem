import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_tool.dart';
import '../models/chat_tool_call.dart';
import 'chat_tool_executor.dart';
import 'secure_storage_service.dart';

/// Web search tool backed by Brave Search API.
class WebSearchService implements ChatToolExecutor {
  WebSearchService({http.Client Function()? clientFactory}) : _clientFactory = clientFactory ?? http.Client.new;

  static const List<ChatTool> definitions = [
    ChatTool(
      name: 'web_search',
      description: 'Search the live web for current, factual, recent, or hard-to-know information. Use this when the answer may have changed or when the user explicitly asks you to search the web. Return relevant sources and cite their URLs.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'A concise web search query.'},
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
      if (decoded is! Map) return 'Invalid arguments for web_search.';
      final query = decoded['query'];
      if (query is! String || query.trim().isEmpty) return 'web_search requires a non-empty query.';

      final apiKey = await _storage.getBraveSearchApiKey();
      if (apiKey == null || apiKey.trim().isEmpty) {
        return 'Web search is not configured. Add a Brave Search API key in Settings → Web search.';
      }

      final client = _clientFactory();
      try {
        final uri = Uri.https('api.search.brave.com', '/res/v1/web/search', {
          'q': query.trim(),
          'count': '6',
          'safesearch': 'moderate',
          'text_decorations': 'false',
        });
        final response = await client.get(uri, headers: {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
          'X-Subscription-Token': apiKey.trim(),
        }).timeout(const Duration(seconds: 20));

        if (response.statusCode != 200) {
          return 'Web search failed with HTTP ${response.statusCode}. ${_errorMessage(response.body)}';
        }

        final body = jsonDecode(response.body);
        final web = body is Map ? body['web'] : null;
        final results = web is Map ? web['results'] : null;
        if (results is! List || results.isEmpty) return 'No web results found for "$query".';

        final buffer = StringBuffer('Search results for "$query":\n\n');
        var index = 0;
        for (final item in results) {
          if (item is! Map) continue;
          final title = item['title'];
          final url = item['url'];
          final description = item['description'];
          if (title is! String || url is! String) continue;
          index++;
          final snippet = description is String ? _clean(description) : '';
          buffer.writeln('[$index] [$title]($url)');
          if (snippet.isNotEmpty) buffer.writeln(snippet);
          buffer.writeln();
          if (index >= 6) break;
        }
        return buffer.toString().trim();
      } finally {
        client.close();
      }
    } catch (error) {
      return 'Web search failed: $error';
    }
  }

  String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) return decoded['message'] as String;
    } catch (_) {}
    return 'Please check the web search API key and try again.';
  }
}
