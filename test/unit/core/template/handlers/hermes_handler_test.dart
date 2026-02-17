import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/hermes_handler.dart';
import 'package:test/test.dart';

void main() {
  test('HermesHandler renders valid grammar and parses tool calls', () {
    final handler = HermesHandler();
    final tools = [
      ToolDefinition(
        name: 'get_current_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('location', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
      ],
      metadata: const {},
      tools: tools,
    );

    expect(handler.format, isA<ChatFormat>());
    expect(rendered.grammar, isNotNull);
    expect(
      rendered.grammar,
      contains(r'string ::= "\"" ([^"\\] | "\\\\" .)* "\""'),
    );
    expect(rendered.grammar, isNot(contains(r'string ::= "\\\""')));

    final parsed = handler.parse(
      '<tool_call>{"name":"get_current_weather","arguments":{"location":"Seoul"}}</tool_call> tail',
    );
    expect(parsed.toolCalls, hasLength(1));
    expect(
      parsed.toolCalls.first.function?.name,
      equals('get_current_weather'),
    );
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('location', 'Seoul'),
    );
    expect(parsed.content, equals('tail'));
  });

  test('parses <function=name> JSON </function> tool call', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '<function=get_current_weather>{"location":"Seoul"}</function>',
    );

    expect(parsed.toolCalls, hasLength(1));
    expect(
      parsed.toolCalls.first.function?.name,
      equals('get_current_weather'),
    );
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('location', 'Seoul'),
    );
  });

  test('parses <function name="..."> JSON </function> tool call', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '<function name="get_current_weather">{"location":"Seoul"}</function>',
    );

    expect(parsed.toolCalls, hasLength(1));
    expect(
      parsed.toolCalls.first.function?.name,
      equals('get_current_weather'),
    );
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('location', 'Seoul'),
    );
  });

  test('parses fenced <tool_call> JSON block', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '```xml\n'
      '<tool_call>{"name":"bad","arguments":{"k":"v"}}</tool_call>\n'
      '```',
    );

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('bad'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('k', 'v'),
    );
    expect(parsed.content, isEmpty);
  });

  test('keeps non-tagged payload as content', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '{"type":"function","function":"get_weather","parameters":{"city":"Seoul"}}; '
      '{"type":"function","function":"get_time","parameters":{"city":"Seoul"}}',
    );

    expect(parsed.toolCalls, isEmpty);
    expect(
      parsed.content,
      '{"type":"function","function":"get_weather","parameters":{"city":"Seoul"}}; '
      '{"type":"function","function":"get_time","parameters":{"city":"Seoul"}}',
    );
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
