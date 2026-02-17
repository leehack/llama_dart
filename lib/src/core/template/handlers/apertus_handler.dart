import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../grammar/json_schema_converter.dart';
import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';

/// Handler for Apertus format.
class ApertusHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.apertus;

  @override
  String get thinkingStartTag => '<|inner_prefix|>';

  @override
  String get thinkingEndTag => '<|inner_suffix|>';

  @override
  List<String> get additionalStops => [];

  @override
  List<String> get preservedTokens => const [
    '<|system_start|>',
    '<|system_end|>',
    '<|developer_start|>',
    '<|developer_end|>',
    '<|user_start|>',
    '<|user_end|>',
    '<|assistant_start|>',
    '<|assistant_end|>',
    '<|inner_prefix|>',
    '<|inner_suffix|>',
    '<|tools_prefix|>',
    '<|tools_suffix|>',
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
    var prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': messages.map((m) => m.toJson()).toList(),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
      },
    );

    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt, startTag: thinkingStartTag)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}$thinkingEndTag';
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final triggerPattern = thinkingForcedOpen
        ? r'[\s\S]*?(<\|inner_suffix\|>\s*)(<\|tools_prefix\|>)[\s\S]*'
        : r'(?:<\|inner_prefix\|>[\s\S]*?<\|inner_suffix\|>\s*)?(<\|tools_prefix\|>)[\s\S]*';
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
      preservedTokens: hasTools ? preservedTokens : const [],
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

    const prefix = '<|tools_prefix|>';
    const suffix = '<|tools_suffix|>';

    final start = text.indexOf(prefix);
    if (start == -1) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final prelude = text.substring(0, start);
    final payload = text.substring(start + prefix.length);
    final jsonSlice = _extractLeadingJsonValue(payload, 0);
    if (jsonSlice == null || jsonSlice.value is! List) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    var cursor = jsonSlice.end;
    while (cursor < payload.length && payload.codeUnitAt(cursor) <= 0x20) {
      cursor++;
    }
    if (!payload.startsWith(suffix, cursor)) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    for (final value in jsonSlice.value as List<dynamic>) {
      if (value is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(value);
      if (map.length != 1) {
        continue;
      }

      final entry = map.entries.first;
      final name = entry.key;
      if (name.isEmpty) {
        continue;
      }
      final args = entry.value;
      final arguments = args is String
          ? args
          : (args == null ? '' : jsonEncode(args));
      toolCalls.add(
        LlamaCompletionChunkToolCall(
          index: toolCalls.length,
          id: null,
          type: 'function',
          function: LlamaCompletionChunkFunction(
            name: name,
            arguments: arguments,
          ),
        ),
      );
    }

    final trailing = payload.substring(cursor + suffix.length);
    return ChatParseResult(
      content: '$prelude$trailing'.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
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
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final itemSchemas = tools
        .map(
          (tool) => <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{tool.name: tool.toJsonSchema()},
            'required': <String>[tool.name],
          },
        )
        .toList(growable: false);

    final schema = <String, dynamic>{
      'type': 'array',
      'items': itemSchemas.length == 1
          ? itemSchemas.first
          : <String, dynamic>{'anyOf': itemSchemas},
      'minItems': 1,
    };

    final grammar = JsonSchemaConverter.convert(schema);
    return ToolCallGrammarUtils.wrapRootGrammar(
      grammar,
      prefix: '<|tools_prefix|>',
      suffix: '<|tools_suffix|>',
    );
  }
}

final class _JsonValueSlice {
  final Object? value;
  final int end;

  const _JsonValueSlice({required this.value, required this.end});
}
