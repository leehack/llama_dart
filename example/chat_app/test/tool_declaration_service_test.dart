import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_chat_example/services/tool_declaration_service.dart';

void main() {
  const service = ToolDeclarationService();

  group('ToolDeclarationService', () {
    test('normalizes blank declarations to an empty array', () {
      expect(service.normalizeDeclarations('   '), '[]');
      expect(service.normalizeDeclarations('[{"name":"a"}]'), '[{"name":"a"}]');
    });

    test('parses OpenAI function-style declarations', () {
      final tools = service.parseDefinitions('''
[
  {
    "type": "function",
    "function": {
      "name": "getWeather",
      "description": "Get weather for a city",
      "parameters": {
        "type": "object",
        "properties": {
          "city": {"type": "string"}
        },
        "required": ["city"]
      }
    }
  }
]
''', handler: (ToolParams _) async => 'ok');

      expect(tools, hasLength(1));
      final tool = tools.first;
      expect(tool.name, 'getWeather');
      expect(tool.description, 'Get weather for a city');
      expect(tool.parameters, hasLength(1));
      expect(tool.parameters.first.name, 'city');
      expect(tool.parameters.first.required, isTrue);
      expect(tool.parameters.first.toJsonSchema()['type'], 'string');
    });

    test('returns readable parser errors', () {
      expect(
        () => service.parseDefinitions('not-json', handler: (_) async => null),
        throwsFormatException,
      );

      final error = service.formatError(
        const FormatException('bad declaration'),
        fallback: 'invalid',
      );
      expect(error, 'bad declaration');

      final fallback = service.formatError(
        Exception('boom'),
        fallback: 'invalid',
      );
      expect(fallback, 'invalid');
    });
  });
}
