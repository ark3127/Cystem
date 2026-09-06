/// Structured-output configuration for Kimi K3.
///
/// NVIDIA's current K3 model documentation advertises structured output, while
/// the hosted NIM request reference does not yet enumerate response_format in
/// its parameter table. Keep this opt-in so normal chat/tool calls remain
/// unchanged until the hosted endpoint is verified for a particular schema.
class ChatResponseFormat {
  final String type;
  final String? name;
  final Map<String, dynamic>? schema;
  final bool? strict;

  const ChatResponseFormat._({
    required this.type,
    this.name,
    this.schema,
    this.strict,
  });

  const ChatResponseFormat.text()
      : this._(type: 'text');

  const ChatResponseFormat.jsonObject()
      : this._(type: 'json_object');

  const ChatResponseFormat.jsonSchema({
    required String name,
    required Map<String, dynamic> schema,
    bool strict = true,
  }) : this._(
          type: 'json_schema',
          name: name,
          schema: schema,
          strict: strict,
        );

  Map<String, dynamic> toApiJson() {
    switch (type) {
      case 'text':
        return {'type': 'text'};
      case 'json_object':
        return {'type': 'json_object'};
      case 'json_schema':
        return {
          'type': 'json_schema',
          'json_schema': {
            'name': name,
            'schema': schema,
            'strict': strict ?? true,
          },
        };
      default:
        throw ArgumentError('Unsupported response format: $type');
    }
  }
}
