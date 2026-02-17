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
/// Tool calls follow llama.cpp generic JSON envelopes:
/// - `{"tool_call": {"name": ..., "arguments": ...}}`
/// - `{"response": "..."}`
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

    final stops = _inferStopsFromTemplate(effectiveTemplate);

    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: false,
      additionalStops: stops,
      grammarTriggers: const [],
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

    final trimmed = text.trim();
    final decoded = _decodeJsonObject(trimmed);
    if (decoded == null) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    if (decoded.containsKey('tool_calls')) {
      final toolCalls = _extractToolCalls(decoded['tool_calls']);
      if (toolCalls == null) {
        return ChatParseResult(
          content: trimmed,
          reasoningContent: thinking.reasoning,
        );
      }
      return ChatParseResult(
        content: '',
        reasoningContent: thinking.reasoning,
        toolCalls: toolCalls,
      );
    }

    if (decoded.containsKey('tool_call')) {
      final toolCall = _toToolCall(decoded['tool_call'], 0);
      if (toolCall == null) {
        return ChatParseResult(
          content: trimmed,
          reasoningContent: thinking.reasoning,
        );
      }
      return ChatParseResult(
        content: '',
        reasoningContent: thinking.reasoning,
        toolCalls: [toolCall],
      );
    }

    final response = decoded['response'];
    if (decoded.containsKey('response')) {
      return ChatParseResult(
        content: response is String
            ? response
            : const JsonEncoder.withIndent('  ').convert(response),
        reasoningContent: thinking.reasoning,
      );
    }

    return ChatParseResult(
      content: trimmed,
      reasoningContent: thinking.reasoning,
    );
  }

  Map<String, dynamic>? _decodeJsonObject(String text) {
    if (text.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  List<LlamaCompletionChunkToolCall>? _extractToolCalls(Object? value) {
    if (value is! List) {
      return null;
    }
    final calls = <LlamaCompletionChunkToolCall>[];
    for (var i = 0; i < value.length; i++) {
      final toolCall = _toToolCall(value[i], i);
      if (toolCall == null) {
        return null;
      }
      calls.add(toolCall);
    }
    return calls;
  }

  LlamaCompletionChunkToolCall? _toToolCall(Object? value, int index) {
    if (value is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(value);

    final rawName = map['name'];
    if (rawName is! String || rawName.isEmpty) {
      return null;
    }

    final rawId = map['id'];
    final id = rawId is String && rawId.isNotEmpty ? rawId : null;

    var encodedArguments = '';
    if (map.containsKey('arguments')) {
      final arguments = map['arguments'];
      if (arguments == null) {
        encodedArguments = '';
      } else {
        encodedArguments = arguments is String
            ? arguments
            : jsonEncode(arguments);
      }
    }

    return LlamaCompletionChunkToolCall(
      index: index,
      id: id ?? 'call_$index',
      type: 'function',
      function: LlamaCompletionChunkFunction(
        name: rawName,
        arguments: encodedArguments,
      ),
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
