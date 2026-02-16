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

  test('parses wrapped double-brace with nested args via outer unwrap', () {
    // Qwen-style outer-doubled braces wrapping normal nested JSON.
    // Stage 2 (outer unwrap) should handle this without corrupting inner objects.
    final handler = HermesHandler();
    final input =
        '<tool_call>{{"name":"f","arguments":{"user":{"id":1}}}}</tool_call>';
    final parsed = handler.parse(input);

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('f'));
    final args =
        jsonDecode(parsed.toolCalls.first.function!.arguments!)
            as Map<String, dynamic>;
    final user = args['user'] as Map<String, dynamic>;
    expect(user['id'], equals(1));
  });

  test('parses fully doubled braces via _normalizeDoubleBraces fallback', () {
    // All braces consistently doubled — stage 3 (full normalization) kicks in.
    final handler = HermesHandler();
    final input =
        '<tool_call>{{"name":"g","arguments":{{"location":"Seoul"}}}}</tool_call>';
    final parsed = handler.parse(input);

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('g'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('location', 'Seoul'),
    );
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
