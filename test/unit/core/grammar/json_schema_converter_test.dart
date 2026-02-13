import 'package:test/test.dart';
import 'package:llamadart/src/core/grammar/json_schema_converter.dart';

void main() {
  group('JsonSchemaConverter', () {
    test('converts simple string schema', () {
      final grammar = JsonSchemaConverter.convert({'type': 'string'});
      expect(grammar, contains('root ::='));
      expect(grammar, contains('char'));
    });

    test('converts simple boolean schema', () {
      final grammar = JsonSchemaConverter.convert({'type': 'boolean'});
      expect(grammar, contains('root ::='));
      expect(grammar, contains('"true"'));
      expect(grammar, contains('"false"'));
    });

    test('converts simple number schema', () {
      final grammar = JsonSchemaConverter.convert({'type': 'number'});
      expect(grammar, contains('root ::='));
      expect(grammar, contains('integral-part'));
      expect(grammar, contains('decimal-part'));
    });

    test('converts simple integer schema', () {
      final grammar = JsonSchemaConverter.convert({'type': 'integer'});
      expect(grammar, contains('root ::='));
      expect(grammar, contains('integral-part'));
    });

    test('converts null schema', () {
      final grammar = JsonSchemaConverter.convert({'type': 'null'});
      expect(grammar, contains('"null"'));
    });

    test('converts enum schema', () {
      final grammar = JsonSchemaConverter.convert({
        'type': 'string',
        'enum': ['red', 'green', 'blue'],
      });
      expect(grammar, contains('root ::='));
      // Enums use escaped quotes: \"red\"
      expect(grammar, contains(r'\"red\"'));
      expect(grammar, contains(r'\"green\"'));
      expect(grammar, contains(r'\"blue\"'));
    });

    test('converts const schema', () {
      final grammar = JsonSchemaConverter.convert({'const': 'hello'});
      expect(grammar, contains('root ::='));
      expect(grammar, contains(r'\"hello\"'));
    });

    test('converts simple object schema', () {
      final grammar = JsonSchemaConverter.convert({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer'},
        },
        'required': ['name'],
      });
      expect(grammar, contains('root ::='));
      // Property keys in GBNF use escaped quotes
      expect(grammar, contains('root-name-kv'));
      expect(grammar, contains('root-age-kv'));
      expect(grammar, contains(r'\"name\"'));
      expect(grammar, contains(r'\"age\"'));
    });

    test('converts object with all required properties', () {
      final grammar = JsonSchemaConverter.convert({
        'type': 'object',
        'properties': {
          'x': {'type': 'number'},
          'y': {'type': 'number'},
        },
        'required': ['x', 'y'],
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains(r'\"x\"'));
      expect(grammar, contains(r'\"y\"'));
    });

    test('converts array schema with items', () {
      final grammar = JsonSchemaConverter.convert({
        'type': 'array',
        'items': {'type': 'string'},
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains('"["'));
      expect(grammar, contains('"]"'));
    });

    test('converts array with minItems/maxItems', () {
      final grammar = JsonSchemaConverter.convert({
        'type': 'array',
        'items': {'type': 'integer'},
        'minItems': 1,
        'maxItems': 5,
      });
      expect(grammar, contains('root ::='));
    });

    test('converts oneOf schema', () {
      final grammar = JsonSchemaConverter.convert({
        'oneOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains('|'));
    });

    test('converts anyOf schema', () {
      final grammar = JsonSchemaConverter.convert({
        'anyOf': [
          {'type': 'boolean'},
          {'type': 'null'},
        ],
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains('|'));
    });

    test('converts nested object schema', () {
      final grammar = JsonSchemaConverter.convert({
        'type': 'object',
        'properties': {
          'location': {
            'type': 'object',
            'properties': {
              'lat': {'type': 'number'},
              'lon': {'type': 'number'},
            },
            'required': ['lat', 'lon'],
          },
        },
        'required': ['location'],
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains(r'\"location\"'));
      expect(grammar, contains(r'\"lat\"'));
      expect(grammar, contains(r'\"lon\"'));
    });

    test('converts empty schema to generic value', () {
      final grammar = JsonSchemaConverter.convert({});
      expect(grammar, contains('root ::='));
    });

    test('converts string with minLength/maxLength', () {
      final grammar = JsonSchemaConverter.convert({
        'type': 'string',
        'minLength': 3,
        'maxLength': 10,
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains('char'));
    });

    test(r'handles $ref resolution', () {
      final grammar = JsonSchemaConverter.convert({
        'type': 'object',
        'properties': {
          'address': {r'$ref': '#/definitions/Address'},
        },
        'required': ['address'],
        'definitions': {
          'Address': {
            'type': 'object',
            'properties': {
              'street': {'type': 'string'},
              'city': {'type': 'string'},
            },
            'required': ['street', 'city'],
          },
        },
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains(r'\"street\"'));
      expect(grammar, contains(r'\"city\"'));
    });

    test('converts array type union', () {
      final grammar = JsonSchemaConverter.convert({
        'type': ['string', 'null'],
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains('|'));
    });

    test('produces valid GBNF syntax', () {
      final grammar = JsonSchemaConverter.convert({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'count': {'type': 'integer'},
          'active': {'type': 'boolean'},
        },
        'required': ['name'],
      });

      // Every rule should have ::= separator
      for (final line in grammar.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        expect(
          trimmed,
          contains(' ::= '),
          reason: 'Rule should use ::= separator: $trimmed',
        );
      }
    });

    test('handles allOf composition', () {
      final grammar = JsonSchemaConverter.convert({
        'allOf': [
          {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
            },
          },
          {
            'type': 'object',
            'properties': {
              'age': {'type': 'integer'},
            },
          },
        ],
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains(r'\"name\"'));
      expect(grammar, contains(r'\"age\"'));
    });
  });
}
