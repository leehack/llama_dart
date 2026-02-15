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
import '../xml_tool_call_format.dart';

/// Handler for GLM 4.5 format.
///
/// Uses `<|observation|>` as a stop token for tool call observation.
/// Tool call format:
/// `<tool_call>func_name<arg_key>key</arg_key><arg_value>value</arg_value></tool_call>`
///
/// Supports `<think>`/`</think>` for reasoning.
class Glm45Handler extends ChatTemplateHandler {
  static final RegExp _toolCallBlockPattern = RegExp(
    r'<tool_call>\s*([a-zA-Z0-9_]+)\s*([\s\S]*?)</tool_call>',
    caseSensitive: false,
  );
  static final RegExp _argPairPattern = RegExp(
    r'<arg_key>\s*([\s\S]*?)\s*</arg_key>\s*<arg_value>\s*([\s\S]*?)\s*</arg_value>',
    caseSensitive: false,
  );
  static const XmlToolCallFormat _glm45ToolCallFormat = XmlToolCallFormat(
    scopeStart: '',
    toolStart: '<tool_call>',
    toolSep: '\n',
    keyStart: '<arg_key>',
    keyValSep: '</arg_key><arg_value>',
    valEnd: '</arg_value>',
    toolEnd: '</tool_call>',
    scopeEnd: '',
  );

  @override
  ChatFormat get format => ChatFormat.glm45;

  @override
  List<String> get additionalStops => ['<|user|>', '<|observation|>'];

  @override
  List<String> get preservedTokens => const [
    '<|endoftext|>',
    '[MASK]',
    '[gMASK]',
    '[sMASK]',
    '<sop>',
    '<eop>',
    '<|system|>',
    '<|user|>',
    '<|assistant|>',
    '<|observation|>',
    '<|begin_of_image|>',
    '<|end_of_image|>',
    '<|begin_of_video|>',
    '<|end_of_video|>',
    '<|begin_of_audio|>',
    '<|end_of_audio|>',
    '<|begin_of_transcription|>',
    '<|end_of_transcription|>',
    '<|code_prefix|>',
    '<|code_middle|>',
    '<|code_suffix|>',
    '/nothink',
    '<think>',
    '</think>',
    '<tool_call>',
    '</tool_call>',
    '<arg_key>',
    '</arg_key>',
    '<arg_value>',
    '</arg_value>',
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
    var prompt = template.render({
      'messages': messages.map((m) => m.toJson()).toList(),
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '[gMASK]<sop>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|user|>',
    });

    prompt = _normalizePromptWhitespace(prompt);

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
    // GLM 4.5 tool calls are wrapped in <tool_call> XML blocks.
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
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<tool_call>')]
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

    final extractedFromContent = _extractToolCalls(text);
    final toolCalls = <LlamaCompletionChunkToolCall>[
      ...extractedFromContent.toolCalls,
    ];
    var contentText = extractedFromContent.remainingContent;

    final reasoning = thinking.reasoning;
    if (toolCalls.isEmpty && reasoning != null && reasoning.trim().isNotEmpty) {
      final extractedFromReasoning = _extractToolCalls(reasoning);
      toolCalls.addAll(extractedFromReasoning.toolCalls);
      if (contentText.trim().isEmpty &&
          extractedFromReasoning.remainingContent.trim().isNotEmpty) {
        contentText = extractedFromReasoning.remainingContent;
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
    return buildXmlToolCallGrammar(tools, _glm45ToolCallFormat);
  }

  Object? _decodeArgValue(String value) {
    if (value.isEmpty) {
      return '';
    }

    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  _ExtractedToolCalls _extractToolCalls(String input) {
    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var remaining = input;

    final matches = _toolCallBlockPattern.allMatches(input);
    for (final match in matches) {
      final toolName = (match.group(1) ?? '').trim();
      if (toolName.isEmpty) {
        continue;
      }

      final args = <String, dynamic>{};
      final argsBlock = match.group(2) ?? '';
      for (final argMatch in _argPairPattern.allMatches(argsBlock)) {
        final key = (argMatch.group(1) ?? '').trim();
        final rawValue = (argMatch.group(2) ?? '').trim();
        if (key.isEmpty) {
          continue;
        }
        args[key] = _decodeArgValue(rawValue);
      }

      final index = toolCalls.length;
      toolCalls.add(
        LlamaCompletionChunkToolCall(
          index: index,
          id: 'call_$index',
          type: 'function',
          function: LlamaCompletionChunkFunction(
            name: toolName,
            arguments: jsonEncode(args),
          ),
        ),
      );

      final fullBlock = match.group(0);
      if (fullBlock != null && fullBlock.isNotEmpty) {
        remaining = remaining.replaceFirst(fullBlock, '');
      }
    }

    return _ExtractedToolCalls(
      toolCalls: toolCalls,
      remainingContent: remaining,
    );
  }

  String _normalizePromptWhitespace(String input) {
    var output = input.replaceAll(RegExp(r'^\s+'), '');

    const token =
        r'(\[gMASK\]|\[MASK\]|\[sMASK\]|<sop>|<eop>|<\|system\|>|<\|user\|>|<\|assistant\|>|<\|observation\|>|<think>|</think>)';
    final adjacentTokenSpacing = RegExp('$token[ \t\r\n]+$token');

    while (true) {
      final normalized = output.replaceAllMapped(
        adjacentTokenSpacing,
        (match) => '${match.group(1)}${match.group(2)}',
      );
      if (normalized == output) {
        break;
      }
      output = normalized;
    }

    return output;
  }
}

class _ExtractedToolCalls {
  final List<LlamaCompletionChunkToolCall> toolCalls;
  final String remainingContent;

  const _ExtractedToolCalls({
    required this.toolCalls,
    required this.remainingContent,
  });
}
