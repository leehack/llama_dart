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
import '../tool_call_grammar_utils.dart';

/// Handler for Kimi K2 format.
///
/// Uses `<|tool_calls_section_begin|>` blocks with per-call
/// `<|tool_call_begin|>...<|tool_call_argument_begin|>{...}<|tool_call_end|>`.
class KimiK2Handler extends ChatTemplateHandler {
  static const String _scopeStart = '<|tool_calls_section_begin|>';
  static const String _scopeEnd = '<|tool_calls_section_end|>';
  static const String _callStart = '<|tool_call_begin|>';
  static const String _argStart = '<|tool_call_argument_begin|>';
  static const String _callEnd = '<|tool_call_end|>';

  @override
  ChatFormat get format => ChatFormat.kimiK2;

  @override
  List<String> get additionalStops => ['<|im_end|>', '<|im_middle|>'];

  @override
  List<String> get preservedTokens => const [
    '<think>',
    '</think>',
    '<|tool_calls_section_begin|>',
    '<|tool_call_begin|>',
    '<|tool_call_argument_begin|>',
    '<|tool_call_end|>',
    '<|tool_calls_section_end|>',
    '<|im_end|>',
    '<|im_system|>',
    '<|im_middle|>',
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
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
    });

    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}</think>';
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
          ? [const GrammarTrigger(type: 0, value: '$_scopeStart$_callStart')]
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
    if (!parseToolCalls) {
      final thinking = extractThinking(
        output,
        thinkingForcedOpen: thinkingForcedOpen,
      );
      return ChatParseResult(
        content: thinking.content.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    final contentWithoutToolCalls = _extractToolCalls(
      output,
      isPartial: isPartial,
      toolCalls: toolCalls,
    );

    final thinking = extractThinking(
      contentWithoutToolCalls,
      thinkingForcedOpen: thinkingForcedOpen,
    );

    return ChatParseResult(
      content: thinking.content.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  String _extractToolCalls(
    String input, {
    required bool isPartial,
    required List<LlamaCompletionChunkToolCall> toolCalls,
  }) {
    var remaining = input;

    while (true) {
      final scopeStartIdx = remaining.indexOf(_scopeStart);
      if (scopeStartIdx == -1) {
        break;
      }

      final afterScopeStart = scopeStartIdx + _scopeStart.length;
      final scopeEndIdx = remaining.indexOf(_scopeEnd, afterScopeStart);
      final scopeBody = scopeEndIdx == -1
          ? remaining.substring(afterScopeStart)
          : remaining.substring(afterScopeStart, scopeEndIdx);

      _parseScopeBody(scopeBody, isPartial: isPartial, toolCalls: toolCalls);

      final removeEnd = scopeEndIdx == -1
          ? remaining.length
          : scopeEndIdx + _scopeEnd.length;
      remaining = remaining.replaceRange(scopeStartIdx, removeEnd, '');

      if (scopeEndIdx == -1) {
        break;
      }
    }

    return remaining;
  }

  void _parseScopeBody(
    String scopeBody, {
    required bool isPartial,
    required List<LlamaCompletionChunkToolCall> toolCalls,
  }) {
    var cursor = 0;
    while (cursor < scopeBody.length) {
      final callStartIdx = scopeBody.indexOf(_callStart, cursor);
      if (callStartIdx == -1) {
        return;
      }

      final nameStart = callStartIdx + _callStart.length;
      final argStartIdx = scopeBody.indexOf(_argStart, nameStart);
      if (argStartIdx == -1) {
        return;
      }

      final rawName = scopeBody.substring(nameStart, argStartIdx).trim();
      final normalizedName = _normalizeToolName(rawName);

      final argsStart = argStartIdx + _argStart.length;
      final jsonExtraction = _extractJsonObject(scopeBody, argsStart);
      if (jsonExtraction == null) {
        if (isPartial && normalizedName != null) {
          final partialArguments = scopeBody.substring(argsStart).trim();
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: toolCalls.length,
              id: 'call_${toolCalls.length}',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: normalizedName,
                arguments: partialArguments,
              ),
            ),
          );
        }
        return;
      }

      final callEndIdx = scopeBody.indexOf(_callEnd, jsonExtraction.end);
      if (callEndIdx == -1) {
        if (isPartial && normalizedName != null) {
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: toolCalls.length,
              id: 'call_${toolCalls.length}',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: normalizedName,
                arguments: jsonExtraction.json,
              ),
            ),
          );
        }
        return;
      }

      if (normalizedName != null) {
        toolCalls.add(
          LlamaCompletionChunkToolCall(
            index: toolCalls.length,
            id: 'call_${toolCalls.length}',
            type: 'function',
            function: LlamaCompletionChunkFunction(
              name: normalizedName,
              arguments: _normalizeArguments(jsonExtraction.json),
            ),
          ),
        );
      }

      cursor = callEndIdx + _callEnd.length;
    }
  }

  String _normalizeArguments(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      return jsonEncode(decoded);
    } catch (_) {
      return rawJson;
    }
  }

  String? _normalizeToolName(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) {
      return null;
    }
    final kimiMatch = RegExp(r'^functions\.(.+):\d+$').firstMatch(name);
    if (kimiMatch == null) {
      return name;
    }
    final normalized = kimiMatch.group(1);
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  _JsonExtraction? _extractJsonObject(String input, int startIndex) {
    if (startIndex >= input.length || input[startIndex] != '{') {
      return null;
    }

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = startIndex; i < input.length; i++) {
      final codeUnit = input.codeUnitAt(i);

      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (codeUnit == 0x5C) {
          escaped = true;
          continue;
        }
        if (codeUnit == 0x22) {
          inString = false;
        }
        continue;
      }

      if (codeUnit == 0x22) {
        inString = true;
        continue;
      }

      if (codeUnit == 0x7B) {
        depth++;
      } else if (codeUnit == 0x7D) {
        depth--;
        if (depth == 0) {
          return _JsonExtraction(
            json: input.substring(startIndex, i + 1),
            end: i + 1,
          );
        }
      }
    }

    return null;
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final toolNames = tools
        .map((tool) => ToolCallGrammarUtils.literal(tool.name))
        .toSet()
        .toList(growable: false);
    final toolNameRule = toolNames.join(' | ');

    return '''
root ::= "<|tool_calls_section_begin|>" tool-call+ "<|tool_calls_section_end|>"
tool-call ::= "<|tool_call_begin|>" "functions." tool-name ":" [0-9]+ "<|tool_call_argument_begin|>" obj "<|tool_call_end|>"
tool-name ::= $toolNameRule
${_commonGbnfRules()}
''';
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

class _JsonExtraction {
  final String json;
  final int end;

  const _JsonExtraction({required this.json, required this.end});
}
