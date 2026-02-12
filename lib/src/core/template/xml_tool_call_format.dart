import 'dart:convert';

import '../models/chat/completion_chunk.dart';
import 'chat_parse_result.dart';
import 'thinking_utils.dart';

/// Describes the XML-style tool call format used by several models.
///
/// Matches llama.cpp's `xml_tool_call_format` struct. Shared by:
/// MiniMax M2, Qwen3 Coder XML, Kimi K2, Apriel, Seed OSS.
class XmlToolCallFormat {
  /// Opening scope tag (e.g., `<minimax:tool_call>`).
  final String scopeStart;

  /// Start of a tool call (e.g., `<invoke name="`).
  final String toolStart;

  /// Separator between tool name and arguments (e.g., `">`).
  final String toolSep;

  /// Start of a key (e.g., `<parameter name="`).
  final String keyStart;

  /// Separator between key and value (e.g., `">`).
  final String keyValSep;

  /// End of a value (e.g., `</parameter>`).
  final String valEnd;

  /// End of a tool call (e.g., `</invoke>`).
  final String toolEnd;

  /// Closing scope tag (e.g., `</minimax:tool_call>`).
  final String scopeEnd;

  /// Whether argument values are raw strings (true) or JSON (false).
  final bool rawArgval;

  /// Whether to trim whitespace from raw argument values.
  final bool trimRawArgval;

  /// Override for the last value's end marker.
  final String? lastValEnd;

  /// Override for the last tool's end marker.
  final String? lastToolEnd;

  /// Whether tool calls can appear inside thinking blocks.
  final bool allowToolcallInThink;

  /// Creates a [XmlToolCallFormat] definition.
  const XmlToolCallFormat({
    required this.scopeStart,
    required this.toolStart,
    required this.toolSep,
    required this.keyStart,
    required this.keyValSep,
    required this.valEnd,
    required this.toolEnd,
    required this.scopeEnd,
    this.rawArgval = true,
    this.trimRawArgval = false,
    this.lastValEnd,
    this.lastToolEnd,
    this.allowToolcallInThink = false,
  });

  /// Standard XML format (e.g. Qwen 2.5/3 Coder).
  static const qwen3Coder = XmlToolCallFormat(
    scopeStart: '',
    toolStart: '<function=',
    toolSep: '>',
    keyStart: '<parameter=',
    keyValSep: '>',
    valEnd: '</parameter>',
    toolEnd: '</function>',
    scopeEnd: '',
  );

  /// Kimi K2 format.
  static const kimiK2 = XmlToolCallFormat(
    scopeStart: '<|tool_calls_section_begin|>',
    toolStart: '<tool_code>',
    toolSep: '\n',
    keyStart: '<',
    keyValSep: '>',
    valEnd: '</',
    toolEnd: '</tool_code>',
    scopeEnd: '<|tool_calls_section_end|>',
  );

  /// MiniMax M2 format.
  static const minimaxM2 = XmlToolCallFormat(
    scopeStart: '<minimax:tool_call>',
    toolStart: '<invoke name="',
    toolSep: '">',
    keyStart: '<parameter name="',
    keyValSep: '">',
    valEnd: '</parameter>',
    toolEnd: '</invoke>',
    scopeEnd: '</minimax:tool_call>',
  );

  /// Seed-OSS format.
  static const seedOss = XmlToolCallFormat(
    scopeStart: '<seed:tool_call>',
    toolStart: '<function=',
    toolSep: '>',
    keyStart: '<parameter=',
    keyValSep: '>',
    valEnd: '</parameter>',
    toolEnd: '</function>',
    scopeEnd: '</seed:tool_call>',
  );

  /// Apriel 1.5 format.
  static const apriel15 = XmlToolCallFormat(
    scopeStart: '<tool_calls>[',
    toolStart: '{"name": "',
    toolSep: '", "arguments": {',
    keyStart: '"',
    keyValSep: '": ',
    valEnd: ', ',
    toolEnd: '}, ',
    scopeEnd: ']</tool_calls>',
    rawArgval: false,
    lastValEnd: '',
    lastToolEnd: '}',
  );

  /// Xiaomi MiMo format.
  static const xiaomiMimo = XmlToolCallFormat(
    scopeStart: '',
    toolStart: '<tool_call>\n{"name": "',
    toolSep: '", "arguments": {',
    keyStart: '"',
    keyValSep: '": ',
    valEnd: ', ',
    toolEnd: '}\n</tool_call>',
    scopeEnd: '',
    rawArgval: false,
    lastValEnd: '',
  );

  /// Generic fallback XML format.
  static const generic = XmlToolCallFormat(
    scopeStart: '',
    toolStart: '<tool_code>',
    toolSep: '\n',
    keyStart: '<',
    keyValSep: '>',
    valEnd: '</',
    toolEnd: '</tool_code>',
    scopeEnd: '',
  );
}

