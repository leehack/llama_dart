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
  String get thinkingStartTag => '<|START_THINKING|>';

  @override
  String get thinkingEndTag => '<|END_THINKING|>';

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
    if (isThinkingForcedOpen(prompt, startTag: thinkingStartTag)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}$thinkingEndTag\n';
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
      startTag: thinkingStartTag,
      endTag: thinkingEndTag,
    );
    final text = thinking.content;

    if (!parseToolCalls) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    const startAction = '<|START_ACTION|>';
    const endAction = '<|END_ACTION|>';
    const startResponse = '<|START_RESPONSE|>';
    const endResponse = '<|END_RESPONSE|>';

    final actionStart = text.indexOf(startAction);
    if (actionStart != -1) {
      final prelude = text.substring(0, actionStart);
      final afterStart = text.substring(actionStart + startAction.length);
      final jsonSlice = _extractLeadingJsonValue(afterStart, 0);
      if (jsonSlice == null || jsonSlice.value is! List) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      final toolCalls = <LlamaCompletionChunkToolCall>[];
      for (final item in jsonSlice.value as List<dynamic>) {
        if (item is! Map) {
          return ChatParseResult(
            content: text.trim(),
            reasoningContent: thinking.reasoning,
          );
        }
        final call = Map<String, dynamic>.from(item);
        final name = call['tool_name'] as String?;
        if (name == null || name.isEmpty) {
          return ChatParseResult(
            content: text.trim(),
            reasoningContent: thinking.reasoning,
          );
        }

        final argumentsValue = call.containsKey('parameters')
            ? call['parameters']
            : '';
        final arguments = argumentsValue is String
            ? argumentsValue
            : jsonEncode(argumentsValue);
        final toolId = call['tool_call_id']?.toString() ?? '';
        toolCalls.add(
          LlamaCompletionChunkToolCall(
            index: toolCalls.length,
            id: toolId.isEmpty ? null : toolId,
            type: 'function',
            function: LlamaCompletionChunkFunction(
              name: name,
              arguments: arguments,
            ),
          ),
        );
      }

      final actionEndOffset = jsonSlice.end;
      var endCursor = actionEndOffset;
      while (endCursor < afterStart.length &&
          afterStart.codeUnitAt(endCursor) <= 0x20) {
        endCursor++;
      }
      if (!afterStart.startsWith(endAction, endCursor)) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      final trailing = afterStart.substring(endCursor + endAction.length);
      if (trailing.isNotEmpty) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      return ChatParseResult(
        content: prelude.trim(),
        reasoningContent: thinking.reasoning,
        toolCalls: toolCalls,
      );
    }

    final responseStart = text.indexOf(startResponse);
    if (responseStart != -1) {
      final prelude = text.substring(0, responseStart);
      final responseBodyStart = responseStart + startResponse.length;
      final responseEnd = text.indexOf(endResponse, responseBodyStart);
      if (responseEnd == -1) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      final trailing = text.substring(responseEnd + endResponse.length);
      if (trailing.isNotEmpty) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      final responseBody = text.substring(responseBodyStart, responseEnd);
      return ChatParseResult(
        content: '$prelude$responseBody'.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    return ChatParseResult(
      content: text.trim(),
      reasoningContent: thinking.reasoning,
    );
  }

  _JsonValueSlice? _extractLeadingJsonValue(String input, int offset) {
    if (offset >= input.length) {
      return null;
    }

    int? end;
    final first = input.codeUnitAt(offset);
    if (first == 0x7B || first == 0x5B) {
      end = _findStructuredJsonEnd(input, offset);
    } else if (first == 0x22) {
      end = _findJsonStringEnd(input, offset);
    } else {
      final scalar = RegExp(
        r'(?:-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null)',
      ).matchAsPrefix(input, offset);
      if (scalar != null) {
        end = scalar.end;
      }
    }

    if (end == null || end <= offset) {
      return null;
    }

    try {
      return _JsonValueSlice(
        value: jsonDecode(input.substring(offset, end)),
        end: end,
      );
    } catch (_) {
      return null;
    }
  }

  int? _findStructuredJsonEnd(String input, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < input.length; i++) {
      final ch = input.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (ch == 0x5C) {
          escaped = true;
          continue;
        }
        if (ch == 0x22) {
          inString = false;
        }
        continue;
      }

      if (ch == 0x22) {
        inString = true;
        continue;
      }
      if (ch == 0x7B || ch == 0x5B) {
        depth++;
        continue;
      }
      if (ch == 0x7D || ch == 0x5D) {
        depth--;
        if (depth == 0) {
          return i + 1;
        }
      }
    }

    return null;
  }

  int? _findJsonStringEnd(String input, int start) {
    var escaped = false;
    for (var i = start + 1; i < input.length; i++) {
      final ch = input.codeUnitAt(i);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == 0x5C) {
        escaped = true;
        continue;
      }
      if (ch == 0x22) {
        return i + 1;
      }
    }
    return null;
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

final class _JsonValueSlice {
  final Object? value;
  final int end;

  const _JsonValueSlice({required this.value, required this.end});
}
