import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_attachment.dart';
import 'secure_storage_service.dart';

/// Generates or edits images using Gemini's native image model. Returned text
/// is backend context; the image itself is surfaced by Cystem's chat UI.
class GeminiImageGenerationService {
  GeminiImageGenerationService({http.Client Function()? clientFactory}) : _clientFactory = clientFactory ?? http.Client.new;

  static const _model = 'gemini-3.1-flash-image';
  static const _endpoint = 'https://generativelanguage.googleapis.com/v1beta/interactions';

  final http.Client Function() _clientFactory;
  final SecureStorageService _storage = SecureStorageService();

  Future<GeminiImageGenerationResult> generateImage(String prompt) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) throw const GeminiImageGenerationException('Nemotron did not provide an image description.');
    return _run(input: [{'type': 'text', 'text': cleanPrompt}]);
  }

  Future<GeminiImageGenerationResult> editImage({required ChatAttachment source, required String instruction}) async {
    final cleanInstruction = instruction.trim();
    if (cleanInstruction.isEmpty) throw const GeminiImageGenerationException('Please describe how you want to edit the image.');
    return _run(input: [
      {'type': 'image', 'data': source.data, 'mime_type': source.mimeType},
      {
        'type': 'text',
        'text': 'Edit the supplied image according to this instruction. Keep everything else unchanged unless the instruction requires it. Return the edited image, not a textual description.\n\n$cleanInstruction',
      },
    ]);
  }

  Future<GeminiImageGenerationResult> _run({required List<Map<String, dynamic>> input}) async {
    final apiKey = await _storage.getGeminiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const GeminiImageGenerationException('Gemini image generation is not configured. Add a Gemini API key in Settings → Gemini.');
    }

    final client = _clientFactory();
    try {
      final response = await client.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'x-goog-api-key': apiKey.trim(),
        },
        body: jsonEncode({
          'model': _model,
          'input': input,
          'response_format': {
            'type': 'image',
            'mime_type': 'image/jpeg',
            'aspect_ratio': '1:1',
            'image_size': '1K',
          },
          'store': false,
        }),
      ).timeout(const Duration(minutes: 3));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GeminiImageGenerationException('Gemini image generation failed (HTTP ${response.statusCode}). ${_errorMessage(response.body)}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const GeminiImageGenerationException('Gemini returned an invalid image response.');

      String? text;
      ChatAttachment? image = _attachmentFromImageContent(decoded['output_image']);
      final steps = decoded['steps'];
      if (steps is List) {
        for (final rawStep in steps.whereType<Map>()) {
          if (rawStep['type'] != 'model_output') continue;
          final content = rawStep['content'];
          if (content is! List) continue;
          for (final rawPart in content.whereType<Map>()) {
            if (rawPart['type'] == 'text' && rawPart['text'] is String) {
              final value = (rawPart['text'] as String).trim();
              if (value.isNotEmpty) text = text == null ? value : '$text\n$value';
            } else if (rawPart['type'] == 'image' && image == null) {
              image = _attachmentFromImageContent(rawPart);
            }
          }
        }
      }

      if (image == null) {
        final status = decoded['status'];
        final errors = decoded['errors'];
        final detail = errors is List ? errors.whereType<Map>().map((item) => item['message']).whereType<String>().join(' ') : '';
        throw GeminiImageGenerationException('Gemini completed without image data${status is String ? ' (status: $status)' : ''}. ${detail.trim()}');
      }
      return GeminiImageGenerationResult(image: image, backendContext: text?.trim());
    } on GeminiImageGenerationException {
      rethrow;
    } on FormatException {
      throw const GeminiImageGenerationException('Gemini returned an unreadable image response.');
    } catch (error) {
      throw GeminiImageGenerationException('Could not reach Gemini image generation. $error');
    } finally {
      client.close();
    }
  }

  ChatAttachment? _attachmentFromImageContent(dynamic content) {
    if (content is! Map) return null;
    final data = content['data'];
    final mimeType = content['mime_type'] ?? content['mimeType'];
    if (data is! String || data.isEmpty || mimeType is! String || mimeType.isEmpty) return null;
    final extension = mimeType.split('/').last.split(';').first;
    return ChatAttachment(
      id: '${DateTime.now().microsecondsSinceEpoch}_gemini_image',
      type: ChatAttachmentType.image,
      mimeType: mimeType,
      data: data,
      fileName: 'cystem-gemini-generated.$extension',
    );
  }

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) return error['message'] as String;
        if (decoded['message'] is String) return decoded['message'] as String;
        final errors = decoded['errors'];
        if (errors is List) {
          final messages = errors.whereType<Map>().map((item) => item['message']).whereType<String>().toList();
          if (messages.isNotEmpty) return messages.join(' ');
        }
      }
    } catch (_) {}
    return 'Please check the Gemini API key, model availability, and quota.';
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
