import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_role.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';

/// Handler for LFM2 (Liquid Foundation Model 2) format.
///
/// Uses `<|tool_call_start|>` / `<|tool_call_end|>` special tokens for tool calls,
/// and `<|tool_list_start|>` / `<|tool_list_end|>` for tool definitions.
class Lfm2Handler extends ChatTemplateHandler {
  static final RegExp _forceJsonSchemaLineMarker = RegExp(
    r'force json schema\.\n',
    caseSensitive: false,
  );

  static final RegExp _forceJsonSchemaMarker = RegExp(
    r'force json schema\.',
    caseSensitive: false,
  );

  @override
  ChatFormat get format => ChatFormat.lfm2;

  @override
  List<String> get additionalStops => ['<|im_end|>'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    if (hasTools) {
      return const [];
    }

    return additionalStops;
  }

  @override
  List<String> get preservedTokens => const [
    '<|tool_call_start|>',
    '<|tool_call_end|>',
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
    final hasTools = tools != null && tools.isNotEmpty;
    final shouldConstrainWithJsonTools =
        hasTools && _shouldConstrainWithJsonTools(messages);
    final effectiveMessages = shouldConstrainWithJsonTools
        ? _stripForceJsonSchemaMarker(messages)
        : messages;

    final prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': effectiveMessages.map((m) => m.toJson()).toList(),
        'add_generation_prompt': addAssistant,
        'tools': _serializeToolsForTemplate(tools),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '',
      },
    );

    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: shouldConstrainWithJsonTools ? buildGrammar(tools) : null,
      grammarLazy: shouldConstrainWithJsonTools,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: shouldConstrainWithJsonTools
          ? [
              const GrammarTrigger(
                type: 3,
                value: r'\s*<\|tool_call_start\|>\s*\[',
              ),
            ]
          : [],
    );
  }

  bool _shouldConstrainWithJsonTools(List<LlamaChatMessage> messages) {
    if (messages.isEmpty) {
      return false;
    }

    final first = messages.first;
    if (first.role != LlamaChatRole.system) {
      return false;
    }

    final content = first.content;
    return _forceJsonSchemaLineMarker.hasMatch(content) ||
        _forceJsonSchemaMarker.hasMatch(content);
  }

  List<LlamaChatMessage> _stripForceJsonSchemaMarker(
    List<LlamaChatMessage> messages,
  ) {
    if (messages.isEmpty) {
      return messages;
    }

    final first = messages.first;
    if (first.role != LlamaChatRole.system) {
      return messages;
    }

    var stripped = first.content.replaceFirst(_forceJsonSchemaLineMarker, '');
    if (stripped == first.content) {
      stripped = first.content.replaceFirst(_forceJsonSchemaMarker, '');
    }
    if (stripped == first.content) {
      return messages;
    }

    return <LlamaChatMessage>[
      first.copyWith(content: stripped),
      ...messages.skip(1),
    ];
  }

  List<Map<String, dynamic>>? _serializeToolsForTemplate(
    List<ToolDefinition>? tools,
  ) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    return tools
        .map(
          (tool) => <String, dynamic>{
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.toJsonSchema(),
          },
        )
        .toList(growable: false);
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    if (!parseToolCalls) {
      final thinking = extractThinking(
        output,
        thinkingForcedOpen: thinkingForcedOpen,
      );
      return ChatParseResult(
        content: thinking.content.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var contentText = output;

    // LFM2 format:
    // <|tool_call_start|>[{"name":"fn","arguments":{...}}]<|tool_call_end|>
    final toolCallRegex = RegExp(
      r'<\|tool_call_start\|>\s*(.*?)\s*<\|tool_call_end\|>',
      dotAll: true,
    );

    final matches = toolCallRegex.allMatches(output);
    for (var i = 0; i < matches.length; i++) {
      final match = matches.elementAt(i);
      try {
        final decoded = jsonDecode(match.group(1)!);
        if (decoded is! List) {
          continue;
        }

        for (final item in decoded) {
          if (item is! Map) {
            continue;
          }
          final toolCall = Map<String, dynamic>.from(item);
          final name = toolCall['name'];
          if (name is! String || name.isEmpty) {
            continue;
          }
          final args = toolCall['arguments'];
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: toolCalls.length,
              id: 'call_${toolCalls.length}',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: name,
                arguments: args is String ? args : jsonEncode(args ?? {}),
              ),
            ),
          );
        }
      } catch (_) {
        // Keep content unchanged when payload is malformed.
      }
      contentText = contentText.replaceAll(match.group(0)!, '');
    }

    final thinking = extractThinking(
      contentText,
      thinkingForcedOpen: thinkingForcedOpen,
    );

    return ChatParseResult(
      content: thinking.content.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return ToolCallGrammarUtils.buildWrappedArrayGrammar(
      tools: tools,
      prefix: '<|tool_call_start|>',
      suffix: '<|tool_call_end|>',
      idKey: 'id',
      allowParallelToolCalls: false,
    );
  }
}
