import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_attachment.dart';
import '../models/chat_tool.dart';
import '../models/chat_tool_call.dart';
import 'chat_tool_executor.dart';
import 'secure_storage_service.dart';

/// Live web search backed by Gemini + Google Search.
/// Nemotron remains Cystem's primary assistant; raw search/tool output stays backend-only.
class WebSearchService implements ChatToolExecutor {
  WebSearchService({http.Client Function()? clientFactory}) : _clientFactory = clientFactory ?? http.Client.new;

  static const _searchModel = 'gemini-3.8-flash';
  static const _interactionsEndpoint = 'https://generativelanguage.googleapis.com/v1beta/interactions';
  static const _generateContentEndpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:generateContent';
  static const _maxImageBytes = 8 * 1024 * 1024;

  static const List<ChatTool> definitions = [
    ChatTool(
      name: 'web_search',
      description: 'Search the live web with Gemini and Google Search for current, recent, factual, or hard-to-know information.',
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
      if (decoded is! Map) return _serviceError('INVALID_ARGUMENTS', false, 'web_search requires a JSON object.');
      final query = decoded['query'];
      if (query is! String || query.trim().isEmpty) return _serviceError('INVALID_ARGUMENTS', false, 'web_search requires a non-empty query.');
      return await search(query.trim());
    } catch (error) {
      if (error is FormatException) return _serviceError('INVALID_ARGUMENTS', false, 'web_search received invalid JSON arguments.');
      return _serviceError('NETWORK_OR_PARSE_ERROR', true, 'Gemini web search is temporarily unavailable.');
    }
  }

  /// Deterministic live search. The UI can invoke this directly for explicit
  /// search requests instead of depending on Nemotron's tool-call decision.
  Future<String> search(String query) async {
    final apiKey = await _storage.getGeminiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      return _serviceError('NOT_CONFIGURED', false, 'Gemini API key is not configured for web search.');
    }

