import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/qwen3_coder_xml_handler.dart';
import 'package:test/test.dart';

void main() {
  test('Qwen3CoderXmlHandler parses qwen XML tool calls', () {
    final handler = Qwen3CoderXmlHandler();
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: tools,
    );
    expect(rendered.grammarTriggers, isNotEmpty);
    expect(rendered.additionalStops, contains('<|im_end|>'));

    final parsed = handler.parse(
      '<tool_call>\n'
      '<function=get_weather>\n'
      '<parameter=city>\n"Seoul"\n</parameter>\n'
      '</function>\n'
      '</tool_call>',
    );
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );

    final noTool = handler.parse('plain', parseToolCalls: false);
    expect(noTool.content, equals('plain'));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
