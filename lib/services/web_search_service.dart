import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_tool.dart';
import '../models/chat_tool_call.dart';
import 'chat_tool_executor.dart';
import 'secure_storage_service.dart';

/// Web search tool backed by Tavily Search API.
class WebSearchService implements ChatToolExecutor {
  WebSearchService({http.Client Function()? clientFactory}) : _clientFactory = clientFactory ?? http.Client.new;

  static const List<ChatTool> definitions = [
    ChatTool(
      name: 'web_search',
      description: 'Search the live web for current, factual, recent, or hard-to-know information. If the user asks to find/show an existing image rather than generate one, search for images too and return usable image URLs.',
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

      final apiKey = await _storage.getTavilySearchApiKey();
      if (apiKey == null || apiKey.trim().isEmpty) return 'Web search is not configured. Add a Tavily API key in Settings → Web search.';

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

        if (response.statusCode != 200) return 'Web search failed with HTTP ${response.statusCode}. ${_errorMessage(response.body)}';

        final body = jsonDecode(response.body);
        final results = body is Map ? body['results'] : null;
        final images = body is Map ? body['images'] : null;
        if (results is! List || results.isEmpty) return 'No web results found for "$query".';

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
            if (item is String && item.startsWith('http')) {
              imageIndex++;
              buffer.writeln('![Web image $imageIndex]($item)');
              if (imageIndex >= 6) break;
            } else if (item is Map) {
              final imageUrl = item['url'] ?? item['image_url'];
              if (imageUrl is String && imageUrl.startsWith('http')) {
                imageIndex++;
                final description = item['description'] is String ? _clean(item['description'] as String) : 'Web image $imageIndex';
                buffer.writeln('![$description]($imageUrl)');
                if (imageIndex >= 6) break;
              }
            }
          }
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
      if (decoded is Map && decoded['detail'] is String) return decoded['detail'] as String;
      if (decoded is Map && decoded['message'] is String) return decoded['message'] as String;
    } catch (_) {}
    return 'Please check the Tavily API key and try again.';
  }
}
