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

/// Handler for Llama 3.x models.
///
/// Uses the ipython role for tool calls with `<|python_tag|>` trigger.
/// Tool call format: `{"name": "fn", "parameters": {...}}`
class Llama3Handler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.llama3;

  @override
  List<String> get additionalStops => ['<|eot_id|>', '<|eom_id|>'];

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
          ? [const GrammarTrigger(type: 0, value: '{"name"')]
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
    final trimmed = text.trim();

    if (!parseToolCalls) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];

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
            toolCalls.add(
              LlamaCompletionChunkToolCall(
                index: i,
                id: 'call_$i',
                type: 'function',
                function: LlamaCompletionChunkFunction(
                  name: name,
                  arguments: params is String
                      ? params
                      : jsonEncode(params ?? {}),
                ),
              ),
            );
          }
        }
      } catch (_) {}
    } else if (trimmed.startsWith('{') &&
        (trimmed.contains('"name"') || trimmed.contains('"function"'))) {
      // Single JSON tool call
      try {
        final json = jsonDecode(trimmed) as Map<String, dynamic>;
        final name = (json['name'] ?? json['function']) as String?;
        final params = json['parameters'] ?? json['arguments'];
        if (name != null) {
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: 0,
              id: 'call_0',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: name,
                arguments: params is String ? params : jsonEncode(params ?? {}),
              ),
            ),
          );
        }
      } catch (_) {}
    }

    return ChatParseResult(
      content: toolCalls.isNotEmpty ? '' : trimmed,
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    // Llama 3 uses native tool calling via the template — grammar not needed
    return null;
  }
}
