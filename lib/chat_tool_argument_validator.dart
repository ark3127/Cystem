import 'dart:convert';

import '../models/chat_tool.dart';
import '../models/chat_tool_call.dart';

class ChatToolArgumentValidationException implements Exception {
  final String message;
  const ChatToolArgumentValidationException(this.message);

  @override
  String toString() => message;
}

/// Validates model-generated tool arguments against the registered JSON schema.
class ChatToolArgumentValidator {
  const ChatToolArgumentValidator();

  void validate(ChatTool tool, ChatToolCall call) {
    final decoded = jsonDecode(call.arguments);
    if (decoded is! Map) {
      throw const ChatToolArgumentValidationException(
        'Tool arguments must be a JSON object.',
      );
    }
    _validateObject(Map<String, dynamic>.from(decoded), tool.parameters);
  }

  void _validateObject(Map<String, dynamic> value, Map<String, dynamic> schema) {
    final properties = schema['properties'] is Map
        ? Map<String, dynamic>.from(schema['properties'] as Map)
        : <String, dynamic>{};
    final required = schema['required'] is List
        ? (schema['required'] as List).whereType<String>().toSet()
        : <String>{};

    for (final key in required) {
      if (!value.containsKey(key)) {
        throw ChatToolArgumentValidationException(
          'Missing required tool argument: $key.',
        );
      }
    }

    if (schema['additionalProperties'] == false) {
      for (final key in value.keys) {
        if (!properties.containsKey(key)) {
          throw ChatToolArgumentValidationException(
            'Unknown tool argument: $key.',
          );
        }
      }
    }

    for (final entry in value.entries) {
      final propertySchema = properties[entry.key];
      if (propertySchema is Map) {
        _validateValue(entry.value, Map<String, dynamic>.from(propertySchema));
      }
    }
  }

  void _validateValue(dynamic value, Map<String, dynamic> schema) {
    final type = schema['type'];
    if (type is String && !_matchesType(value, type)) {
      throw ChatToolArgumentValidationException(
        'Tool argument has the wrong type; expected $type.',
      );
    }

    final enumValues = schema['enum'];
    if (enumValues is List && !enumValues.any((item) => item == value)) {
      throw const ChatToolArgumentValidationException(
        'Tool argument is not one of the allowed values.',
      );
    }

    if (value is String) {
      final minLength = schema['minLength'];
      final maxLength = schema['maxLength'];
      if (minLength is num && value.length < minLength) {
        throw const ChatToolArgumentValidationException('Tool string argument is too short.');
      }
      if (maxLength is num && value.length > maxLength) {
        throw const ChatToolArgumentValidationException('Tool string argument is too long.');
      }
    }

    if (value is Map && type == 'object') {
      _validateObject(Map<String, dynamic>.from(value), schema);
    }

    if (value is List && type == 'array' && schema['items'] is Map) {
      for (final item in value) {
        _validateValue(item, Map<String, dynamic>.from(schema['items'] as Map));
      }
    }
  }

  bool _matchesType(dynamic value, String type) {
    switch (type) {
      case 'object':
        return value is Map;
      case 'array':
        return value is List;
      case 'string':
        return value is String;
      case 'integer':
        return value is int;
      case 'number':
        return value is num && value is! bool;
      case 'boolean':
        return value is bool;
      case 'null':
        return value == null;
      default:
        return true;
    }
  }
}
