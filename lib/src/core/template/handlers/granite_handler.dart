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

/// Handler for IBM Granite models.
///
/// Granite 3.0 explicitly supports tool calling via JSON.
/// It typically uses `<|start_of_role|>tool_response<|end_of_role|>` for tool outputs.
///
/// Tool calls are often just JSON objects or lists of objects in the
/// content, sometimes wrapped in code blocks or just raw JSON.
class GraniteHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.granite;

  @override
  List<String> get additionalStops => ['<|end_of_text|>', '<|end_of_role|>'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) =>
      additionalStops;

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
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<|start_of_text|>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_text|>',
    });

    // Handle enableThinking post-render logic (custom logic if Granite supports it)
    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}</think>\n';
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    // Granite tool calling varies, but let's assume it might output
    // JSON that lists tool calls.
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
          ? [const GrammarTrigger(type: 0, value: '{')]
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
    final text = thinking.content.trim();

    if (!parseToolCalls) {
      return ChatParseResult(
        content: text,
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];

    var jsonStart = -1;
    var isList = false;

    // Try to find start of JSON
    final listStart = text.indexOf('[');
    final objStart = text.indexOf('{');

    if (listStart != -1 && (objStart == -1 || listStart < objStart)) {
      jsonStart = listStart;
      isList = true;
    } else if (objStart != -1) {
      jsonStart = objStart;
    }

    if (jsonStart != -1) {
      final jsonText = text.substring(jsonStart).trim();
      // Simple heuristic: try to parse from jsonStart to end, or find matching bracket
      // For now, try parsing the whole substring
      try {
        if (isList) {
          // Try to find matching ']'
          final end = jsonText.lastIndexOf(']');
          if (end != -1) {
            final candidate = jsonText.substring(0, end + 1);
            final list = jsonDecode(candidate) as List<dynamic>;
            for (var i = 0; i < list.length; i++) {
              final call = list[i] as Map<String, dynamic>;
              if (call.containsKey('name')) {
                toolCalls.add(_createToolCall(i, call));
              }
            }
          }
        } else {
          // Try to find matching '}'
          final end = jsonText.lastIndexOf('}');
          if (end != -1) {
            final candidate = jsonText.substring(0, end + 1);
            final json = jsonDecode(candidate) as Map<String, dynamic>;
            if (json.containsKey('name')) {
              toolCalls.add(_createToolCall(0, json));
            }
          }
        }
      } catch (_) {}
    }

    return ChatParseResult(
      content: jsonStart != -1 ? text.substring(0, jsonStart).trim() : text,
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  LlamaCompletionChunkToolCall _createToolCall(
    int index,
    Map<String, dynamic> json,
  ) {
    final name = json['name'] as String;
    final args = json['arguments'];
    return LlamaCompletionChunkToolCall(
      index: index,
      id: 'call_$index',
      type: 'function',
      function: LlamaCompletionChunkFunction(
        name: name,
        arguments: args is String ? args : jsonEncode(args ?? {}),
      ),
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    // If we wanted strict JSON output, we could build a grammar here,
    // but Granite is usually steered by system prompt.
    return null;
  }
}
