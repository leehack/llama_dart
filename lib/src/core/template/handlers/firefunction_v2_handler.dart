import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';

/// Handler for FireFunction v2 templates.
///
/// Tool calls are emitted as a JSON array prefixed with `functools`:
/// `functools[{"name":"tool","arguments":{...}}]`.
class FirefunctionV2Handler extends ChatTemplateHandler {
  static const String _prefix = ' functools[';

  @override
  ChatFormat get format => ChatFormat.firefunctionV2;

  @override
  List<String> get additionalStops => ['<|eot_id|>'];

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
    final toolJson = hasTools
        ? const JsonEncoder.withIndent(
            '  ',
          ).convert(tools.map((tool) => tool.toJson()).toList())
        : '';

    final prompt = template.render({
      'messages': messages.map((m) => m.toJson()).toList(),
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'functions': toolJson,
      'datetime': _formatNowUtc(),
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
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: _prefix)]
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

    final prefixIdx = output.indexOf(_prefix);
    if (prefixIdx == -1) {
      return ChatParseResult(content: output.trim());
    }

    final contentBefore = output.substring(0, prefixIdx).trim();
    final arrayStart = output.indexOf('[', prefixIdx);
    if (arrayStart == -1) {
      return ChatParseResult(content: output.trim());
    }

    var extracted = _extractJsonArray(output, arrayStart);
    if (extracted == null && isPartial) {
      final healed = '${output.substring(arrayStart)}]';
      extracted = _JsonExtraction(json: healed, end: output.length);
    }

    if (extracted == null) {
      return ChatParseResult(content: output.trim());
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    try {
      final decoded = jsonDecode(extracted.json);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) continue;
          final call = Map<String, dynamic>.from(item);
          final name = call['name'] as String?;
          if (name == null || name.isEmpty) continue;

          final rawArguments = call['arguments'] ?? call['parameters'] ?? {};
          final id = call['id']?.toString();
          toolCalls.add(
            LlamaCompletionChunkToolCall(
              index: toolCalls.length,
              id: id ?? 'call_${toolCalls.length}',
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: name,
                arguments: _normalizeArguments(rawArguments),
              ),
            ),
          );
        }
      }
    } catch (_) {
      return ChatParseResult(content: output.trim());
    }

    final trailing = extracted.end < output.length
        ? output.substring(extracted.end).trim()
        : '';
    final mergedContent = [
      if (contentBefore.isNotEmpty) contentBefore,
      if (trailing.isNotEmpty) trailing,
    ].join('\n').trim();

    return ChatParseResult(content: mergedContent, toolCalls: toolCalls);
  }

  String _normalizeArguments(Object? arguments) {
    if (arguments is String) {
      try {
        final decoded = jsonDecode(arguments);
        if (decoded is Map) {
          return jsonEncode(Map<String, dynamic>.from(decoded));
        }
        return jsonEncode({'value': decoded});
      } catch (_) {
        return arguments;
      }
    }

    if (arguments is Map) {
      return jsonEncode(Map<String, dynamic>.from(arguments));
    }

    return jsonEncode(arguments ?? {});
  }

  _JsonExtraction? _extractJsonArray(String input, int startIndex) {
    if (startIndex >= input.length || input.codeUnitAt(startIndex) != 0x5B) {
      return null;
    }

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = startIndex; i < input.length; i++) {
      final codeUnit = input.codeUnitAt(i);

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

      if (codeUnit == 0x5B) {
        depth++;
      } else if (codeUnit == 0x5D) {
        depth--;
        if (depth == 0) {
          return _JsonExtraction(
            json: input.substring(startIndex, i + 1),
            end: i + 1,
          );
        }
      }
    }

    return null;
  }

  String _formatNowUtc() {
    final now = DateTime.now().toUtc();
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    final month = months[now.month - 1];
    final day = twoDigits(now.day);
    final year = now.year;
    final hour = twoDigits(now.hour);
    final minute = twoDigits(now.minute);
    final second = twoDigits(now.second);
    return '$month $day $year $hour:$minute:$second GMT';
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}

class _JsonExtraction {
  final String json;
  final int end;

  const _JsonExtraction({required this.json, required this.end});
}
