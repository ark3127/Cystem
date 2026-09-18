import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

import '../models/chat_tool.dart';
import '../models/chat_tool_call.dart';
import 'chat_tool_executor.dart';

/// Android-facing tools that use the OS intent handlers.
///
/// Calls and SMS intentionally open the system dialer/messaging composer;
/// Cystem does not silently place calls or send messages on the user's behalf.
class PhoneToolService implements ChatToolExecutor {
  static const List<ChatTool> definitions = [
    ChatTool(
      name: 'make_phone_call',
      description: 'Open the phone dialer with a phone number filled in. Do not claim the call was completed.',
      parameters: {
        'type': 'object',
        'properties': {
          'phone_number': {'type': 'string', 'description': 'Phone number to dial.'},
        },
        'required': ['phone_number'],
        'additionalProperties': false,
      },
    ),
    ChatTool(
      name: 'compose_sms',
      description: 'Open the system SMS composer with a recipient and optional message. Do not claim the SMS was sent.',
      parameters: {
        'type': 'object',
        'properties': {
          'phone_number': {'type': 'string', 'description': 'SMS recipient phone number.'},
          'message': {'type': 'string', 'description': 'Message body to prefill.'},
        },
        'required': ['phone_number'],
        'additionalProperties': false,
      },
    ),
    ChatTool(
      name: 'open_url',
      description: 'Open a normal HTTP or HTTPS URL in the device browser.',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'HTTP or HTTPS URL.'},
        },
        'required': ['url'],
        'additionalProperties': false,
      },
    ),
    ChatTool(
      name: 'open_maps',
      description: 'Open a place or address in the device map handler.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Place, address, or business to search for.'},
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    ),
  ];

  @override
  Future<String> execute(ChatToolCall call) async {
    try {
      final decoded = jsonDecode(call.arguments);
      if (decoded is! Map) return 'Invalid arguments for ${call.name}.';
      final args = Map<String, dynamic>.from(decoded);

      switch (call.name) {
        case 'make_phone_call':
          return await _launchCall(args);
        case 'compose_sms':
          return await _composeSms(args);
        case 'open_url':
          return await _openUrl(args);
        case 'open_maps':
          return await _openMaps(args);
        default:
          return 'Unknown phone tool: ${call.name}';
      }
    } on FormatException {
      return 'The tool arguments were not valid JSON.';
    } catch (error) {
      return 'Phone tool failed: $error';
    }
  }

  Future<String> _launchCall(Map<String, dynamic> args) async {
    final number = _requiredString(args, 'phone_number');
    final launched = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!launched) return 'Could not open the phone dialer.';
    return 'Opened the phone dialer for $number. The user must confirm/place the call.';
  }

  Future<String> _composeSms(Map<String, dynamic> args) async {
    final number = _requiredString(args, 'phone_number');
    final message = args['message'] is String ? args['message'] as String : '';
    final query = message.isEmpty ? null : 'body=${Uri.encodeComponent(message)}';
    final uri = Uri.parse('sms:${Uri.encodeComponent(number)}${query == null ? '' : '?$query'}');
    final launched = await launchUrl(uri);
    if (!launched) return 'Could not open the SMS composer.';
    return 'Opened the SMS composer for $number. The user must review and send the message.';
  }

  Future<String> _openUrl(Map<String, dynamic> args) async {
    final rawUrl = _requiredString(args, 'url');
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'Only HTTP and HTTPS URLs are allowed.';
    }
    final launched = await launchUrl(uri);
    if (!launched) return 'Could not open the URL.';
    return 'Opened $rawUrl in the device browser.';
  }

  Future<String> _openMaps(Map<String, dynamic> args) async {
    final query = _requiredString(args, 'query');
    final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': query});
    final launched = await launchUrl(uri);
    if (!launched) return 'Could not open maps.';
    return 'Opened maps for "$query".';
  }

  String _requiredString(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is! String || value.trim().isEmpty) {
      throw ArgumentError('Missing required argument: $key');
    }
    return value.trim();
  }
}
