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

/// Handler for Hermes 2 Pro / Qwen 2.5 / Qwen 3 format.
///
/// Uses `<tool_call>` / `</tool_call>` XML tags with JSON payloads.
/// Tool call format: `<tool_call>{"name": "fn", "arguments": {...}}</tool_call>`
class HermesHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.hermes;

  @override
  List<String> get additionalStops => ['<|im_end|>'];

  @override
  List<String> get preservedTokens => const ['<tool_call>', '</tool_call>'];

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
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
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
          ? [const GrammarTrigger(type: 0, value: '<tool_call>')]
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
    final toolCallRegex = RegExp(
      r'<tool_call>\s*(.*?)\s*</tool_call>',
      dotAll: true,
    );

    var contentText = text;
    final matches = toolCallRegex.allMatches(text);

    for (var i = 0; i < matches.length; i++) {
      final match = matches.elementAt(i);
      try {
        final jsonStr = match.group(1)!.trim();

        // Try parsing as-is first. Only attempt double-brace recovery
        // if the initial parse fails and the input looks like a Qwen quirk.
        // This avoids corrupting valid nested JSON like {"a": {"b": 1}}.
        Map<String, dynamic> json;
        try {
          json = jsonDecode(jsonStr) as Map<String, dynamic>;
        } on FormatException {
          if (!(jsonStr.startsWith('{{') && jsonStr.endsWith('}}'))) rethrow;

          try {
            json =
                jsonDecode(jsonStr.substring(1, jsonStr.length - 1))
                    as Map<String, dynamic>;
          } on FormatException {
            json =
                jsonDecode(_normalizeDoubleBraces(jsonStr))
                    as Map<String, dynamic>;
          }
        }
        final name = json['name'] as String?;
        final args = json['arguments'];
        if (name != null) {
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: i,
              id: 'call_$i',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: name,
                arguments: args is String ? args : jsonEncode(args ?? {}),
              ),
            ),
          );
        }
      } catch (_) {
        // Skip malformed tool calls
      }
      contentText = contentText.replaceAll(match.group(0)!, '');
    }

    return ChatParseResult(
      content: contentText.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) return null;

    // Build a GBNF grammar that constrains output to valid Hermes tool calls
    final toolRules = <String>[];
    final toolChoices = <String>[];

    for (final tool in tools) {
      final ruleName = _sanitizeName(tool.name);
      toolChoices.add('$ruleName-call');

      final schema = tool.toJsonSchema();
      final argsRule = _jsonSchemaToGbnf(schema, '$ruleName-args');
      toolRules.add(argsRule);
      toolRules.add(
        '$ruleName-call ::= "{\\"name\\": \\"${tool.name}\\", \\"arguments\\": " $ruleName-args "}"',
      );
    }

    final choiceRule = 'tool-choice ::= ${toolChoices.join(' | ')}';
    final root =
        'root ::= "<tool_call>" space tool-choice "</tool_call>" (space "<tool_call>" space tool-choice "</tool_call>")*';

    return [root, choiceRule, ...toolRules, _commonGbnfRules()].join('\n');
  }

  /// Collapses every `{{` → `{` and `}}` → `}` outside quoted strings.
  ///
  /// This is a last-resort normalizer for Qwen-style outputs where **all**
  /// braces are consistently doubled (e.g. `{{"name":"f","arguments":{{"k":"v"}}}}`).
  /// It is only safe when brace doubling is uniform — mixed payloads (outer
  /// wrapper doubled, inner objects single) must be handled by the outer-unwrap
  /// stage before reaching this path.
  ///
  /// As a safety gate, the function first verifies that every brace outside
  /// quoted strings appears as a doubled pair. If any single brace is found,
  /// the input is returned unchanged to avoid corrupting mixed-style payloads.
  String _normalizeDoubleBraces(String input) {
    if (!input.contains('{{') && !input.contains('}}')) return input;

    // Verify all braces outside strings are consistently doubled.
    var inString = false;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (c == '"' && (i == 0 || input[i - 1] != r'\')) {
        inString = !inString;
        continue;
      }
      if (!inString && (c == '{' || c == '}')) {
        if (i + 1 >= input.length || input[i + 1] != c) {
          // Single brace found — mixed style, bail out.
          return input;
        }
        i++; // skip the paired brace
      }
    }

    // All braces are doubled — collapse them.
    final buf = StringBuffer();
    inString = false;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];

      if (c == '"' && (i == 0 || input[i - 1] != r'\')) {
        inString = !inString;
        buf.write(c);
        continue;
      }

      if (!inString && i + 1 < input.length) {
        final next = input[i + 1];
        if (c == '{' && next == '{') {
          buf.write('{');
          i++;
          continue;
        }
        if (c == '}' && next == '}') {
          buf.write('}');
          i++;
          continue;
        }
      }

      buf.write(c);
    }
    return buf.toString();
  }

  String _sanitizeName(String name) =>
      name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-').toLowerCase();

  String _jsonSchemaToGbnf(Map<String, dynamic> schema, String ruleName) {
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};

    if (properties.isEmpty) {
      return '$ruleName ::= "{" space "}"';
    }

    final parts = <String>[];
    var first = true;
    for (final entry in properties.entries) {
      final sep = first ? '' : '", " space ';
      first = false;
      final propType = (entry.value as Map<String, dynamic>)['type'] as String?;
      final valueRule = _typeToGbnf(propType);
      parts.add('$sep"\\"${entry.key}\\": " space $valueRule');
    }

    return '$ruleName ::= "{" space ${parts.join(' ')} space "}"';
  }

  String _typeToGbnf(String? type) {
    switch (type) {
      case 'string':
        return 'string';
      case 'number':
      case 'integer':
        return 'number';
      case 'boolean':
        return 'boolean';
      case 'array':
        return 'arr';
      default:
        return 'value';
    }
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
