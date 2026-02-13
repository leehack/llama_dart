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

/// Handler for Nemotron V2 format.
///
/// Nemotron V2 emits tool calls inside `<TOOLCALL>[...]</TOOLCALL>` blocks.
class NemotronV2Handler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.nemotronV2;

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
          ? [const GrammarTrigger(type: 0, value: '<TOOLCALL>')]
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

    final regex = RegExp(r'<TOOLCALL>\s*(.*?)\s*</TOOLCALL>', dotAll: true);
    final matches = regex.allMatches(text);
    for (final match in matches) {
      final payload = match.group(1);
      if (payload == null) {
        continue;
      }

      try {
        final decoded = jsonDecode(payload);
        if (decoded is List) {
          for (final item in decoded) {
            final toolCall = _toToolCall(item, toolCalls.length);
            if (toolCall != null) {
              toolCalls.add(toolCall);
            }
          }
        } else {
          final toolCall = _toToolCall(decoded, toolCalls.length);
          if (toolCall != null) {
            toolCalls.add(toolCall);
          }
        }

        contentText = contentText.replaceFirst(match.group(0)!, '');
      } catch (_) {
        // Keep malformed block in content.
      }
    }

    return ChatParseResult(
      content: contentText.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  LlamaCompletionChunkToolCall? _toToolCall(Object? data, int index) {
    if (data is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(data);

    String? name;
    Object? arguments;

    if (map['name'] is String) {
      name = map['name'] as String;
      arguments = map['arguments'];
    } else if (map['function'] is Map) {
      final function = Map<String, dynamic>.from(map['function'] as Map);
      name = function['name'] as String?;
      arguments = function['arguments'];
    }

    if (name == null || name.isEmpty) {
      return null;
    }

    return LlamaCompletionChunkToolCall(
      index: index,
      id: map['id'] as String?,
      type: (map['type'] as String?) ?? 'function',
      function: LlamaCompletionChunkFunction(
        name: name,
        arguments: arguments is String
            ? arguments
            : jsonEncode(arguments ?? <String, dynamic>{}),
      ),
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
