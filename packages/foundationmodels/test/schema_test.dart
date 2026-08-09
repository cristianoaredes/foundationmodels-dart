import 'package:foundationmodels/foundationmodels.dart';
import 'package:test/test.dart';

void main() {
  group('FmSchema — output mode (fail-fast)', () {
    test('serializes the supported subset exactly', () {
      final schema = FmSchema.object({
        'city': FmSchema.string(description: 'City name'),
        'tags': FmSchema.array(FmSchema.string(), minItems: 1, maxItems: 5),
        'score': FmSchema.number(),
        'count': FmSchema.integer(),
        'ok': FmSchema.boolean(),
      }, required: const ['city']);
      expect(schema.toJson(), {
        'type': 'object',
        'properties': {
          'city': {'type': 'string', 'description': 'City name'},
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'minItems': 1,
            'maxItems': 5,
          },
          'score': {'type': 'number'},
          'count': {'type': 'integer'},
          'ok': {'type': 'boolean'},
        },
        'required': ['city'],
        'additionalProperties': false,
      });
    });

    test('string enum serializes; empty enum throws empty_enum', () {
      expect(FmSchema.string(enumValues: ['a', 'b']).toJson(), {
        'type': 'string',
        'enum': ['a', 'b'],
      });
      expect(
        () => FmSchema.string(enumValues: const []).toJson(),
        throwsA(isA<UnsupportedSchemaTypeException>()
            .having((e) => e.schemaErrorCase, 'schemaErrorCase', 'empty_enum')),
      );
    });

    test('raw schema with unsupported keyword throws naming keyword + path',
        () {
      final schema = FmSchema.raw({
        'type': 'object',
        'properties': {
          'x': {'type': 'string', 'minLength': 3},
        },
      });
      expect(
        () => schema.toJson(),
        throwsA(isA<UnsupportedSchemaTypeException>()
            .having((e) => e.keyword, 'keyword', 'minLength')
            .having((e) => e.path, 'path', '/properties/x')),
      );
    });

    test('additionalProperties: true throws in output mode', () {
      final schema = FmSchema.raw({
        'type': 'object',
        'additionalProperties': true,
      });
      expect(
        () => schema.toJson(),
        throwsA(isA<UnsupportedSchemaTypeException>().having(
            (e) => e.schemaErrorCase, 'schemaErrorCase',
            'additional_properties_true')),
      );
    });

    test('external refs throw external_ref', () {
      expect(
        () => FmSchema.ref('https://example.com/schema.json'),
        throwsA(isA<UnsupportedSchemaTypeException>()
            .having((e) => e.schemaErrorCase, 'schemaErrorCase', 'external_ref')),
      );
      final raw = FmSchema.raw({'\$ref': 'other.json#/thing'});
      expect(() => raw.toJson(),
          throwsA(isA<UnsupportedSchemaTypeException>()));
    });

    test('internal refs with \$defs serialize', () {
      final schema = FmSchema.withDefs(
        {'address': FmSchema.object({'street': FmSchema.string()})},
        FmSchema.object({'home': FmSchema.ref('address')}),
      );
      final json = schema.toJson();
      expect(json['\$defs'], isA<Map>());
      expect(
        (json['properties']! as Map)['home'],
        {'\$ref': '#/\$defs/address'},
      );
    });
  });

  group('FmSchema — tool mode (sanitize)', () {
    test('strips unsupported keywords silently', () {
      final schema = FmSchema.raw({
        'type': 'object',
        'properties': {
          'x': {'type': 'string', 'minLength': 3, 'pattern': '^a'},
        },
      });
      expect(schema.toJson(mode: SchemaMode.tool), {
        'type': 'object',
        'properties': {
          'x': {'type': 'string'},
        },
      });
    });

    test('coerces additionalProperties to false', () {
      final schema = FmSchema.raw({
        'type': 'object',
        'additionalProperties': true,
      });
      expect(schema.toJson(mode: SchemaMode.tool)['additionalProperties'],
          isFalse);
    });
  });
}