/// Parses XML-style tool calls with optional reasoning.
///
/// Matches llama.cpp's `consume_reasoning_with_xml_tool_calls`.
ChatParseResult parseXmlToolCalls(
  String input,
  XmlToolCallFormat format, {
  String startThink = '<think>',
  String endThink = '</think>',
  bool parseToolCalls = true,
}) {
  String? reasoning;
  var content = input;

  // Extract thinking/reasoning first
  final thinkResult = extractThinking(
    content,
    startTag: startThink,
    endTag: endThink,
  );
  reasoning = thinkResult.reasoning;
  content = thinkResult.content;

  if (!parseToolCalls) {
    return ChatParseResult(
      content: content.trim(),
      reasoningContent: reasoning,
    );
  }

  final toolCalls = <LlamaCompletionChunkToolCall>[];
  var remainingContent = content;

  // Find scope start
  final scopeIdx = format.scopeStart.isEmpty
      ? 0
      : content.indexOf(format.scopeStart);

  if (scopeIdx == -1) {
    return ChatParseResult(
      content: content.trim(),
      reasoningContent: reasoning,
    );
  }

  if (format.scopeStart.isNotEmpty) {
    remainingContent = content.substring(0, scopeIdx);
    content = content.substring(scopeIdx + format.scopeStart.length);
  }

  // Parse individual tool calls
  var callIndex = 0;
  var pos = 0;

  while (pos < content.length) {
    final toolIdx = content.indexOf(format.toolStart, pos);
    if (toolIdx == -1) break;

    // Extract tool name
    final nameStart = toolIdx + format.toolStart.length;
    final sepIdx = content.indexOf(format.toolSep, nameStart);
    if (sepIdx == -1) break;

    final name = content.substring(nameStart, sepIdx).trim();
    pos = sepIdx + format.toolSep.length;

    // Extract key-value pairs as arguments
    final args = <String, dynamic>{};
    var lastKey = '';

    while (pos < content.length) {
      // Check for tool end
      final effectiveToolEnd = (callIndex > 0 || format.lastToolEnd == null)
          ? format.toolEnd
          : format.lastToolEnd!;

      if (content.startsWith(effectiveToolEnd, pos) ||
          content.startsWith(format.toolEnd, pos)) {
        pos += format.toolEnd.length;
        break;
      }

      // Try to find next key
      final keyIdx = content.indexOf(format.keyStart, pos);
      if (keyIdx == -1) break;

      final keyNameStart = keyIdx + format.keyStart.length;
      final keyNameEnd = content.indexOf(format.keyValSep, keyNameStart);
      if (keyNameEnd == -1) break;

      final key = content.substring(keyNameStart, keyNameEnd).trim();
      lastKey = key;
      pos = keyNameEnd + format.keyValSep.length;

      // Find value end
      final effectiveValEnd = format.lastValEnd != null && lastKey == key
          ? format
                .valEnd // Use normal valEnd during iteration
          : format.valEnd;

      final valEndIdx = content.indexOf(effectiveValEnd, pos);
      if (valEndIdx == -1) {
        // Last value — take rest up to tool end
        final toolEndIdx = content.indexOf(format.toolEnd, pos);
        if (toolEndIdx != -1) {
          final rawValue = content.substring(pos, toolEndIdx);
          _setArgValue(args, key, rawValue, format);
          pos = toolEndIdx + format.toolEnd.length;
        }
        break;
      }

      final rawValue = content.substring(pos, valEndIdx);
      _setArgValue(args, key, rawValue, format);
      pos = valEndIdx + effectiveValEnd.length;
    }

    toolCalls.add(
      LlamaCompletionChunkToolCall(
        index: callIndex,
        id: 'call_$callIndex',
        type: 'function',
        function: LlamaCompletionChunkFunction(
          name: name,
          arguments: jsonEncode(args),
        ),
      ),
    );
    callIndex++;
  }

  // Find scope end and append any trailing content
  if (format.scopeEnd.isNotEmpty) {
    final scopeEndIdx = content.indexOf(format.scopeEnd, pos);
    if (scopeEndIdx != -1) {
      final trailing = content.substring(scopeEndIdx + format.scopeEnd.length);
      if (trailing.trim().isNotEmpty) {
        remainingContent += trailing;
      }
    }
  }

  return ChatParseResult(
    content: remainingContent.trim(),
    reasoningContent: reasoning,
    toolCalls: toolCalls,
  );
}

void _setArgValue(
  Map<String, dynamic> args,
  String key,
  String rawValue,
  XmlToolCallFormat format,
) {
  var value = rawValue;
  if (format.trimRawArgval) {
    value = value.trim();
  }

  if (format.rawArgval) {
    // Try to parse as JSON value, fall back to string
    try {
      args[key] = jsonDecode(value);
    } catch (_) {
      args[key] = value;
    }
  } else {
    // Value is already JSON
    try {
      args[key] = jsonDecode(value);
    } catch (_) {
      args[key] = value;
    }
  }
}
