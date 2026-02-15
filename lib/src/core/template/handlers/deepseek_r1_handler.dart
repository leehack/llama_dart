import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';

/// Handler for DeepSeek R1 format.
///
/// Uses fullwidth Unicode delimiters for tool calls:
/// - `<｜tool▁calls▁begin｜>` / `<｜tool▁calls▁end｜>`
/// - `<｜tool▁call▁begin｜>` / `<｜tool▁call▁end｜>`
/// - `<｜tool▁sep｜>` separates function name from arguments
class DeepseekR1Handler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.deepseekR1;

  @override
  List<String> get additionalStops => ['<｜end▁of▁sentence｜>'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return [...additionalStops, if (hasTools) '<｜tool▁calls▁end｜>'];
  }

  @override
  List<String> get preservedTokens => const [
    '<think>',
    '</think>',
    '<｜tool▁sep｜>',
    '<｜tool▁calls▁begin｜>',
    '<｜tool▁call▁begin｜>',
    '<｜tool▁call▁end｜>',
    '<｜tool▁calls▁end｜>',
  ];

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    final template = Template(templateSource);
    var prompt = template.render({
      'messages': messages.map((m) => m.toJson()).toList(),
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'bos_token':
          metadata['tokenizer.ggml.bos_token'] ?? '<｜begin▁of▁sentence｜>',
      'eos_token':
          metadata['tokenizer.ggml.eos_token'] ?? '<｜end▁of▁sentence｜>',
    });

    // Handle enableThinking post-render logic
    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}</think>\n';
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final triggerPattern = thinkingForcedOpen
        ? r'[\s\S]*?(</think>\s*)(<｜tool▁calls▁begin｜>|<｜tool_calls_begin｜>|<｜tool calls begin｜>|<｜tool\\_calls\\_begin｜>|<｜tool▁calls｜>)[\s\S]*'
        : r'(?:<think>[\s\S]*?</think>\s*)?(<｜tool▁calls▁begin｜>|<｜tool_calls_begin｜>|<｜tool calls begin｜>|<｜tool\\_calls\\_begin｜>|<｜tool▁calls｜>)[\s\S]*';
    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: hasTools,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: hasTools ? preservedTokens : [],
      grammarTriggers: hasTools
          ? [GrammarTrigger(type: 3, value: triggerPattern)]
          : [],
    );
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final thinking = extractThinking(
      output,
      thinkingForcedOpen: thinkingForcedOpen,
    );
    final text = thinking.content;

    if (!parseToolCalls) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var contentText = text;

    final toolsBlockRegex = RegExp(
      r'(<｜tool▁calls▁begin｜>|<｜tool_calls_begin｜>|<｜tool calls begin｜>|<｜tool\\_calls\\_begin｜>|<｜tool▁calls｜>)([\s\S]*?)<｜tool▁calls▁end｜>',
      dotAll: true,
    );

    final blockMatch = toolsBlockRegex.firstMatch(text);
    if (blockMatch != null) {
      contentText = text.substring(0, blockMatch.start).trim();

      final singleCallRegex = RegExp(
        r'<｜tool▁call▁begin｜>(.*?)<｜tool▁call▁end｜>',
        dotAll: true,
      );

      final callMatches = singleCallRegex.allMatches(blockMatch.group(2)!);
      for (var i = 0; i < callMatches.length; i++) {
        final callContent = callMatches.elementAt(i).group(1)!.trim();

        final sepIdx = callContent.indexOf('<｜tool▁sep｜>');
        if (sepIdx != -1) {
          final name = callContent.substring(0, sepIdx).trim();
          final argsStr = callContent
              .substring(sepIdx + '<｜tool▁sep｜>'.length)
              .trim();

          try {
            final args = jsonDecode(argsStr);
            toolCalls.add(
              LlamaCompletionChunkToolCall(
                index: i,
                id: 'call_$i',
                type: 'function',
                function: LlamaCompletionChunkFunction(
                  name: name,
                  arguments: args is String ? args : jsonEncode(args),
                ),
              ),
            );
          } catch (_) {}
        }
      }
    } else {
      final legacyToolCallRegex = RegExp(
        r'<tool_call>(.*?)</tool_call>',
        dotAll: true,
      );
      final legacyMatches = legacyToolCallRegex
          .allMatches(text)
          .toList(growable: false);
      if (legacyMatches.isNotEmpty) {
        contentText = text.substring(0, legacyMatches.first.start).trim();
      }
      for (var i = 0; i < legacyMatches.length; i++) {
        final rawJson = legacyMatches[i].group(1)?.trim();
        if (rawJson == null || rawJson.isEmpty) {
          continue;
        }
        try {
          final decoded = jsonDecode(rawJson);
          if (decoded is! Map<String, dynamic>) {
            continue;
          }
          final name = decoded['name'];
          final arguments = decoded['arguments'];
          if (name is! String || name.isEmpty) {
            continue;
          }
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: i,
              id: 'call_$i',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: name,
                arguments: arguments is String
                    ? arguments
                    : jsonEncode(arguments),
              ),
            ),
          );
        } catch (_) {
          // Ignore malformed tool calls.
        }
      }
    }

    return ChatParseResult(
      content: contentText.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final toolNames = tools
        .map((tool) => _literal(tool.name))
        .toSet()
        .toList(growable: false);
    final toolNameRule = toolNames.join(' | ');

    return '''
root ::= ( "</think>" space )? tool-calls
tool-calls ::= ( "<｜tool▁calls▁begin｜>" | "<｜tool_calls_begin｜>" | "<｜tool calls begin｜>" | "<｜tool\\\\_calls\\\\_begin｜>" | "<｜tool▁calls｜>" ) space tool-call+ "<｜tool▁calls▁end｜>" space
tool-call ::= ( "<｜tool▁call▁begin｜>" )? tool-name "<｜tool▁sep｜>" obj "<｜tool▁call▁end｜>" space
tool-name ::= $toolNameRule
${_commonGbnfRules()}
''';
  }

  String _literal(String value) {
    final escaped = value
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return '"$escaped"';
  }

  String _commonGbnfRules() {
    return r'''
space ::= " "?
string ::= "\"" ([^"\\] | "\\\\" .)* "\""
number ::= "-"? ([0-9] | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [-+]? [0-9]+)?
boolean ::= "true" | "false"
null ::= "null"
value ::= string | number | boolean | null | arr | obj
arr ::= "[" space (value ("," space value)*)? space "]"
obj ::= "{" space (string ":" space value ("," space string ":" space value)*)? space "}"''';
  }
}
