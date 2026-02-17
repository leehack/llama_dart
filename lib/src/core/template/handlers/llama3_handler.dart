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

/// Handler for Llama 3.x models.
///
/// Uses the ipython role for tool calls with `<|python_tag|>` trigger.
/// Tool call format: `{"name": "fn", "parameters": {...}}`
class Llama3Handler extends ChatTemplateHandler {
  static final RegExp _llama31FunctionPrefix = RegExp(
    r'^\s*\{\s*(?:"type"\s*:\s*"function"\s*,\s*)?"name"\s*:\s*"([^"]+)"\s*,\s*"parameters"\s*:\s*',
    dotAll: true,
  );

  static final RegExp _llama31CloseRegex = RegExp(r'\}\s*', dotAll: true);

  static final RegExp _builtinFunctionPrefix = RegExp(
    r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*call\(',
    dotAll: true,
  );

  static final RegExp _builtinArgName = RegExp(
    r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*',
    dotAll: true,
  );

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
    final trimmed = thinking.content.trim();

    if (!parseToolCalls) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final builtinResult = _tryParseBuiltinPythonTag(trimmed);
    if (builtinResult.foundTag) {
      if (builtinResult.function == null ||
          (isPartial && !builtinResult.valid)) {
        return ChatParseResult(
          content: trimmed,
          reasoningContent: thinking.reasoning,
        );
      }

      return ChatParseResult(
        content: builtinResult.content,
        reasoningContent: thinking.reasoning,
        toolCalls: [
          LlamaCompletionChunkToolCall(
            index: 0,
            id: 'call_0',
            type: 'function',
            function: builtinResult.function,
          ),
        ],
      );
    }

    final prefix = _llama31FunctionPrefix.firstMatch(trimmed);
    if (prefix == null) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final functionName = prefix.group(1);
    if (functionName == null || functionName.isEmpty) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final argsValue = _extractLeadingJsonValue(trimmed, prefix.end);
    if (argsValue == null) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final close = _llama31CloseRegex.matchAsPrefix(trimmed, argsValue.end);
    if (close == null) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    var contentStart = close.end;
    while (contentStart < trimmed.length &&
        trimmed.codeUnitAt(contentStart) <= 0x20) {
      contentStart++;
    }

    return ChatParseResult(
      content: trimmed.substring(contentStart),
      reasoningContent: thinking.reasoning,
      toolCalls: [
        LlamaCompletionChunkToolCall(
          index: 0,
          id: 'call_0',
          type: 'function',
          function: LlamaCompletionChunkFunction(
            name: functionName,
            arguments: jsonEncode(argsValue.value),
          ),
        ),
      ],
    );
  }

  _BuiltinParseResult _tryParseBuiltinPythonTag(String output) {
    final pythonTagIndex = output.indexOf('<|python_tag|>');
    if (pythonTagIndex < 0) {
      return const _BuiltinParseResult(foundTag: false, valid: true);
    }

    final contentPrefix = output.substring(0, pythonTagIndex);
    final afterTag = output.substring(pythonTagIndex + '<|python_tag|>'.length);
    final functionPrefix = _builtinFunctionPrefix.matchAsPrefix(afterTag);
    if (functionPrefix == null) {
      return const _BuiltinParseResult(foundTag: true, valid: false);
    }

    final functionName = functionPrefix.group(1);
    if (functionName == null || functionName.isEmpty) {
      return const _BuiltinParseResult(foundTag: true, valid: false);
    }

    var cursor = functionPrefix.end;
    final arguments = <String, dynamic>{};

    while (true) {
      final argMatch = _builtinArgName.matchAsPrefix(afterTag, cursor);
      if (argMatch == null) {
        break;
      }

      final argName = argMatch.group(1);
      if (argName == null || argName.isEmpty) {
        return const _BuiltinParseResult(foundTag: true, valid: false);
      }

      cursor = argMatch.end;
      final value = _extractLeadingJsonValue(afterTag, cursor);
      if (value == null) {
        return const _BuiltinParseResult(foundTag: true, valid: false);
      }
      arguments[argName] = value.value;
      cursor = value.end;

      while (cursor < afterTag.length && afterTag.codeUnitAt(cursor) <= 0x20) {
        cursor++;
      }

      if (cursor < afterTag.length && afterTag.codeUnitAt(cursor) == 0x2C) {
        cursor++;
      } else {
        break;
      }
    }

    while (cursor < afterTag.length && afterTag.codeUnitAt(cursor) <= 0x20) {
      cursor++;
    }

    if (cursor >= afterTag.length || afterTag.codeUnitAt(cursor) != 0x29) {
      return const _BuiltinParseResult(foundTag: true, valid: false);
    }

    cursor++;
    while (cursor < afterTag.length && afterTag.codeUnitAt(cursor) <= 0x20) {
      cursor++;
    }

    if (cursor != afterTag.length) {
      return const _BuiltinParseResult(foundTag: true, valid: false);
    }

    return _BuiltinParseResult(
      foundTag: true,
      valid: true,
      content: contentPrefix,
      function: LlamaCompletionChunkFunction(
        name: functionName,
        arguments: jsonEncode(arguments),
      ),
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

    final raw = input.substring(offset, end);
    try {
      return _JsonValueSlice(value: jsonDecode(raw), end: end);
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
    return ToolCallGrammarUtils.buildWrappedObjectGrammar(
      tools: tools,
      prefix: '',
      suffix: '',
      nameKey: 'name',
      argumentsKey: 'parameters',
    );
  }
}

final class _BuiltinParseResult {
  final bool foundTag;
  final bool valid;
  final String content;
  final LlamaCompletionChunkFunction? function;

  const _BuiltinParseResult({
    required this.foundTag,
    required this.valid,
    this.content = '',
    this.function,
  });
}

final class _JsonValueSlice {
  final Object? value;
  final int end;

  const _JsonValueSlice({required this.value, required this.end});
}
