import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/models/chat_response_format.dart';

void main() {
  group('ChatResponseFormat', () {
    test('serializes json object mode', () {
      const format = ChatResponseFormat.jsonObject();
      expect(format.toApiJson(), {'type': 'json_object'});
    });

    test('serializes strict json schema mode', () {
      const format = ChatResponseFormat.jsonSchema(
        name: 'person',
        schema: {
          'type': 'object',
          'properties': {'name': {'type': 'string'}},
          'required': ['name'],
          'additionalProperties': false,
        },
      );

      expect(format.toApiJson()['type'], 'json_schema');
      final jsonSchema = (format.toApiJson()['json_schema'] as Map);
      expect(jsonSchema['name'], 'person');
      expect(jsonSchema['strict'], true);
    });
  });
}
