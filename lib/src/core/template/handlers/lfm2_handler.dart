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

/// Handler for LFM2 (Liquid Foundation Model 2) format.
///
/// Uses `<|tool_call_start|>` / `<|tool_call_end|>` special tokens for tool calls,
/// and `<|tool_list_start|>` / `<|tool_list_end|>` for tool definitions.
///
/// Also supports the legacy bracket format: `[function_name(arg1='val1')]`
class Lfm2Handler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.lfm2;

  @override
  List<String> get additionalStops => ['<|im_end|>'];

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
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '',
    });

    final hasTools = tools != null && tools.isNotEmpty;
    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: hasTools,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<|tool_call_start|>')]
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

    // Try <|tool_call_start|>/<|tool_call_end|> format first
    final toolCallRegex = RegExp(
      r'<\|tool_call_start\|>\s*(.*?)\s*<\|tool_call_end\|>',
      dotAll: true,
    );

    final matches = toolCallRegex.allMatches(text);
    for (var i = 0; i < matches.length; i++) {
      final match = matches.elementAt(i);
      try {
        final json = jsonDecode(match.group(1)!) as Map<String, dynamic>;
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
      } catch (_) {}
      contentText = contentText.replaceAll(match.group(0)!, '');
    }

    // Fallback: try legacy bracket format [function_name(args)]
    if (toolCalls.isEmpty) {
      final bracketRegex = RegExp(
        r'\[([a-zA-Z0-9_]+)\((.*?)\)\]',
        dotAll: true,
      );
      final bracketMatches = bracketRegex.allMatches(text);
      for (var i = 0; i < bracketMatches.length; i++) {
        final match = bracketMatches.elementAt(i);
        final name = match.group(1)?.trim() ?? '';
        final argsStr = match.group(2)?.trim() ?? '';

        toolCalls.add(
          LlamaCompletionChunkToolCall(
            index: i,
            id: 'call_$i',
            type: 'function',
            function: LlamaCompletionChunkFunction(
              name: name,
              arguments: _parseBracketArgs(argsStr),
            ),
          ),
        );
        contentText = contentText.replaceAll(match.group(0)!, '');
      }
    }

    return ChatParseResult(
      content: contentText.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  /// Parses the bracket-style arguments (key=value, key='value')
  /// into a JSON string.
  String _parseBracketArgs(String argsStr) {
    if (argsStr.isEmpty) return '{}';

    final args = <String, dynamic>{};
    // Match key=value pairs, where value can be quoted
    final argRegex = RegExp(r'''(\w+)\s*=\s*(?:'([^']*)'|"([^"]*)"|(\S+))''');
    for (final match in argRegex.allMatches(argsStr)) {
      final key = match.group(1)!;
      final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
      // Try to parse as number
      final numVal = num.tryParse(value);
      if (numVal != null) {
        args[key] = numVal;
      } else if (value == 'true' || value == 'false') {
        args[key] = value == 'true';
      } else {
        args[key] = value;
      }
    }
    return jsonEncode(args);
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
