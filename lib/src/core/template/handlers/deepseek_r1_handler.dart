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

/// Handler for DeepSeek R1 format.
///
/// Uses fullwidth Unicode delimiters for tool calls:
/// - `<｜tool▁calls▁begin｜>` / `<｜tool▁calls▁end｜>`
/// - `<｜tool▁call▁begin｜>` / `<｜tool▁call▁end｜>`
/// - `<｜tool▁sep｜>` separates function name from arguments
class DeepseekR1Handler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.deepseekR1;

  @override
  List<String> get additionalStops => ['<｜end▁of▁sentence｜>'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return [...additionalStops, if (hasTools) '<｜tool▁calls▁end｜>'];
  }

  @override
  List<String> get preservedTokens => const [
    '<｜tool▁sep｜>',
    '<｜tool▁calls▁begin｜>',
    '<｜tool▁call▁begin｜>',
    '<｜tool▁call▁end｜>',
    '<｜tool▁calls▁end｜>',
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
    var prompt = template.render({
      'messages': messages.map((m) => m.toJson()).toList(),
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'bos_token':
          metadata['tokenizer.ggml.bos_token'] ?? '<｜begin▁of▁sentence｜>',
      'eos_token':
          metadata['tokenizer.ggml.eos_token'] ?? '<｜end▁of▁sentence｜>',
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
      preservedTokens: hasTools ? preservedTokens : [],
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<｜tool▁calls▁begin｜>')]
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

    // Check for tool calls block
    final toolsBlockRegex = RegExp(
      r'<｜tool▁calls▁begin｜>(.*?)<｜tool▁calls▁end｜>',
      dotAll: true,
    );

    final blockMatch = toolsBlockRegex.firstMatch(text);
    if (blockMatch != null) {
      contentText = text.substring(0, blockMatch.start).trim();

      // Parse individual tool calls within the block
      final singleCallRegex = RegExp(
        r'<｜tool▁call▁begin｜>(.*?)<｜tool▁call▁end｜>',
        dotAll: true,
      );

      final callMatches = singleCallRegex.allMatches(blockMatch.group(1)!);
      for (var i = 0; i < callMatches.length; i++) {
        final callContent = callMatches.elementAt(i).group(1)!.trim();

        // Format: function_name\n<｜tool▁sep｜>\n{json_args}
        final sepIdx = callContent.indexOf('<｜tool▁sep｜>');
        if (sepIdx != -1) {
          final name = callContent.substring(0, sepIdx).trim();
          final argsStr = callContent
              .substring(sepIdx + '<｜tool▁sep｜>'.length)
              .trim();

          try {
            final args = jsonDecode(argsStr);
            toolCalls.add(
              LlamaCompletionChunkToolCall(
                index: i,
                id: 'call_$i',
                type: 'function',
                function: LlamaCompletionChunkFunction(
                  name: name,
                  arguments: args is String ? args : jsonEncode(args),
                ),
              ),
            );
          } catch (_) {}
        }
      }
    }

    return ChatParseResult(
      content: contentText,
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
