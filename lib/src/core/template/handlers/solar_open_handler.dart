import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';

/// Handler for Solar Open format.
///
/// Solar Open encodes reasoning in `<|think|> ...` channel blocks.
class SolarOpenHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.solarOpen;

  @override
  String get thinkingStartTag => '<|think|>';

  @override
  String get thinkingEndTag => '<|end|><|begin|>assistant<|content|>';

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
    final renderedMessages = messages.map((m) {
      final json = m.toJson();
      final reasoning = json['reasoning_content'];
      if (reasoning is String && reasoning.isNotEmpty) {
        json['reasoning'] = reasoning;
        json.remove('reasoning_content');
      }
      return json;
    }).toList();

    final template = Template(templateSource);
    var prompt = template.render({
      'messages': renderedMessages,
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
    });

    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt, startTag: thinkingStartTag)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}$thinkingEndTag';
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

    return ChatParseResult(
      content: thinking.content.trim(),
      reasoningContent: thinking.reasoning,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
