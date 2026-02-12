import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';

/// Handler for GPT-OSS format.
///
/// GPT-OSS responses are structured in `<|start|>assistant` message frames with
/// channel headers (`analysis`, `commentary`, `final`) and optional
/// `to=functions.<name>` tool-routing headers.
class GptOssHandler extends ChatTemplateHandler {
  static const String _assistantStart = '<|start|>assistant';
  static const String _messageTag = '<|message|>';
  static const String _endTag = '<|end|>';

  @override
  ChatFormat get format => ChatFormat.gptOss;

  @override
  List<String> get additionalStops => [];

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    final renderedMessages = messages.map((m) {
      final json = m.toJson();
      final reasoning = json['reasoning_content'];
      final toolCalls = json['tool_calls'];
      if (reasoning is String && toolCalls is List && toolCalls.isNotEmpty) {
        json['thinking'] = reasoning;
      }
      return json;
    }).toList();

    final template = Template(templateSource);
    final prompt = template.render({
      'messages': renderedMessages,
      'add_generation_prompt': addAssistant,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
      'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
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
    );
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final reasoningParts = <String>[];
    final contentParts = <String>[];
    final toolCalls = <LlamaCompletionChunkToolCall>[];

    var cursor = 0;
    while (cursor < output.length) {
      final start = output.indexOf(_assistantStart, cursor);
      if (start == -1) {
        final trailing = output.substring(cursor).trim();
        if (trailing.isNotEmpty) {
          contentParts.add(trailing);
        }
        break;
      }

      if (start > cursor) {
        final prelude = output.substring(cursor, start).trim();
        if (prelude.isNotEmpty) {
          contentParts.add(prelude);
        }
      }

      final headerStart = start + _assistantStart.length;
      final messageIdx = output.indexOf(_messageTag, headerStart);
      if (messageIdx == -1) {
        final trailing = output.substring(start).trim();
        if (trailing.isNotEmpty) {
          contentParts.add(trailing);
        }
        break;
      }

      final header = output.substring(headerStart, messageIdx);
      final bodyStart = messageIdx + _messageTag.length;
      final endIdx = output.indexOf(_endTag, bodyStart);

      final body = endIdx == -1
          ? output.substring(bodyStart)
          : output.substring(bodyStart, endIdx);

      _consumeFrame(
        header: header,
        body: body,
        parseToolCalls: parseToolCalls,
        reasoningParts: reasoningParts,
        contentParts: contentParts,
        toolCalls: toolCalls,
      );

      if (endIdx == -1) {
        break;
      }
      cursor = endIdx + _endTag.length;
    }

    return ChatParseResult(
      content: contentParts.join('\n').trim(),
      reasoningContent: reasoningParts.isEmpty
          ? null
          : reasoningParts.join('\n'),
      toolCalls: toolCalls,
    );
  }

  void _consumeFrame({
    required String header,
    required String body,
    required bool parseToolCalls,
    required List<String> reasoningParts,
    required List<String> contentParts,
    required List<LlamaCompletionChunkToolCall> toolCalls,
  }) {
    final normalizedBody = body.trim();
    if (normalizedBody.isEmpty) {
      return;
    }

    final channel = _extractChannel(header);
    final functionName = _extractFunctionRecipient(header);

    if (functionName != null && parseToolCalls) {
      toolCalls.add(
        LlamaCompletionChunkToolCall(
          index: toolCalls.length,
          id: 'call_${toolCalls.length}',
          type: 'function',
          function: LlamaCompletionChunkFunction(
            name: functionName,
            arguments: _normalizeArguments(normalizedBody),
          ),
        ),
      );
      return;
    }

    if (channel == 'analysis') {
      reasoningParts.add(normalizedBody);
      return;
    }

    if (channel == 'final' || channel == 'commentary') {
      contentParts.add(normalizedBody);
      return;
    }

    contentParts.add(normalizedBody);
  }

  String? _extractChannel(String header) {
    final match = RegExp(r'<\|channel\|>([a-zA-Z0-9_-]+)').firstMatch(header);
    return match?.group(1);
  }

  String? _extractFunctionRecipient(String header) {
    final match = RegExp(r'to=functions\.([^<\s]+)').firstMatch(header);
    return match?.group(1);
  }

  String _normalizeArguments(String rawBody) {
    final value = rawBody.trim();
    if (value.isEmpty) {
      return '{}';
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return jsonEncode(Map<String, dynamic>.from(decoded));
      }
      return jsonEncode({'value': decoded});
    } catch (_) {
      return value;
    }
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
