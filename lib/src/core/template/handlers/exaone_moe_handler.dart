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

/// Handler for EXAONE MoE format.
///
/// EXAONE MoE uses `<think>` tags and `<tool_call>{...}</tool_call>` blocks.
class ExaoneMoeHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.exaoneMoe;

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
    var prompt = template.render({
      'messages': messages.map((m) => m.toJson()).toList(),
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
    });

    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}</think>';
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
    final shouldTreatAsContent =
        thinkingForcedOpen && !isPartial && !output.contains('</think>');

    final extracted = shouldTreatAsContent
        ? (content: output, reasoning: null)
        : extractThinking(output, thinkingForcedOpen: thinkingForcedOpen);

    if (!parseToolCalls) {
      return ChatParseResult(
        content: extracted.content.trim(),
        reasoningContent: extracted.reasoning,
      );
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var contentText = extracted.content;

    final regex = RegExp(
      r'<tool_call[^>]*>([\s\S]*?)</tool_call>',
      dotAll: true,
    );
    final matches = regex.allMatches(extracted.content);

    for (final match in matches) {
      final body = match.group(1);
      if (body == null) {
        continue;
      }

      final payload = _stripCodeFence(body.trim());

      try {
        final decoded = jsonDecode(payload);
        final toolCall = _toToolCall(decoded, toolCalls.length);
        if (toolCall == null) {
          continue;
        }
        toolCalls.add(toolCall);
        contentText = contentText.replaceFirst(match.group(0)!, '');
      } catch (_) {
        // Keep malformed tool blocks in content.
      }
    }

    return ChatParseResult(
      content: contentText.trim(),
      reasoningContent: extracted.reasoning,
      toolCalls: toolCalls,
    );
  }

  LlamaCompletionChunkToolCall? _toToolCall(Object? value, int index) {
    if (value is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(value);

    String? name;
    String? id;
    Object? arguments;

    if (map['name'] is String) {
      name = map['name'] as String;
      arguments = map['arguments'];
      id = map['id'] as String?;
    } else if (map['function'] is Map) {
      final function = Map<String, dynamic>.from(map['function'] as Map);
      name = function['name'] as String?;
      arguments = function['arguments'];
      id = map['id'] as String?;
    }

    if (name == null || name.isEmpty) {
      return null;
    }

    return LlamaCompletionChunkToolCall(
      index: index,
      id: id ?? 'call_$index',
      type: (map['type'] as String?) ?? 'function',
      function: LlamaCompletionChunkFunction(
        name: name,
        arguments: arguments is String
            ? arguments
            : jsonEncode(arguments ?? <String, dynamic>{}),
      ),
    );
  }

  String _stripCodeFence(String value) {
    var text = value;
    if (text.startsWith('```json')) {
      text = text.substring('```json'.length).trim();
    } else if (text.startsWith('```')) {
      text = text.substring('```'.length).trim();
    }

    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3).trim();
    }
    return text;
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
