import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/command_r7b_handler.dart';
import 'package:test/test.dart';

void main() {
  test('CommandR7BHandler renders and parses command-r tool calls', () {
    final handler = CommandR7BHandler();
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}<|START_THINKING|>',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: tools,
      enableThinking: false,
    );

    expect(rendered.prompt, endsWith('<|END_THINKING|>\n'));
    expect(rendered.grammar, isNotNull);
    expect(rendered.grammarLazy, isTrue);
    expect(rendered.additionalStops, contains('<|END_ACTION|>'));
    expect(rendered.grammarTriggers, isNotEmpty);

    final parsed = handler.parse(
      '<|START_THINKING|>reasoning<|END_THINKING|>'
      'answer '
      '<|START_ACTION|>{"tool_name":"get_weather","parameters":{"city":"Seoul"}}<|END_ACTION|>',
    );

    expect(parsed.reasoningContent, contains('reasoning'));
    expect(parsed.content, equals('answer'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );

    final noToolParse = handler.parse(
      '<|START_ACTION|>{"tool_name":"noop","parameters":{}}<|END_ACTION|>',
      parseToolCalls: false,
    );
    expect(noToolParse.toolCalls, isEmpty);
    expect(noToolParse.content, contains('<|START_ACTION|>'));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
