import 'package:test/test.dart';
import 'package:llamadart/src/common/json_schema_to_gbnf.dart';

void main() {
  group('JsonSchemaToGbnf', () {
    test('converts simple string schema', () {
      final schema = {'type': 'string'};
      final grammar = JsonSchemaToGbnf.convert(schema);
      expect(grammar, contains('root ::= root-str'));
      // Check that it defines a string rule
      expect(grammar, contains('-str ::='));
    });

    test('converts simple object schema', () {
      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer'},
        },
      };
      final grammar = JsonSchemaToGbnf.convert(schema);
      expect(grammar, contains('root ::= root-obj'));
      // Check that keys are present (ignoring complex escaping verification for now)
      expect(grammar, contains('name'));
      expect(grammar, contains('age'));
      expect(grammar, contains('root-name-str'));
      expect(grammar, contains('root-age-num'));
    });

    test('generates tool grammar', () {
      final tools = [
        {
          'name': 'get_weather',
          'description': 'Get weather',
          'parameters': {
            'type': 'object',
            'properties': {
              'location': {'type': 'string'},
            },
          },
        },
      ];
      final grammar = JsonSchemaToGbnf.generateToolGrammar(tools);
      expect(grammar, contains('root ::= get-weather-tool'));
      // Check for presence of JSON structure keywords
      expect(grammar, contains('type'));
      expect(grammar, contains('function'));
      expect(grammar, contains('name'));
      expect(grammar, contains('parameters'));
      expect(grammar, contains('get_weather'));
    });

    test('handles array without items', () {
      final schema = {'type': 'array'};
      final grammar = JsonSchemaToGbnf.convert(schema);
      expect(grammar, contains('root ::= "[]"'));
    });

    test('handles null type', () {
      final schema = {'type': 'null'};
      final grammar = JsonSchemaToGbnf.convert(schema);
      expect(grammar, contains('root ::= "null"'));
    });

    test('handles object without type but with properties', () {
      final schema = {
        'properties': {
          'foo': {'type': 'string'},
        },
      };
      final grammar = JsonSchemaToGbnf.convert(schema);
      expect(grammar, contains('root ::= root-obj'));
    });

    test('handles enum with special characters', () {
      final schema = {
        'type': 'string',
        'enum': ['a"b', 'c\\d'],
      };
      final grammar = JsonSchemaToGbnf.convert(schema);
      expect(grammar, contains(r'root-enum ::= "\"a\"b\"" | "\"c\\d\""'));
    });

    test('handles optional and required properties', () {
      final schema = {
        'type': 'object',
        'properties': {
          'req': {'type': 'string'},
          'opt': {'type': 'string'},
        },
        'required': ['req'],
      };
      final grammar = JsonSchemaToGbnf.convert(schema);
      expect(grammar, contains('req'));
      expect(grammar, contains(' ("," ws "\\"opt\\"" ":" ws root-opt-str)?'));
    });

    test('handles fallback for unknown type', () {
      final schema = {'type': 'something'};
      final grammar = JsonSchemaToGbnf.convert(schema);
      expect(grammar, contains('root ::= root-str'));
    });
  });
}
