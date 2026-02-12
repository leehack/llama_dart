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

/// Handler for Command R7B format.
///
/// Uses `<|START_ACTION|>` / `<|END_ACTION|>` for tool calls.
/// Tool call format: `<|START_ACTION|>{"tool_name": "fn", "parameters": {...}}<|END_ACTION|>`
///
/// Supports thinking with `<|START_THINKING|>` / `<|END_THINKING|>`.
class CommandR7BHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.commandR7B;

  @override
  List<String> get additionalStops => ['<|END_RESPONSE|>'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return [...additionalStops, if (hasTools) '<|END_ACTION|>'];
  }

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
          metadata['tokenizer.ggml.bos_token'] ?? '<|START_OF_TURN_TOKEN|>',
      'eos_token':
          metadata['tokenizer.ggml.eos_token'] ?? '<|END_OF_TURN_TOKEN|>',
    });

    // Handle enableThinking post-render logic
    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt, startTag: '<|START_THINKING|>')) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}<|END_THINKING|>\n';
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
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<|START_ACTION|>')]
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
      // The following line was provided in the instruction but is syntactically incorrect here.
      // systemParts.add('<|START_OF_TURN_TOKEN|><|SYSTEM_TOKEN|>${params.systemPrompt}<|END_OF_TURN_TOKEN|>');
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

    // Parse <|START_ACTION|>...<|END_ACTION|>
    final regex = RegExp(
      r'<\|START_ACTION\|>(.*?)<\|END_ACTION\|>',
      dotAll: true,
    );

    final matches = regex.allMatches(text);
    for (var i = 0; i < matches.length; i++) {
      final match = matches.elementAt(i);
      try {
        final json = jsonDecode(match.group(1)!) as Map<String, dynamic>;
        // Command R7B uses "tool_name" instead of "name"
        final name = json['tool_name'] as String?;
        final args = json['parameters'] ?? json['arguments'];
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
      } catch (_) {}
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

    // Build GBNF for Command R7B style tool calls
    final toolRules = <String>[];
    final toolChoices = <String>[];

    for (final tool in tools) {
      final ruleName = _sanitizeName(tool.name);
      toolChoices.add('$ruleName-call');

      final schema = tool.toJsonSchema();
      final argsRule = _jsonSchemaToGbnf(schema, '$ruleName-args');
      toolRules.add(argsRule);
      toolRules.add(
        '$ruleName-call ::= "{\\"tool_name\\": \\"${tool.name}\\", \\"parameters\\": " $ruleName-args "}"',
      );
    }

    final choiceRule = 'tool-choice ::= ${toolChoices.join(' | ')}';
    final root =
        'root ::= "<|START_ACTION|>" space tool-choice "<|END_ACTION|>" (space "<|START_ACTION|>" space tool-choice "<|END_ACTION|>" )*';

    return [root, choiceRule, ...toolRules, _commonGbnfRules()].join('\n');
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
    return '''
space ::= " "?
string ::= "\\"" ([^"\\\\] | "\\\\" .)* "\\""
number ::= "-"? ([0-9] | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [-+]? [0-9]+)?
boolean ::= "true" | "false"
null ::= "null"
value ::= string | number | boolean | null | arr | obj
arr ::= "[" space (value ("," space value)*)? space "]"
obj ::= "{" space (string ":" space value ("," space string ":" space value)*)? space "}"''';
  }
}
