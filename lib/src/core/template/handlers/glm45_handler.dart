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

/// Handler for GLM 4.5 format.
///
/// Uses `<|observation|>` as a stop token for tool call observation.
/// Tool call format: `func_name\n<arg_name>arg_value</arg_name>...`
///
/// Supports `<think>`/`</think>` for reasoning.
class Glm45Handler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.glm45;

  @override
  List<String> get additionalStops => ['<|observation|>'];

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
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '[gMASK]<|sop|>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|user|>',
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
    // GLM 4.5 doesn't use a specific trigger token for tools in all cases,
    // but <|tool_call|> is commonly observed.
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
      grammarTriggers: [],
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

    // Pattern: `func_name\n<arg>val</arg>...`
    // We look for function names followed by XML parameters
    // This is tricky because the function name is just a word at the start of line

    // Simple heuristic: if line starts with word chars and next line has XML tag
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // Potential function name?
      if (RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(line)) {
        // Check subsequent lines for args
        var j = i + 1;
        var argsContent = '';
        while (j < lines.length) {
          final nextLine = lines[j].trim();
          if (nextLine.startsWith('<') && nextLine.endsWith('>')) {
            argsContent += nextLine;
            j++;
          } else {
            break;
          }
        }

        if (argsContent.isNotEmpty) {
          final args = <String, dynamic>{};
          final argRegex = RegExp(r'<([^>]+)>([^<]+)</\1>');
          for (final match in argRegex.allMatches(argsContent)) {
            final key = match.group(1)!;
            final val = match.group(2)!;
            // Try parse JSON, else string
            try {
              args[key] = jsonDecode(val);
            } catch (_) {
              args[key] = val;
            }
          }

          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: toolCalls.length,
              id: 'call_${toolCalls.length}',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: line,
                arguments: jsonEncode(args),
              ),
            ),
          );

          // Remove parsed text from content
          // (Simplified removal strategy - might need refinement based on exact layout)
          contentText = contentText
              .replaceFirst(line, '')
              .replaceFirst(argsContent, '');
          i = j - 1;
        }
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
