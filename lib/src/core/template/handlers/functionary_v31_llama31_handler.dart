import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';

/// Handler for Functionary v3.1 Llama 3.1 templates.
///
/// Supports `<function=name>{...}</function>` tool calls and
/// `<|python_tag|><code>` python fallback.
class FunctionaryV31Llama31Handler extends ChatTemplateHandler {
  static const String _pythonTag = '<|python_tag|>';

  @override
  ChatFormat get format => ChatFormat.functionaryV31Llama31;

  @override
  List<String> get additionalStops => ['<|eot_id|>', '<|eom_id|>'];

  @override
  List<String> get preservedTokens => const [_pythonTag];

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
    final hasTools = tools != null && tools.isNotEmpty;

    final prompt = template.render({
      'messages': messages.map((m) => m.toJson()).toList(),
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<|begin_of_text|>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_text|>',
    });

    return LlamaChatTemplateResult(
      prompt: prompt,
      format: hasTools ? format.index : ChatFormat.contentOnly.index,
      grammar: buildGrammar(tools),
      grammarLazy: hasTools,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: hasTools
          ? [
              const GrammarTrigger(type: 0, value: '<function='),
              const GrammarTrigger(type: 0, value: _pythonTag),
            ]
          : const [],
    );
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    if (!parseToolCalls) {
      return ChatParseResult(content: output.trim());
    }

    var text = output;
    final toolCalls = <LlamaCompletionChunkToolCall>[];

    final functionTag = RegExp(
      r'<function=([^>]+)>(.*?)</function>',
      dotAll: true,
    );
    for (final match in functionTag.allMatches(output)) {
      final name = match.group(1)?.trim();
      final body = match.group(2)?.trim() ?? '';
      if (name == null || name.isEmpty) {
        continue;
      }

      toolCalls.add(
        LlamaCompletionChunkToolCall(
          index: toolCalls.length,
          id: 'call_${toolCalls.length}',
          type: 'function',
          function: LlamaCompletionChunkFunction(
            name: name,
            arguments: _normalizeArguments(body),
          ),
        ),
      );
      text = text.replaceAll(match.group(0)!, '');
    }

    final pythonIdx = text.indexOf(_pythonTag);
    if (pythonIdx != -1) {
      final before = text.substring(0, pythonIdx);
      final code = text.substring(pythonIdx + _pythonTag.length).trim();
      if (code.isNotEmpty) {
        toolCalls.add(
          LlamaCompletionChunkToolCall(
            index: toolCalls.length,
            id: 'call_${toolCalls.length}',
            type: 'function',
            function: LlamaCompletionChunkFunction(
              name: 'python',
              arguments: jsonEncode({'code': code}),
            ),
          ),
        );
      }
      text = before;
    } else if (isPartial && text.contains('<function=')) {
      final openIdx = text.indexOf('<function=');
      if (openIdx != -1) {
        final nameEnd = text.indexOf('>', openIdx + '<function='.length);
        if (nameEnd != -1) {
          final name = text
              .substring(openIdx + '<function='.length, nameEnd)
              .trim();
          final args = text.substring(nameEnd + 1).trim();
          if (name.isNotEmpty && args.isNotEmpty) {
            toolCalls.add(
              LlamaCompletionChunkToolCall(
                index: toolCalls.length,
                id: 'call_${toolCalls.length}',
                type: 'function',
                function: LlamaCompletionChunkFunction(
                  name: name,
                  arguments: args,
                ),
              ),
            );
            text = text.substring(0, openIdx);
          }
        }
      }
    }

    return ChatParseResult(content: text.trim(), toolCalls: toolCalls);
  }

  String _normalizeArguments(String body) {
    if (body.isEmpty) {
      return '{}';
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return jsonEncode(Map<String, dynamic>.from(decoded));
      }
      return jsonEncode({'value': decoded});
    } catch (_) {
      return body;
    }
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
