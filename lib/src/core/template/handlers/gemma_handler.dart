import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';

/// Handler for Gemma 3 / Gemma 3n models.
///
/// Uses `<start_of_turn>` / `<end_of_turn>` markers with `developer` and
/// `model` roles. Tool calling is prompt-engineered — the model outputs
/// JSON like `{"tool_call": {"type": "name", "parameters": {...}}}`.
///
/// Gemma 3n also supports multimodal content via `<audio_soft_token>` and
/// `<image_soft_token>` markers in the template.
class GemmaHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.gemma;

  @override
  List<String> get additionalStops => ['<end_of_turn>'];

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
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<bos>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<eos>',
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
          ? [const GrammarTrigger(type: 0, value: '{"tool_call"')]
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
    final trimmed = output.trim();

    if (!parseToolCalls || !trimmed.contains('"tool_call"')) {
      return ChatParseResult(content: trimmed);
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var contentText = trimmed;

    // Match {"tool_call": { ... }} blocks
    final regex = RegExp(
      r'\{[^{]*"tool_call"\s*:\s*({(?:[^{}]|{(?:[^{}]|{[^{}]*})*})*})\s*\}',
      dotAll: true,
    );

    final matches = regex.allMatches(trimmed);
    for (var i = 0; i < matches.length; i++) {
      try {
        final raw = matches.elementAt(i).group(0)!;
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final toolCall = json['tool_call'] as Map<String, dynamic>?;
        if (toolCall != null) {
          // Gemma 3 uses 'code', 'type', or 'tool_name' for name
          final name =
              toolCall['name'] as String? ??
              toolCall['type'] as String? ??
              toolCall['code'] as String? ??
              toolCall['tool_name'] as String?;
          final args = toolCall['parameters'] ?? toolCall['arguments'];
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
        }
        contentText = contentText.replaceAll(raw, '');
      } catch (_) {}
    }

    return ChatParseResult(content: contentText.trim(), toolCalls: toolCalls);
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    // Gemma uses prompt-engineered tool calling — no grammar needed
    return null;
  }
}
