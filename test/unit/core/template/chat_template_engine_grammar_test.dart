import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ChatTemplateEngine grammar routing', () {
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city')],
        handler: _noopHandler,
      ),
    ];

    const messages = [
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
    ];

    test('applies generic tool grammar for generic templates', () {
      const template =
          '<|im_start|>user\n{{ messages[0]["content"] }}<|im_end|>\n<|im_start|>assistant\n';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: messages,
        metadata: const {},
        tools: tools,
      );

      expect(result.format, equals(ChatFormat.generic.index));
      expect(result.grammar, isNotNull);
    });

    test(
      'does not auto-apply generic grammar for format-specific handlers',
      () {
        const template = '>>>all\n{{ messages[0]["content"] }}';

        final result = ChatTemplateEngine.render(
          templateSource: template,
          messages: messages,
          metadata: const {},
          tools: tools,
        );

        expect(result.format, equals(ChatFormat.functionaryV32.index));
        expect(result.grammar, isNull);
      },
    );
  });
}

Future<Object?> _noopHandler(_) async {
  return 'ok';
}
