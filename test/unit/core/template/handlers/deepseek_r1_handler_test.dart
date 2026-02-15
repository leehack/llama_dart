import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/deepseek_r1_handler.dart';
import 'package:test/test.dart';

void main() {
  test('DeepseekR1Handler renders grammar and parses modern tool block', () {
    final handler = DeepseekR1Handler();
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}<think>',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: tools,
      enableThinking: false,
    );

    expect(handler.format, isA<ChatFormat>());
    expect(rendered.grammar, isNotNull);
    expect(rendered.grammar, contains(r'<｜tool\\_calls\\_begin｜>'));
    expect(rendered.prompt, endsWith('</think>\n'));
    expect(rendered.additionalStops, contains('<｜tool▁calls▁end｜>'));
    expect(rendered.grammarTriggers, hasLength(1));
    expect(
      rendered.grammarTriggers.first.value,
      contains(r'<｜tool\\_calls\\_begin｜>'),
    );

    final parsed = handler.parse(
      '<think>reasoning</think>answer '
      '<｜tool▁calls▁begin｜>'
      '<｜tool▁call▁begin｜>get_weather<｜tool▁sep｜>{"city":"Seoul"}<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>',
    );

    expect(parsed.reasoningContent, equals('reasoning'));
    expect(parsed.content, equals('answer'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
