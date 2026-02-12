import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/deepseek_v3_handler.dart';
import 'package:test/test.dart';

void main() {
  test('DeepseekV3Handler supports system prepend and tool_call parsing', () {
    final handler = DeepseekV3Handler();
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource:
          '{{ messages[0]["content"] }}|{{ messages[1]["content"] }}<think>',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.system, text: 'sys'),
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {'tokenizer.ggml.bos_token': '<BOS>'},
      tools: tools,
      enableThinking: false,
    );

    expect(rendered.prompt, contains('<BOS>sys|hello'));
    expect(rendered.prompt, endsWith('</think>\n'));
    expect(rendered.grammarTriggers, isNotEmpty);

    final parsed = handler.parse(
      '<think>reasoning</think>'
      'answer '
      '<tool_call>{"name":"get_weather","arguments":{"city":"Seoul"}}</tool_call>',
    );

    expect(parsed.reasoningContent, contains('reasoning'));
    expect(parsed.content, equals('answer'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );

    final noToolParse = handler.parse('plain', parseToolCalls: false);
    expect(noToolParse.content, equals('plain'));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
