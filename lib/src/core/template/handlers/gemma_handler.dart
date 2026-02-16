import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../tool_call_fallback_parser.dart';
import '../tool_call_grammar_utils.dart';

/// Handler for Gemma 3 / Gemma 3n models.
///
/// Uses `<start_of_turn>` / `<end_of_turn>` markers with `developer` and
/// `model` roles. Tool calling is prompt-engineered — the model outputs
/// JSON like `{"tool_call": {"type": "name", "parameters": {...}}}`.
///
/// Gemma 3n also supports multimodal content via `<audio_soft_token>` and
/// `<image_soft_token>` markers in the template.
class GemmaHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.gemma;

  @override
  List<String> get additionalStops => ['<end_of_turn>'];

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
      grammarLazy: false,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      grammarTriggers: const [],
    );
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final trimmed = output.trim();

    if (!parseToolCalls) {
      return ChatParseResult(content: trimmed);
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var contentText = trimmed;

    if (trimmed.contains('"tool_call"')) {
      // Match {"tool_call": { ... }} blocks
      final regex = RegExp(
        r'\{[^{]*"tool_call"\s*:\s*({(?:[^{}]|{(?:[^{}]|{[^{}]*})*})*})\s*\}',
        dotAll: true,
      );

      final matches = regex.allMatches(trimmed);
      for (var i = 0; i < matches.length; i++) {
        try {
          final raw = matches.elementAt(i).group(0)!;
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final toolCall = _toMap(json['tool_call']);
          if (toolCall != null) {
            final name = _extractToolName(toolCall);
            final args = _extractToolArguments(json, toolCall);
            if (name != null) {
              final argsMap = normalizeFallbackToolArguments(
                _toArgumentsObject(args),
              );
              final normalizedName = normalizeFallbackToolName(
                name,
                arguments: argsMap,
              );

              toolCalls.add(
                LlamaCompletionChunkToolCall(
                  index: i,
                  id: 'call_$i',
                  type: 'function',
                  function: LlamaCompletionChunkFunction(
                    name: normalizedName,
                    arguments: jsonEncode(argsMap),
                  ),
                ),
              );
            }
          }
          contentText = contentText.replaceAll(raw, '');
        } catch (_) {}
      }
    }

    return ChatParseResult(content: contentText.trim(), toolCalls: toolCalls);
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return ToolCallGrammarUtils.buildWrappedObjectGrammar(
      tools: tools,
      prefix: '{"tool_call":',
      suffix: '}',
      nameKey: 'name',
      argumentsKey: 'arguments',
    );
  }

  Map<String, dynamic>? _toMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Map<String, dynamic> _toArgumentsObject(Object? raw) {
    if (raw == null) {
      return const <String, dynamic>{};
    }

    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    if (raw is String) {
      return decodeToolArgumentsObject(raw);
    }

    return const <String, dynamic>{};
  }

  String? _extractToolName(Map<String, dynamic> toolCall) {
    const nameKeys = <String>[
      'name',
      'type',
      'code',
      'tool_name',
      'function',
      'tool',
      'toolName',
    ];
    for (final key in nameKeys) {
      final value = toolCall[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    final nestedFunction = _toMap(toolCall['function']);
    final nestedName = nestedFunction?['name'];
    if (nestedName is String && nestedName.trim().isNotEmpty) {
      return nestedName.trim();
    }

    return null;
  }

  Object? _extractToolArguments(
    Map<String, dynamic> root,
    Map<String, dynamic> toolCall,
  ) {
    const argsKeys = <String>[
      'parameters',
      'arguments',
      'args',
      'params',
      'input',
    ];

    for (final key in argsKeys) {
      if (toolCall.containsKey(key) && toolCall[key] != null) {
        return toolCall[key];
      }
    }

    final nestedFunction = _toMap(toolCall['function']);
    if (nestedFunction != null) {
      for (final key in argsKeys) {
        if (nestedFunction.containsKey(key) && nestedFunction[key] != null) {
          return nestedFunction[key];
        }
      }
    }

    final inline = <String, dynamic>{};
    for (final entry in toolCall.entries) {
      if (_isToolCallMetaKey(entry.key)) {
        continue;
      }
      inline[entry.key] = entry.value;
    }
    if (inline.isNotEmpty) {
      return inline;
    }

    final rootInline = <String, dynamic>{};
    for (final entry in root.entries) {
      if (entry.key == 'tool_call') {
        continue;
      }
      rootInline[entry.key] = entry.value;
    }
    if (rootInline.isNotEmpty) {
      return rootInline;
    }

    return null;
  }

  bool _isToolCallMetaKey(String key) {
    const metaKeys = <String>{
      'name',
      'type',
      'code',
      'tool_name',
      'function',
      'tool',
      'toolName',
      'id',
      'call_id',
      'tool_call_id',
      'index',
    };
    return metaKeys.contains(key);
  }
}
