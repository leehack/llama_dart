import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../grammar/json_schema_converter.dart';
import '../../models/chat/chat_role.dart';
import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../tool_call_fallback_parser.dart';
import '../thinking_utils.dart';

/// Handler for DeepSeek V3.1 format.
///
/// Similar to Hermes with `<tool_call>` tags but uses prefix-based thinking
/// and `<|end_of_sentence|>` stop token.
class DeepseekV3Handler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.deepseekV3;

  @override
  List<String> get additionalStops => ['<｜end▁of▁sentence｜>'];

  @override
  List<String> get preservedTokens => const [
    '<think>',
    '</think>',
    '<｜tool▁calls▁begin｜>',
    '<｜tool▁call▁begin｜>',
    '<｜tool▁sep｜>',
    '<｜tool▁call▁end｜>',
    '<｜tool▁calls▁end｜>',
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
    final bosToken =
        metadata['tokenizer.ggml.bos_token'] ?? '<|begin_of_sentence|>';
    final eosToken =
        metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_sentence|>';

    // Prepend bos_token to the first system message if it exists
    final modifiedMessages = messages.map((m) {
      if (m.role == LlamaChatRole.system && m == messages.first) {
        return m.copyWith(content: '$bosToken${m.content}');
      }
      return m;
    }).toList();

    var prompt = template.render({
      'messages': modifiedMessages.map((m) => m.toJson()).toList(),
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'bos_token': bosToken,
      'eos_token': eosToken,
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
    final triggerPattern = thinkingForcedOpen
        ? r'[\s\S]*?(</think>\s*)(<｜tool▁calls▁begin｜>|<｜tool_calls_begin｜>|<｜tool calls begin｜>|<｜tool\\_calls\\_begin｜>|<｜tool▁calls｜>)[\s\S]*'
        : r'(?:<think>[\s\S]*?</think>\s*)?(<｜tool▁calls▁begin｜>|<｜tool_calls_begin｜>|<｜tool calls begin｜>|<｜tool\\_calls\\_begin｜>|<｜tool▁calls｜>)[\s\S]*';
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
          ? [GrammarTrigger(type: 3, value: triggerPattern)]
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

    final toolsBlockRegex = RegExp(
      r'(<｜tool▁calls▁begin｜>|<｜tool_calls_begin｜>|<｜tool calls begin｜>|<｜tool\\_calls\\_begin｜>|<｜tool▁calls｜>)([\s\S]*?)<｜tool▁calls▁end｜>',
      dotAll: true,
    );
    final blockMatch = toolsBlockRegex.firstMatch(text);
    if (blockMatch != null) {
      contentText = text.substring(0, blockMatch.start).trim();

      final singleCallRegex = RegExp(
        r'<｜tool▁call▁begin｜>(.*?)<｜tool▁call▁end｜>',
        dotAll: true,
      );
      final callMatches = singleCallRegex.allMatches(blockMatch.group(2)!);
      for (var i = 0; i < callMatches.length; i++) {
        final callContent = callMatches.elementAt(i).group(1)!.trim();
        final sepIdx = callContent.indexOf('<｜tool▁sep｜>');
        if (sepIdx == -1) {
          continue;
        }

        var toolName = callContent.substring(0, sepIdx).trim();
        final payload = callContent
            .substring(sepIdx + '<｜tool▁sep｜>'.length)
            .trim();
        if (_isPlaceholderToolName(toolName)) {
          final extractedName = _extractToolNameFromPayload(payload);
          if (extractedName != null && extractedName.isNotEmpty) {
            toolName = extractedName;
          }
        }

        var arguments = _extractArgumentsFromPayload(payload);
        arguments = normalizeFallbackToolArguments(arguments);
        toolName = normalizeFallbackToolName(toolName, arguments: arguments);

        if (toolName.isEmpty) {
          continue;
        }

        toolCalls.add(
          LlamaCompletionChunkToolCall(
            index: i,
            id: 'call_$i',
            type: 'function',
            function: LlamaCompletionChunkFunction(
              name: toolName,
              arguments: jsonEncode(arguments),
            ),
          ),
        );
      }
    } else {
      final legacyToolCallRegex = RegExp(
        r'<tool_call>(.*?)</tool_call>',
        dotAll: true,
      );
      final legacyMatches = legacyToolCallRegex
          .allMatches(text)
          .toList(growable: false);
      if (legacyMatches.isNotEmpty) {
        contentText = text.substring(0, legacyMatches.first.start).trim();
      }
      for (var i = 0; i < legacyMatches.length; i++) {
        final rawJson = legacyMatches[i].group(1)?.trim();
        if (rawJson == null || rawJson.isEmpty) {
          continue;
        }
        try {
          final decoded = jsonDecode(rawJson);
          if (decoded is! Map<String, dynamic>) {
            continue;
          }
          final name = decoded['name'];
          final arguments = decoded['arguments'];
          if (name is! String || name.isEmpty) {
            continue;
          }
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: i,
              id: 'call_$i',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: name,
                arguments: arguments is String
                    ? arguments
                    : jsonEncode(arguments),
              ),
            ),
          );
        } catch (_) {
          // Ignore malformed tool calls.
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
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final converter = JsonSchemaConverter();
    final toolRuleNames = <String>[];

    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i];
      final schema = tool.toJsonSchema();
      converter.resolveRefs(schema, schema);
      final argsRule = converter.visit(schema, 'tool-$i-args');

      final toolRuleName = 'tool-$i-call';
      final prefix = _literal('${tool.name}<｜tool▁sep｜>');
      final suffix = _literal('<｜tool▁call▁end｜>');
      converter.rules[toolRuleName] =
          '( "<｜tool▁call▁begin｜>" )? $prefix $argsRule $suffix';
      toolRuleNames.add(toolRuleName);
    }

    const rootRule = '( "</think>" space )? tool-calls';
    const toolCallsRule =
        '( "<｜tool▁calls▁begin｜>" | "<｜tool_calls_begin｜>" | "<｜tool calls begin｜>" | "<｜tool\\\\_calls\\\\_begin｜>" | "<｜tool▁calls｜>" ) space tool-call+ "<｜tool▁calls▁end｜>" space';
    final toolCallRule = toolRuleNames.join(' | ');

    final buffer = StringBuffer()
      ..writeln('root ::= $rootRule')
      ..writeln('tool-calls ::= $toolCallsRule')
      ..writeln('tool-call ::= $toolCallRule');

    final otherRules = converter.rules.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in otherRules) {
      if (entry.key == 'root' ||
          entry.key == 'tool-calls' ||
          entry.key == 'tool-call') {
        continue;
      }
      buffer.writeln('${entry.key} ::= ${entry.value}');
    }

    return buffer.toString();
  }

  String _literal(String value) {
    final escaped = value
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return '"$escaped"';
  }

  Map<String, dynamic> _extractArgumentsFromPayload(String payload) {
    if (payload.isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      if (decoded is String) {
        return decodeToolArgumentsObject(decoded);
      }
    } catch (_) {
      // Fall through to looser extractors.
    }

    final extractedObject = _extractJsonObject(payload);
    if (extractedObject != null) {
      return extractedObject;
    }

    return const <String, dynamic>{};
  }

  bool _isPlaceholderToolName(String name) {
    return name == 'function' || name == 'call' || name == 'tool';
  }

  String? _extractToolNameFromPayload(String payload) {
    if (payload.isEmpty) {
      return null;
    }

    final nameMatch = RegExp(
      r'^([A-Za-z_][A-Za-z0-9_\.-]*)',
    ).firstMatch(payload);
    return nameMatch?.group(1);
  }

  Map<String, dynamic>? _extractJsonObject(String payload) {
    if (payload.isEmpty) {
      return null;
    }

    final objectMatch = RegExp(r'(\{[\s\S]*?\})').firstMatch(payload);
    if (objectMatch == null) {
      return null;
    }

    final rawObject = objectMatch.group(1);
    if (rawObject == null || rawObject.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawObject);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}
