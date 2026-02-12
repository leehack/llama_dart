import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';

/// Handler for Functionary v3.2 format.
///
/// Tool calls use `>>>name\n{...}` blocks, with `>>>all\n` as a content
/// channel and optional `>>>python\n<raw code>` output.
class FunctionaryV32Handler extends ChatTemplateHandler {
  static final RegExp _tagRegex = RegExp(r'>>>([A-Za-z0-9_]+)\n');
  static final RegExp _startOnlyRegex = RegExp(
    r'^(all\n|python\n|[A-Za-z0-9_]+\n\{)',
  );

  @override
  ChatFormat get format => ChatFormat.functionaryV32;

  @override
  List<String> get additionalStops => ['<|eot_id|>'];

  @override
  List<String> get preservedTokens => const ['<|end_header_id|>'];

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
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<|begin_of_text|>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_text|>',
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
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '>>>')]
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
    if (!text.contains('>>>') && _startOnlyRegex.hasMatch(text)) {
      text = '>>>$text';
    }

    final matches = _tagRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return ChatParseResult(content: output.trim());
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    final contentParts = <String>[];

    if (matches.first.start > 0) {
      final prelude = text.substring(0, matches.first.start).trim();
      if (prelude.isNotEmpty) {
        contentParts.add(prelude);
      }
    }

    for (var i = 0; i < matches.length; i++) {
      final current = matches[i];
      final name = current.group(1)!;
      final bodyStart = current.end;
      final bodyEnd = i + 1 < matches.length
          ? matches[i + 1].start
          : text.length;
      final body = text.substring(bodyStart, bodyEnd).trim();

      if (name == 'all') {
        if (body.isNotEmpty) {
          contentParts.add(body);
        }
        continue;
      }

      if (name == 'python' && !body.startsWith('{')) {
        toolCalls.add(
          LlamaCompletionChunkToolCall(
            index: toolCalls.length,
            id: 'call_${toolCalls.length}',
            type: 'function',
            function: LlamaCompletionChunkFunction(
              name: 'python',
              arguments: jsonEncode({'code': body}),
            ),
          ),
        );
        continue;
      }

      final jsonRange = _extractJsonObject(body);
      if (jsonRange == null) {
        if (isPartial && body.isNotEmpty) {
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: toolCalls.length,
              id: 'call_${toolCalls.length}',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: name,
                arguments: body,
              ),
            ),
          );
        } else if (body.isNotEmpty) {
          contentParts.add('>>>$name\n$body');
        }
        continue;
      }

      final jsonText = body.substring(jsonRange.start, jsonRange.end);
      toolCalls.add(
        LlamaCompletionChunkToolCall(
          index: toolCalls.length,
          id: 'call_${toolCalls.length}',
          type: 'function',
          function: LlamaCompletionChunkFunction(
            name: name,
            arguments: _normalizeArguments(jsonText),
          ),
        ),
      );

      final trailing = body.substring(jsonRange.end).trim();
      if (trailing.isNotEmpty) {
        contentParts.add(trailing);
      }
    }

    return ChatParseResult(
      content: contentParts.join('\n').trim(),
      toolCalls: toolCalls,
    );
  }

  ({int start, int end})? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    if (start == -1) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);

      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (codeUnit == 0x5C) {
          escaped = true;
          continue;
        }
        if (codeUnit == 0x22) {
          inString = false;
        }
        continue;
      }

      if (codeUnit == 0x22) {
        inString = true;
        continue;
      }

      if (codeUnit == 0x7B) {
        depth++;
      } else if (codeUnit == 0x7D) {
        depth--;
        if (depth == 0) {
          return (start: start, end: i + 1);
        }
      }
    }

    return null;
  }

  String _normalizeArguments(String jsonText) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map) {
        return jsonEncode(Map<String, dynamic>.from(decoded));
      }
      return jsonEncode({'value': decoded});
    } catch (_) {
      return jsonText;
    }
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
