import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import 'nvidia_api_service.dart';

/// Private attachment-understanding layer backed by Nemotron Nano Omni.
class NvidiaNanoOmniService {
  NvidiaNanoOmniService({NvidiaApiService? apiService})
      : _apiService = apiService ?? NvidiaApiService();

  final NvidiaApiService _apiService;

  Future<String> analyzeAttachments({
    required String userText,
    required List<ChatAttachment> attachments,
  }) async {
    if (attachments.isEmpty) return '';

    const instruction = '''
You are Cystem's private attachment-understanding layer.
Analyze the supplied attachment(s) for Nemotron Super. Do not answer the
user's question directly. Return only useful factual context.

Describe relevant objects, people, actions, spatial relationships, visible text,
UI elements, charts, diagrams, colors, clothing, errors, and uncertainty.
Transcribe readable text accurately. Do not invent details.
''';

    final message = ChatMessage(
      id: 'nano_${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.user,
      content: '$instruction\nUser request: $userText',
      createdAt: DateTime.now(),
      attachments: attachments,
    );

    final result = await _apiService.completeMessage(
      [message],
      model: NvidiaApiService.nanoOmniModel,
      temperature: 0.1,
    );
    return result.message.content.trim();
  }
}
