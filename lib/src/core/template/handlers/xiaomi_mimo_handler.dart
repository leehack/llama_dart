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

/// Handler for Xiaomi MiMo format.
///
/// Xiaomi MiMo emits tool calls as `<tool_call>{...}</tool_call>` blocks.
class XiaomiMimoHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.xiaomiMimo;

  @override
  List<String> get additionalStops => [];

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
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
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
          ? [const GrammarTrigger(type: 0, value: '<tool_call>')]
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

    final regex = RegExp(
      r'<tool_call>\s*(\{.*?\})\s*</tool_call>',
      dotAll: true,
    );
    final matches = regex.allMatches(text);
    for (final match in matches) {
      final payload = match.group(1);
      if (payload == null) {
        continue;
      }

      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map) {
          continue;
        }
        final mapped = Map<String, dynamic>.from(decoded);
        final name = mapped['name'] as String?;
        if (name == null || name.isEmpty) {
          continue;
        }

        final arguments = mapped['arguments'];
        toolCalls.add(
          LlamaCompletionChunkToolCall(
            index: toolCalls.length,
            id: mapped['id'] as String?,
            type: (mapped['type'] as String?) ?? 'function',
            function: LlamaCompletionChunkFunction(
              name: name,
              arguments: arguments is String
                  ? arguments
                  : jsonEncode(arguments ?? <String, dynamic>{}),
            ),
          ),
        );

        contentText = contentText.replaceFirst(match.group(0)!, '');
      } catch (_) {
        // Keep malformed tool blocks as plain content.
      }
    }

    return ChatParseResult(
      content: contentText.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
