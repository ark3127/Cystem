import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_attachment.dart';
import 'secure_storage_service.dart';

/// Uses Gemini as Cystem's vision layer. Nemotron remains the main text model.
/// The Interactions API is used for multimodal image understanding.
class GeminiVisionService {
  GeminiVisionService({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  static const _model = 'gemini-3.8-flash';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/interactions';

  final http.Client Function() _clientFactory;
  final SecureStorageService _storage = SecureStorageService();

  Future<String> analyzeImages(List<ChatAttachment> attachments) async {
    if (attachments.isEmpty) return '';

    final apiKey = await _storage.getGeminiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const GeminiVisionException(
        'Gemini vision is not configured. Add a Gemini API key in Settings → Vision.',
      );
    }

    final input = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': '''You are Cystem's private image-understanding layer. Another AI model, NVIDIA Nemotron, cannot see the user's image. Analyze the attached image(s) extremely thoroughly and return only visual context for Nemotron.

Include everything that could matter: scene and objects, people, actions, spatial relationships, UI elements, charts/diagrams, colors and visual states, visible text, error messages, and any other relevant details. Transcribe readable text and code as accurately as possible. If there is code, preserve it in a fenced code block. Clearly distinguish observations from uncertainty. Do not answer the user's question and do not invent details. Your output stays in the backend and is never shown as a separate chat message.''',
      },
      ...attachments.map(
        (attachment) => {
          'type': 'image',
          'data': attachment.data,
          'mime_type': attachment.mimeType,
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
              'model': _model,
              'input': input,
              'response_format': {
                'type': 'text',
                'mime_type': 'text/plain',
              },
              'store': false,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode != 200) {
        throw GeminiVisionException(
          'Gemini vision failed with HTTP ${response.statusCode}. ${_errorMessage(response.body)}',
        );
      }

      final decoded = jsonDecode(response.body);
      final text = _extractText(decoded);
      if (text.trim().isEmpty) {
        throw const GeminiVisionException(
          'Gemini returned an empty visual analysis.',
        );
      }
      return text.trim();
    } finally {
      client.close();
    }
  }

  String _extractText(dynamic decoded) {
    if (decoded is! Map) return '';
    final outputText = decoded['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) return outputText;

    final steps = decoded['steps'];
    if (steps is! List) return '';
    return steps
        .whereType<Map>()
        .where((step) => step['type'] == 'model_output')
        .expand(
          (step) =>
              step['content'] is List ? (step['content'] as List) : const [],
        )
        .whereType<Map>()
        .where((part) => part['type'] == 'text')
        .map((part) => part['text'])
        .whereType<String>()
        .join('\n');
  }

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
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
