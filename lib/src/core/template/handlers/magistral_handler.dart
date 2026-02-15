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

/// Handler for Magistral format.
///
/// A variant of Mistral Nemo that supports thinking/reasoning with
/// `[THINK]`/`[/THINK]` tags, alongside `[TOOL_CALLS]` for function calling.
class MagistralHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.magistral;

  @override
  String get thinkingStartTag => '[THINK]';

  @override
  String get thinkingEndTag => '[/THINK]';

  @override
  List<String> get additionalStops => ['</s>'];

  @override
  List<String> get preservedTokens => const ['[THINK]', '[/THINK]'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return [...additionalStops, if (hasTools) '[TOOL_CALLS]'];
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
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
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
      preservedTokens: hasTools
          ? const ['[THINK]', '[/THINK]', '[TOOL_CALLS]']
          : preservedTokens,
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '[TOOL_CALLS]')]
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
    final trimmed = text.trim();

    if (!parseToolCalls) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    // Require the explicit [TOOL_CALLS] marker to parse tool calls.
    // Note: when [TOOL_CALLS] is configured as a grammar trigger, the native
    // sampler may consume the marker before it reaches the output buffer.
    // This is a known limitation — the proper fix belongs in the engine layer
    // (e.g. prepending the trigger text to the buffer after grammar activation).
    if (!trimmed.contains('[TOOL_CALLS]')) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    final markerIdx = trimmed.indexOf('[TOOL_CALLS]');
    final contentBefore = trimmed.substring(0, markerIdx).trim();
    final afterMarker = trimmed
        .substring(markerIdx + '[TOOL_CALLS]'.length)
        .trim();

    // Format 1: Ministral - function_name[ARGS]{...}
    // [ARGS] is an explicit marker that doesn't appear in natural text.
    final ministralPattern = RegExp(r'(\w+)\[ARGS\]');
    if (ministralPattern.hasMatch(afterMarker)) {
      for (final match in ministralPattern.allMatches(afterMarker)) {
        final name = match.group(1)!;
        final argsStart = match.end;
        final jsonObj = _extractJsonObject(afterMarker, argsStart);
        if (jsonObj != null) {
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: toolCalls.length,
              id: 'call_${toolCalls.length}',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: name,
                arguments: jsonObj,
              ),
            ),
          );
        }
      }

      if (toolCalls.isNotEmpty) {
        return ChatParseResult(
          content: contentBefore,
          reasoningContent: thinking.reasoning,
          toolCalls: toolCalls,
        );
      }
    }

    // Format 2: Mistral Nemo JSON array - [TOOL_CALLS][{...}, ...]
    try {
      final list = jsonDecode(afterMarker) as List<dynamic>;
      for (var i = 0; i < list.length; i++) {
        final call = list[i] as Map<String, dynamic>;
        final name = call['name'] as String?;
        final args = call['arguments'];
        final id = call['id'] as String?;
        if (name != null) {
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: i,
              id: id ?? 'call_$i',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: name,
                arguments: args is String ? args : jsonEncode(args ?? {}),
              ),
            ),
          );
        }
      }
      if (toolCalls.isNotEmpty) {
        return ChatParseResult(
          content: contentBefore,
          reasoningContent: thinking.reasoning,
          toolCalls: toolCalls,
        );
      }
    } catch (_) {
      // Not a JSON array, fall through
    }

    // Marker present but could not parse tool calls
    return ChatParseResult(
      content: trimmed,
      reasoningContent: thinking.reasoning,
    );
  }

  /// Extracts a balanced JSON object starting at [offset] in [input].
  ///
  /// Counts brace depth while respecting quoted strings so that nested
  /// objects like `{"a": {"b": 1}}` are extracted correctly.
  /// Returns the JSON substring, or `null` if no valid object is found.
  String? _extractJsonObject(String input, int offset) {
    // Skip whitespace (including newlines/tabs) to find the opening brace
    var start = offset;
    while (start < input.length) {
      final ch = input[start];
      if (ch != ' ' && ch != '\n' && ch != '\r' && ch != '\t') break;
      start++;
    }
    if (start >= input.length || input[start] != '{') return null;

    var depth = 0;
    var inString = false;
    for (var i = start; i < input.length; i++) {
      final c = input[i];

      if (inString) {
        if (c == r'\') {
          i++; // skip escaped character
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }

      switch (c) {
        case '"':
          inString = true;
        case '{':
          depth++;
        case '}':
          depth--;
          if (depth == 0) {
            final json = input.substring(start, i + 1);
            try {
              jsonDecode(json); // validate
              return json;
            } catch (_) {
              return null;
            }
          }
      }
    }
    return null; // unbalanced braces
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return ToolCallGrammarUtils.buildWrappedArrayGrammar(
      tools: tools,
      prefix: '[TOOL_CALLS]',
      suffix: '',
      idKey: 'id',
      idPattern: r'^[a-zA-Z0-9]{9}$',
    );
  }
}
