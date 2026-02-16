import 'dart:convert';

import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/llama3_handler.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:test/test.dart';

void main() {
  final messages = [const LlamaChatMessage(role: 'user', content: 'hello')];

  test('Llama3Handler exposes chat format', () {
    final handler = Llama3Handler();
    expect(handler.format, isA<ChatFormat>());
  });

  test('returns content-only format when no tools are provided', () {
    final handler = Llama3Handler();
    final result = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: messages,
      metadata: const {},
      tools: const [],
    );

    expect(result.format, ChatFormat.contentOnly.index);
  });

  test('returns builtin-tools format when builtin tools are available', () {
    final handler = Llama3Handler();
    final result = handler.render(
      templateSource:
          '<|start_header_id|>ipython<|end_header_id|><|python_tag|>{{ messages[0]["content"] }}',
      messages: messages,
      metadata: const {},
      tools: [
        ToolDefinition(
          name: 'code_interpreter',
          description: 'Execute Python code',
          parameters: [ToolParam.string('code')],
          handler: _noopHandler,
        ),
      ],
    );

    expect(result.format, ChatFormat.llama3BuiltinTools.index);
    expect(result.grammar, isNull);
  });

  test('returns JSON tool grammar for non-builtin tools', () {
    final handler = Llama3Handler();
    final result = handler.render(
      templateSource:
          '<|start_header_id|>ipython<|end_header_id|>{{ messages[0]["content"] }}',
      messages: messages,
      metadata: const {},
      tools: [
        ToolDefinition(
          name: 'get_weather',
          description: 'Get weather information',
          parameters: [ToolParam.string('city', required: true)],
          handler: _noopHandler,
        ),
      ],
    );

    expect(result.format, ChatFormat.llama3.index);
    expect(result.grammar, isNotNull);
    expect(result.grammar, contains('name-kv'));
    expect(result.grammar, contains('parameters-kv'));
  });

  test('parses strict JSON tool payload and keeps loose text content', () {
    final handler = Llama3Handler();

    final strict = handler.parse(
      '[{"name":"get_weather","parameters":{"city":"Seoul"}}]',
    );
    expect(strict.toolCalls, hasLength(1));
    expect(strict.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(strict.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );

    final semicolon = handler.parse(
      '{"type":"function","function":"get_weather","parameters":{"city":"Seoul"}}; '
      '{"type":"function","function":"get_time","parameters":{"city":"Seoul"}}',
    );
    expect(semicolon.toolCalls, hasLength(1));
    expect(semicolon.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(semicolon.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
    expect(semicolon.content, isEmpty);

    final alias = handler.parse('weatherlookup');
    expect(alias.toolCalls, isEmpty);
    expect(alias.content, equals('weatherlookup'));
  });
}

Future<Object?> _noopHandler(_) async {
  return null;
}
