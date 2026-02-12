import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../models/chat/chat_role.dart';
import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';

/// Handler for DeepSeek V3.1 format.
///
/// Similar to Hermes with `<tool_call>` tags but uses prefix-based thinking
/// and `<|end_of_sentence|>` stop token.
class DeepseekV3Handler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.deepseekV3;

  @override
  List<String> get additionalStops => ['<|end_of_sentence|>'];

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
    final bosToken =
        metadata['tokenizer.ggml.bos_token'] ?? '<|begin_of_sentence|>';
    final eosToken =
        metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_sentence|>';

    // Prepend bos_token to the first system message if it exists
    final modifiedMessages = messages.map((m) {
      if (m.role == LlamaChatRole.system && m == messages.first) {
        return m.copyWith(content: '$bosToken${m.content}');
      }
      return m;
    }).toList();

    var prompt = template.render({
      'messages': modifiedMessages.map((m) => m.toJson()).toList(),
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'bos_token': bosToken,
      'eos_token': eosToken,
    });

    // Handle enableThinking post-render logic
    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}</think>\n';
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
    final toolCallRegex = RegExp(
      r'<tool_call>\s*(.*?)\s*</tool_call>',
      dotAll: true,
    );

    var contentText = text;
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
