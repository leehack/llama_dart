import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../tool_call_fallback_parser.dart';
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';

/// Handler for Llama 3.x models.
///
/// Uses the ipython role for tool calls with `<|python_tag|>` trigger.
/// Tool call format: `{"name": "fn", "parameters": {...}}`
class Llama3Handler extends ChatTemplateHandler {
  static const Set<String> _builtinToolNames = {
    'wolfram_alpha',
    'web_search',
    'brave_search',
    'python',
    'code_interpreter',
  };

  @override
  ChatFormat get format => ChatFormat.llama3;

  @override
  List<String> get additionalStops => ['<|eot_id|>', '<|eom_id|>'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return hasTools ? additionalStops : const ['<|eot_id|>'];
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
    final prompt = template.render({
      'messages': messages.map((m) => m.toJson()).toList(),
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<|begin_of_text|>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_text|>',
      'date_string': DateTime.now().toIso8601String().split('T').first,
    });

    final hasTools = tools != null && tools.isNotEmpty;
    final hasBuiltinTools =
        hasTools && tools.any((tool) => _builtinToolNames.contains(tool.name));
    final supportsPythonTagBuiltins = templateSource.contains('<|python_tag|>');
    final resolvedFormat = hasTools
        ? (hasBuiltinTools && supportsPythonTagBuiltins
              ? ChatFormat.llama3BuiltinTools
              : format)
        : ChatFormat.contentOnly;

    final triggers = <GrammarTrigger>[];
    if (hasTools) {
      triggers.add(
        const GrammarTrigger(
          type: 3,
          value:
              r'(\{\s*(?:"type"\s*:\s*"function"\s*,\s*)?"name"\s*:\s*")[\s\S]*',
        ),
      );
      if (resolvedFormat == ChatFormat.llama3BuiltinTools) {
        triggers.add(const GrammarTrigger(type: 0, value: '<|python_tag|>'));
      }
    }

    final grammar = resolvedFormat == ChatFormat.llama3BuiltinTools
        ? null
        : buildGrammar(tools);

    return LlamaChatTemplateResult(
      prompt: prompt,
      format: resolvedFormat.index,
      grammar: grammar,
      grammarLazy: hasTools,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      grammarTriggers: triggers,
      preservedTokens: resolvedFormat == ChatFormat.llama3BuiltinTools
          ? const ['<|python_tag|>']
          : const [],
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
    final trimmed = text.trim();

    if (!parseToolCalls) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];

    // Built-in tool format used by Llama 3 templates with `<|python_tag|>`:
    // <|python_tag|>tool_name.call(arg=value, ...)
    final builtinTool = _tryParseBuiltinPythonTag(trimmed);
    if (builtinTool != null) {
      toolCalls.add(
        LlamaCompletionChunkToolCall(
          index: 0,
          id: 'call_0',
          type: 'function',
          function: builtinTool,
        ),
      );
      return ChatParseResult(
        content: '',
        reasoningContent: thinking.reasoning,
        toolCalls: toolCalls,
      );
    }

    // Llama 3 outputs JSON objects directly: {"name": "fn", "parameters": {...}}
    // May output multiple calls as a JSON array
    if (trimmed.startsWith('[')) {
      // JSON array of tool calls
      try {
        final list = jsonDecode(trimmed) as List<dynamic>;
        for (var i = 0; i < list.length; i++) {
          final call = list[i] as Map<String, dynamic>;
          final name = (call['name'] ?? call['function']) as String?;
          final params = call['parameters'] ?? call['arguments'];
          if (name != null) {
            final argsMap = normalizeFallbackToolArguments(
              _toArgumentsObject(params),
            );
            final normalizedName = normalizeFallbackToolName(
              name,
              arguments: argsMap,
            );
            toolCalls.add(
              LlamaCompletionChunkToolCall(
                index: i,
                id: 'call_$i',
                type: 'function',
                function: LlamaCompletionChunkFunction(
                  name: normalizedName,
                  arguments: jsonEncode(argsMap),
                ),
              ),
            );
          }
        }
      } catch (_) {}
    } else if (trimmed.startsWith('{') &&
        (trimmed.contains('"name"') || trimmed.contains('"function"'))) {
      // Single JSON tool call. If trailing non-JSON text exists, parse only the
      // leading object to mirror llama.cpp parser behavior.
      final json = _tryDecodeLeadingObject(trimmed);
      if (json != null) {
        final name = (json['name'] ?? json['function']) as String?;
        final params = json['parameters'] ?? json['arguments'];
        if (name != null) {
          final argsMap = normalizeFallbackToolArguments(
            _toArgumentsObject(params),
          );
          final normalizedName = normalizeFallbackToolName(
            name,
            arguments: argsMap,
          );
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: 0,
              id: 'call_0',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: normalizedName,
                arguments: jsonEncode(argsMap),
              ),
            ),
          );
        }
      }
    }

    return ChatParseResult(
      content: toolCalls.isNotEmpty ? '' : trimmed,
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  Map<String, dynamic> _toArgumentsObject(Object? raw) {
    if (raw == null) {
      return const <String, dynamic>{};
    }

    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    if (raw is String) {
      return decodeToolArgumentsObject(raw);
    }

    return const <String, dynamic>{};
  }

  Map<String, dynamic>? _tryDecodeLeadingObject(String input) {
    try {
      final decoded = jsonDecode(input);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      final object = _extractLeadingJsonObject(input);
      if (object == null) {
        return null;
      }
      try {
        final decoded = jsonDecode(object);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
      return null;
    }
  }

  String? _extractLeadingJsonObject(String input) {
    if (input.isEmpty || input.codeUnitAt(0) != 0x7B) {
      return null;
    }

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = 0; i < input.length; i++) {
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
      if (ch == 0x7B) {
        depth++;
        continue;
      }
      if (ch == 0x7D) {
        depth--;
        if (depth == 0) {
          return input.substring(0, i + 1);
        }
      }
    }

    return null;
  }

  LlamaCompletionChunkFunction? _tryParseBuiltinPythonTag(String output) {
    final match = RegExp(
      r'^<\|python_tag\|>\s*([A-Za-z_][A-Za-z0-9_]*)\.call\((.*)\)\s*$',
      dotAll: true,
    ).firstMatch(output);
    if (match == null) {
      return null;
    }

    final functionName = match.group(1);
    final argsText = match.group(2) ?? '';
    if (functionName == null || functionName.isEmpty) {
      return null;
    }

    final arguments = _parseBuiltinCallArguments(argsText);
    return LlamaCompletionChunkFunction(
      name: functionName,
      arguments: jsonEncode(arguments),
    );
  }

  Map<String, dynamic> _parseBuiltinCallArguments(String argsText) {
    final result = <String, dynamic>{};
    final tokens = _splitTopLevelCsv(argsText);
    for (final token in tokens) {
      final trimmed = token.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final eq = trimmed.indexOf('=');
      if (eq == -1) {
        continue;
      }

      final key = trimmed.substring(0, eq).trim();
      final rawValue = trimmed.substring(eq + 1).trim();
      if (key.isEmpty) {
        continue;
      }

      result[key] = _decodeLooseJsonValue(rawValue);
    }
    return result;
  }

  List<String> _splitTopLevelCsv(String input) {
    final items = <String>[];
    var start = 0;
    var inString = false;
    var escaped = false;
    var depthParen = 0;
    var depthBrace = 0;
    var depthBracket = 0;

    for (var i = 0; i < input.length; i++) {
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

      if (ch == 0x28) depthParen++;
      if (ch == 0x29) depthParen--;
      if (ch == 0x7B) depthBrace++;
      if (ch == 0x7D) depthBrace--;
      if (ch == 0x5B) depthBracket++;
      if (ch == 0x5D) depthBracket--;

      if (ch == 0x2C &&
          depthParen == 0 &&
          depthBrace == 0 &&
          depthBracket == 0) {
        items.add(input.substring(start, i));
        start = i + 1;
      }
    }

    if (start <= input.length) {
      items.add(input.substring(start));
    }
    return items;
  }

  Object? _decodeLooseJsonValue(String rawValue) {
    if (rawValue.isEmpty) {
      return '';
    }

    try {
      return jsonDecode(rawValue);
    } catch (_) {
      // Keep unparseable values as-is (e.g. bare identifiers).
      return rawValue;
    }
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return ToolCallGrammarUtils.buildWrappedObjectGrammar(
      tools: tools,
      prefix: '',
      suffix: '',
      nameKey: 'name',
      argumentsKey: 'parameters',
    );
  }
}
