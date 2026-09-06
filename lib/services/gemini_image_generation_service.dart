import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_attachment.dart';
import 'secure_storage_service.dart';

/// Generates images from Nemotron's text description using Gemini's native
/// image model. The returned text is kept as hidden backend context.
class GeminiImageGenerationService {
  GeminiImageGenerationService({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  static const _model = 'gemini-3.1-flash-image';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1/models/$_model:generateContent';

  final http.Client Function() _clientFactory;
  final SecureStorageService _storage = SecureStorageService();

  Future<GeminiImageGenerationResult> generateImage(String prompt) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) {
      throw const GeminiImageGenerationException('Nemotron did not provide an image description.');
    }

    final apiKey = await _storage.getGeminiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const GeminiImageGenerationException(
        'Gemini image generation is not configured. Add a Gemini API key in Settings → Vision.',
      );
    }

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
                {
                  'parts': [
                    {
                      'text': '''Create the requested image based directly on the following description from Cystem's main AI model, Nemotron. Preserve the intended subject, composition, style, text, and important details. Generate the image itself; do not merely describe how to make it.\n\n$cleanPrompt''',
                    },
                  ],
                },
              ],
              'generationConfig': {
                'responseModalities': ['TEXT', 'IMAGE'],
              },
            }),
          )
          .timeout(const Duration(minutes: 3));

      if (response.statusCode != 200) {
        throw GeminiImageGenerationException(
          'Gemini image generation failed with HTTP ${response.statusCode}. ${_errorMessage(response.body)}',
        );
      }

      final decoded = jsonDecode(response.body);
      final candidates = decoded is Map ? decoded['candidates'] : null;
      if (candidates is! List || candidates.isEmpty) {
        throw const GeminiImageGenerationException('Gemini returned no image generation result.');
      }

      final content = candidates.first is Map ? candidates.first['content'] : null;
      final parts = content is Map ? content['parts'] : null;
      if (parts is! List) {
        throw const GeminiImageGenerationException('Gemini returned an empty image generation result.');
      }

      String? text;
      ChatAttachment? image;
      for (final rawPart in parts.whereType<Map>()) {
        // Gemini 3 image models can emit interim images while thinking. Only
        // use the final non-thought image in the visible CYSTEM response.
        if (rawPart['thought'] == true) continue;

        final partText = rawPart['text'];
        if (partText is String && partText.trim().isNotEmpty) {
          text = text == null ? partText.trim() : '$text\n${partText.trim()}';
        }

        final inlineData = rawPart['inlineData'] ?? rawPart['inline_data'];
        if (inlineData is Map) {
          final data = inlineData['data'];
          final mimeType = inlineData['mimeType'] ?? inlineData['mime_type'];
          if (data is String && data.isNotEmpty && mimeType is String && mimeType.isNotEmpty) {
            image = ChatAttachment(
              id: '${DateTime.now().microsecondsSinceEpoch}_gemini_image',
              type: ChatAttachmentType.image,
              mimeType: mimeType,
              data: data,
              fileName: 'cystem-gemini-generated.png',
            );
          }
        }
      }

      if (image == null) {
        throw const GeminiImageGenerationException('Gemini did not return a generated image.');
      }

      return GeminiImageGenerationResult(
        image: image,
        backendContext: text?.trim(),
      );
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

class GeminiImageGenerationResult {
  const GeminiImageGenerationResult({required this.image, this.backendContext});

  final ChatAttachment image;
  final String? backendContext;
}

class GeminiImageGenerationException implements Exception {
  const GeminiImageGenerationException(this.message);
  final String message;

  @override
  String toString() => message;
}
