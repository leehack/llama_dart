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

/// The built-in ChatML template used as fallback when the model has none.
const String _chatMlTemplate = '''
{%- for message in messages -%}
  {{- '<|im_start|>' + message.role + '\\n' + message.content + '<|im_end|>\\n' -}}
{%- endfor -%}
{%- if add_generation_prompt -%}
  {{- '<|im_start|>assistant\\n' -}}
{%- endif -%}
''';

/// Handler for generic ChatML-based models.
///
/// This is the universal fallback handler. Used when a model's template
/// contains `<|im_start|>` tokens but no format-specific tool call markers.
///
/// Tool calls are rendered/parsed using `<tool_call>` tags similar to Hermes.
class GenericHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.generic;

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
    // Use provided template if available, otherwise fall back to ChatML
    final effectiveTemplate = templateSource.isNotEmpty
        ? templateSource
        : _chatMlTemplate;

    final template = Template(effectiveTemplate);
    final prompt = template.render({
      'messages': messages.map((m) => m.toJson()).toList(),
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
    });

    final hasTools = tools != null && tools.isNotEmpty;
    final stops = _inferStopsFromTemplate(effectiveTemplate);

    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: hasTools,
      additionalStops: stops,
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<tool_call>')]
          : [],
    );
  }

  List<String> _inferStopsFromTemplate(String templateSource) {
    final stops = <String>{};

    if (templateSource.contains('<|im_end|>')) {
      stops.add('<|im_end|>');
    }
    if (templateSource.contains('<|end|>')) {
      stops.add('<|end|>');
    }

    if (stops.isEmpty) {
      stops.addAll(additionalStops);
    }

    return stops.toList(growable: false);
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

    // Try to parse tool calls from <tool_call> tags (similar to Hermes)
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

    // Also try direct JSON tool call detection (no wrapping tags)
    if (toolCalls.isEmpty && text.contains('"name"')) {
      try {
        final json = jsonDecode(text.trim()) as Map<String, dynamic>;
        final name = json['name'] as String?;
        final args = json['arguments'];
        if (name != null) {
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: 0,
              id: 'call_0',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: name,
                arguments: args is String ? args : jsonEncode(args ?? {}),
              ),
            ),
          );
          contentText = '';
        }
      } catch (_) {}
    }

    return ChatParseResult(
      content: contentText.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    // Generic handler doesn't build grammar — relies on prompt-based tool calling
    return null;
  }

  /// The built-in ChatML template string.
  static String get chatMlTemplate => _chatMlTemplate;
}
