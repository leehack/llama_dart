import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/lfm2_handler.dart';
import 'package:test/test.dart';

void main() {
  test('Lfm2Handler renders wrapped grammar and parses both call syntaxes', () {
    final handler = Lfm2Handler();
    final tools = [
      ToolDefinition(
        name: 'search',
        description: 'Search',
        parameters: [ToolParam.string('query', required: true)],
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

    expect(handler.format, isA<ChatFormat>());
    expect(rendered.grammar, isNotNull);
    expect(rendered.grammar, contains('"<|tool_call_start|>"'));
    expect(rendered.grammarLazy, isTrue);
    expect(rendered.grammarTriggers, hasLength(1));

    final modern = handler.parse(
      '<|tool_call_start|>{"name":"search","arguments":{"query":"llama"}}<|tool_call_end|>',
    );
    expect(modern.toolCalls, hasLength(1));
    expect(modern.toolCalls.first.function?.name, equals('search'));
    expect(
      jsonDecode(modern.toolCalls.first.function!.arguments!),
      containsPair('query', 'llama'),
    );

    final legacy = handler.parse("[search(query='llama')] and text");
    expect(legacy.toolCalls, hasLength(1));
    expect(legacy.toolCalls.first.function?.name, equals('search'));
    expect(legacy.content, equals('and text'));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
