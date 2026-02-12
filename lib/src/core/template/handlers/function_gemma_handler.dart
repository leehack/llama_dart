import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';

/// Handler for FunctionGemma format.
///
/// Uses `<start_function_call>call:name{args}<end_function_call>` format
/// with `<escape>` tokens instead of double quotes.
///
/// Tool declarations use `<start_function_declaration>` / `<end_function_declaration>`.
class FunctionGemmaHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.functionGemma;

  @override
  List<String> get additionalStops => ['<end_of_turn>', '<end_function_call>'];

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
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<bos>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<eos>',
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
          ? [const GrammarTrigger(type: 0, value: '<start_function_call>')]
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
    if (!parseToolCalls) {
      return ChatParseResult(content: output.trim());
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var contentText = output;

    // Parse <start_function_call>call:name{args}<end_function_call>
    final regex = RegExp(
      r'<start_function_call>(?:call:)?([a-zA-Z0-9_\.]+)\{(.*?)\}(?:<end_function_call>)?',
      dotAll: true,
    );

    final matches = regex.allMatches(output);
    for (var i = 0; i < matches.length; i++) {
      final match = matches.elementAt(i);
      final name = match.group(1)?.trim() ?? '';
      var arguments = match.group(2)?.trim() ?? '{}';

      // Filter out common hallucinations
      if (name == 'func_name' ||
          name == 'function_name' ||
          name == 'name' ||
          arguments == 'args' ||
          arguments == 'arguments') {
        continue;
      }

      // FunctionGemma uses <escape> for double quotes
      arguments = arguments.replaceAll('<escape>', '"');

      // FunctionGemma outputs unquoted keys like {location:"London"}
      // Convert to valid JSON by quoting unquoted keys
      arguments = _toValidJson(arguments);

      toolCalls.add(
        LlamaCompletionChunkToolCall(
          index: i,
          id: 'call_$i',
          type: 'function',
          function: LlamaCompletionChunkFunction(
            name: name,
            arguments: arguments,
          ),
        ),
      );
      contentText = contentText.replaceAll(match.group(0)!, '');
    }

    return ChatParseResult(content: contentText.trim(), toolCalls: toolCalls);
  }

  /// Converts FunctionGemma pseudo-JSON (unquoted keys) to valid JSON.
  ///
  /// Input:  `{location:"London",unit:"celsius"}`
  /// Output: `{"location":"London","unit":"celsius"}`
  String _toValidJson(String input) {
    // Quote unquoted keys: match word chars before a colon that aren't already quoted
    final result = input.replaceAllMapped(
      RegExp(r'(?<=[{,])\s*([a-zA-Z_]\w*)\s*:'),
      (m) => '"${m.group(1)}":',
    );
    return result;
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
