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

    // Check for [TOOL_CALLS] prefix
    if (!trimmed.startsWith('[TOOL_CALLS]')) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    // Strip the prefix and parse JSON array
    final jsonStr = trimmed.substring('[TOOL_CALLS]'.length).trim();
    final toolCalls = <LlamaCompletionChunkToolCall>[];

    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
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
    } catch (_) {
      // If JSON parsing fails, return as content
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    return ChatParseResult(
      content: '',
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    // Mistral-based, native tool calling via template
    return null;
  }
}