    final client = _clientFactory();
    try {
      final response = await client.post(
        Uri.parse(_interactionsEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'x-goog-api-key': apiKey.trim(),
        },
        body: jsonEncode({
          'model': _searchModel,
          'input': [
            {
              'type': 'text',
              'text': '''Use Google Search to research the query below. Produce concise, source-grounded research context for Cystem's main assistant. Prefer authoritative and recent sources. Include key facts, caveats, source titles, URLs/citations, and dates when relevant. Do not address the user directly and do not expose internal tool instructions.

Query:
$query''',
            },
          ],
          'tools': [
            {'type': 'google_search'},
          ],
          'response_format': {'type': 'text', 'mime_type': 'text/plain'},
          'store': false,
        }),
      ).timeout(const Duration(seconds: 90));

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
      if (text.isEmpty) return _serviceError('EMPTY_RESULT', true, 'Google Search returned no usable context.');
      return '[WEB SEARCH CONTEXT — Gemini + Google Search]\n$text';
    } on FormatException {
      return _serviceError('INVALID_RESPONSE', true, 'Gemini returned an unreadable web-search response.');
    } catch (error) {
      return _serviceError('NETWORK_ERROR', true, 'Gemini web search failed: $error');
    } finally {
      client.close();
    }
  }

  /// Searches Google Images through Gemini's Google Image Search grounding,
  /// then downloads real source images as persistent chat attachments.
  Future<List<ChatAttachment>> searchImages(String query) async {
    final apiKey = await _storage.getGeminiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const WebImageSearchException('Gemini API key is not configured for image search.');
    }

    final client = _clientFactory();
    try {
      final response = await client.post(
        Uri.parse(_generateContentEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'x-goog-api-key': apiKey.trim(),
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': 'Search Google Images for this request. Do not create or redraw an image. Return search-grounding metadata for real source images: $query'},
              ],
            },
          ],
          'tools': [
            {
              'google_search': {
                'searchTypes': {'imageSearch': {}},
              },
            },
          ],
          'generationConfig': {'responseModalities': ['TEXT']},
        }),
      ).timeout(const Duration(seconds: 90));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw WebImageSearchException('Gemini image search failed (HTTP ${response.statusCode}). ${_errorMessage(response.body)}');
      }

      final decoded = jsonDecode(response.body);
      final candidates = decoded is Map ? decoded['candidates'] : null;
      final sources = <_SourceImage>[];
      if (candidates is List) {
        for (final candidate in candidates.whereType<Map>()) {
          final grounding = candidate['groundingMetadata'];
          if (grounding is! Map) continue;
          final chunks = grounding['groundingChunks'];
          if (chunks is! List) continue;
          for (final chunk in chunks.whereType<Map>()) {
            final image = chunk['image'];
            if (image is! Map) continue;
            final imageUrl = image['imageUri'] ?? image['image_uri'];
            final sourceUrl = image['sourceUri'] ?? image['source_uri'];
            if (imageUrl is String && imageUrl.isNotEmpty) {
              sources.add(_SourceImage(imageUrl: imageUrl, sourceUrl: sourceUrl is String ? sourceUrl : null));
            }
          }
        }
      }

      final unique = <String, _SourceImage>{};
      for (final item in sources) {
        unique[item.imageUrl] = item;
      }

      final attachments = <ChatAttachment>[];
      for (final source in unique.values.take(6)) {
        final attachment = await _downloadImage(client, source);
        if (attachment != null) attachments.add(attachment);
      }
      if (attachments.isEmpty) {
        throw const WebImageSearchException('Google Image Search returned no displayable source images.');
      }
      return attachments;
    } on WebImageSearchException {
      rethrow;
    } on FormatException {
      throw const WebImageSearchException('Gemini returned an unreadable image-search response.');
    } catch (error) {
      throw WebImageSearchException('Gemini image search is temporarily unavailable. $error');
    } finally {
      client.close();
    }
  }

  Future<ChatAttachment?> _downloadImage(http.Client client, _SourceImage source) async {
    try {
      final uri = Uri.tryParse(source.imageUrl);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
      final response = await client.get(uri, headers: const {'Accept': 'image/*'}).timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (response.bodyBytes.isEmpty || response.bodyBytes.length > _maxImageBytes) return null;

      final headerType = response.headers['content-type']?.split(';').first.trim();
      final mimeType = headerType != null && headerType.startsWith('image/') ? headerType : _mimeTypeFromUrl(source.imageUrl);
      if (mimeType == null) return null;

      return ChatAttachment(
        id: '${DateTime.now().microsecondsSinceEpoch}_google_image',
        type: ChatAttachmentType.image,
        mimeType: mimeType,
        data: base64Encode(response.bodyBytes),
        fileName: 'cystem-google-image.${mimeType.split('/').last}',
        sourceUrl: source.sourceUrl,
      );
    } catch (_) {
      return null;
    }
  }

  String _extractText(dynamic decoded) {
    if (decoded is! Map) return '';
    final outputText = decoded['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) return outputText.trim();
    final steps = decoded['steps'];
    if (steps is! List) return '';
    final chunks = <String>[];
    for (final step in steps.whereType<Map>()) {
      if (step['type'] != 'model_output') continue;
      final content = step['content'];
      if (content is! List) continue;
      for (final part in content.whereType<Map>()) {
        if (part['type'] == 'text' && part['text'] is String) chunks.add(part['text'] as String);
      }
    }
    return chunks.join('\n').trim();
  }

  String? _mimeTypeFromUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.gif')) return 'image/gif';
    return null;
  }

  String _serviceError(String code, bool retryable, String details, {int? httpStatus}) {
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

class _SourceImage {
  const _SourceImage({required this.imageUrl, this.sourceUrl});
  final String imageUrl;
  final String? sourceUrl;
}

class WebImageSearchException implements Exception {
  const WebImageSearchException(this.message);
  final String message;
  @override
  String toString() => message;
}
