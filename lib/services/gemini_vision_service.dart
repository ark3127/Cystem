import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_attachment.dart';
import 'secure_storage_service.dart';

/// Uses Gemini as Cystem's vision layer. Nemotron remains the main text model.
class GeminiVisionService {
  GeminiVisionService({http.Client Function()? clientFactory}) : _clientFactory = clientFactory ?? http.Client.new;

  static const _model = 'gemini-2.5-flash';
  static const _endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  final http.Client Function() _clientFactory;
  final SecureStorageService _storage = SecureStorageService();

  Future<String> analyzeImages(List<ChatAttachment> attachments) async {
    if (attachments.isEmpty) return '';

    final apiKey = await _storage.getGeminiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const GeminiVisionException('Gemini vision is not configured. Add a Gemini API key in Settings → Vision.');
    }

    final parts = <Map<String, dynamic>>[
      {
        'text': '''Analyze the attached image(s) extremely thoroughly for another AI model that cannot see images. Your output will be passed verbatim as visual context to NVIDIA Nemotron.

Describe everything that could matter: scene and objects, people, actions, spatial relationships, UI elements, charts/diagrams, colors and visual states, visible text, error messages, and any other relevant details. Transcribe readable text and code as accurately as possible. If there is code, preserve it in a fenced code block. Separate observations from uncertainty. Do not answer the user's question; only produce a detailed visual analysis. Do not omit details merely because they seem minor.''',
      },
      ...attachments.map(
        (attachment) => {
          'inline_data': {
            'mime_type': attachment.mimeType,
            'data': attachment.data,
          },
        },
      ),
    ];

    final client = _clientFactory();
    try {
      final response = await client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey.trim(),
            },
            body: jsonEncode({
              'contents': [
                {'parts': parts},
              ],
              'generationConfig': {
                'temperature': 0.2,
                'maxOutputTokens': 8192,
              },
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode != 200) {
        throw GeminiVisionException('Gemini vision failed with HTTP ${response.statusCode}. ${_errorMessage(response.body)}');
      }

      final decoded = jsonDecode(response.body);
      final candidates = decoded is Map ? decoded['candidates'] : null;
      if (candidates is! List || candidates.isEmpty) {
        throw const GeminiVisionException('Gemini returned no visual analysis.');
      }

      final content = candidates.first is Map ? candidates.first['content'] : null;
      final responseParts = content is Map ? content['parts'] : null;
      if (responseParts is! List) {
        throw const GeminiVisionException('Gemini returned an empty visual analysis.');
      }

      final text = responseParts
          .whereType<Map>()
          .map((part) => part['text'])
          .whereType<String>()
          .join();
      if (text.trim().isEmpty) {
        throw const GeminiVisionException('Gemini returned an empty visual analysis.');
      }
      return text.trim();
    } finally {
      client.close();
    }
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

class GeminiVisionException implements Exception {
  const GeminiVisionException(this.message);
  final String message;

  @override
  String toString() => message;
}
