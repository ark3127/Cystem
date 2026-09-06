import 'dart:convert';

import '../models/chat_completion_result.dart';
import '../models/chat_message.dart';
import '../models/chat_response_format.dart';
import 'nvidia_api_service.dart';

/// Runs a Kimi K3 completion and turns its final content into typed JSON.
///
/// JSON parsing is followed by lightweight JSON-Schema validation for the
/// schema features useful to Cystem: object/array/scalar types, required
/// properties, additionalProperties=false, enum, and anyOf.
class StructuredOutputService {
  final NvidiaApiService _apiService;

  const StructuredOutputService(this._apiService);

  Future<Map<String, dynamic>> completeObject(
    List<ChatMessage> messages, {
    required String name,
    required Map<String, dynamic> schema,
    bool strict = true,
    String? reasoningEffort,
    double? temperature,
    int? maxTokens,
    int? seed,
    bool clearSeed = false,
  }) async {
    final result = await _apiService.completeMessage(
      messages,
      reasoningEffort: reasoningEffort,
      temperature: temperature,
      maxTokens: maxTokens,
      seed: seed,
      clearSeed: clearSeed,
      responseFormat: ChatResponseFormat.jsonSchema(
        name: name,
        schema: schema,
        strict: strict,
      ),
    );

    return parseObject(result, schema: schema);
  }

  Map<String, dynamic> parseObject(
    ChatCompletionResult result, {
    required Map<String, dynamic> schema,
  }) {
    final content = result.message.content.trim();
    if (content.isEmpty) {
      throw const NvidiaApiException(
        'Kimi returned an empty structured-output response.',
      );
    }

    if (result.finishReason == 'length') {
      throw const NvidiaApiException(
        'Kimi stopped before the structured JSON was complete.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      throw const NvidiaApiException(
        'Kimi returned invalid JSON for the requested structured output.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const NvidiaApiException(
        'Kimi structured output must be a JSON object.',
      );
    }

    final error = _validate(decoded, schema, r'$');
    if (error != null) {
      throw NvidiaApiException('Structured output failed schema validation: $error');
    }

    return decoded;
  }

  String? _validate(dynamic value, Map<String, dynamic> schema, String path) {
    final anyOf = schema['anyOf'];
    if (anyOf is List && anyOf.isNotEmpty) {
      for (final candidate in anyOf) {
        if (candidate is Map<String, dynamic> &&
            _validate(value, candidate, path) == null) {
          return null;
        }
      }
      return '$path does not match any allowed schema variant';
    }

    final enumValues = schema['enum'];
    if (enumValues is List &&
        !enumValues.any((candidate) => _deepEqual(candidate, value))) {
      return '$path is not one of the allowed enum values';
    }

    final type = schema['type'];
    if (type is String && !_matchesType(value, type)) {
      return '$path expected $type but received ${_typeName(value)}';
    }

    if (type == 'object' && value is Map) {
      final required = schema['required'];
      if (required is List) {
        for (final key in required) {
          if (key is String && !value.containsKey(key)) {
            return '$path.$key is required';
          }
        }
      }

      final properties = schema['properties'];
      if (properties is Map) {
        for (final entry in value.entries) {
          final propertySchema = properties[entry.key];
          if (propertySchema is Map<String, dynamic>) {
            final error = _validate(
              entry.value,
              propertySchema,
              '$path.${entry.key}',
            );
            if (error != null) return error;
          } else if (schema['additionalProperties'] == false) {
            return '$path.${entry.key} is not allowed';
          }
        }
      } else if (schema['additionalProperties'] == false && value.isNotEmpty) {
        return '$path contains properties but the schema defines none';
      }
    }

    if (type == 'array' && value is List) {
      final items = schema['items'];
      if (items is Map<String, dynamic>) {
        for (var index = 0; index < value.length; index++) {
          final error = _validate(value[index], items, '$path[$index]');
          if (error != null) return error;
        }
      }
    }

    return null;
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
        return value is num;
      case 'boolean':
        return value is bool;
      case 'null':
        return value == null;
      default:
        return true;
    }
  }

  String _typeName(dynamic value) {
    if (value == null) return 'null';
    if (value is bool) return 'boolean';
    if (value is int) return 'integer';
    if (value is num) return 'number';
    if (value is String) return 'string';
    if (value is List) return 'array';
    if (value is Map) return 'object';
    return value.runtimeType.toString();
  }

  bool _deepEqual(dynamic left, dynamic right) {
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_deepEqual(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_deepEqual(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }
}
