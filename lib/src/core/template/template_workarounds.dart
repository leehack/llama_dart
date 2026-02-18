import 'dart:convert';

import '../models/chat/chat_message.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/content_part.dart';
import 'chat_format.dart';
import 'template_caps.dart';

/// Template workarounds matching llama.cpp's `workaround` namespace.
///
/// These handle known quirks in model templates that need preprocessing
/// before rendering.
class TemplateWorkarounds {
  /// If the template doesn't support system role, merges system messages
  /// into the next user message.
  ///
  /// Matches llama.cpp's `workaround::system_message_not_supported`.
  static List<LlamaChatMessage> applySystemMessageWorkaround(
    List<LlamaChatMessage> messages,
    TemplateCaps caps,
  ) {
    if (caps.supportsSystemRole) return messages;
    if (messages.isEmpty) return messages;
    if (messages.first.role != LlamaChatRole.system) return messages;

    final result = List<LlamaChatMessage>.from(messages);
    final systemMsg = result.removeAt(0);

    if (result.isNotEmpty) {
      final next = result[0];
      result[0] = LlamaChatMessage.fromText(
        role: next.role,
        text: '${systemMsg.content}\n${next.content}',
      );
    }

    return result;
  }

  /// Applies format-specific workaround chain and returns transformed messages.
  static List<LlamaChatMessage> applyFormatWorkarounds(
    List<LlamaChatMessage> messages,
    ChatFormat format,
  ) {
    final jsonMessages = messages.map((m) => m.toJson()).toList();
    var changed = false;

    if (_formatsNeedFuncArgsNormalization.contains(format)) {
      normalizeToolCallArgs(jsonMessages);
      changed = true;
    }

    if (_formatsNeedGenericSchema.contains(format)) {
      useGenericSchema(jsonMessages);
      changed = true;
    }

    if (_formatsNeedMoveToolCallsToContent.contains(format)) {
      moveToolCallsToContent(jsonMessages);
      changed = true;
    }

    if (!changed) {
      return messages;
    }

    return _messagesFromJson(jsonMessages);
  }

  /// Ensures tool call arguments are JSON objects, not strings.
  ///
  /// Matches llama.cpp's `workaround::func_args_not_string`.
  static void normalizeToolCallArgs(List<Map<String, dynamic>> messages) {
    for (final message in messages) {
      final toolCalls = message['tool_calls'];
      if (toolCalls is! List) continue;

      for (final item in toolCalls) {
        if (item is! Map<String, dynamic>) continue;

        if (item['function'] is Map) {
          final function = Map<String, dynamic>.from(item['function'] as Map);
          if (function.containsKey('arguments')) {
            function['arguments'] = _argumentsToObject(function['arguments']);
          }
          item['function'] = function;
          continue;
        }

        if (item.containsKey('arguments')) {
          item['arguments'] = _argumentsToObject(item['arguments']);
        }
      }
    }
  }

  /// Converts OpenAI-style tool call schema into generic short schema.
  ///
  /// Matches llama.cpp's `workaround::use_generic_schema`.
  static void useGenericSchema(List<Map<String, dynamic>> messages) {
    for (final message in messages) {
      final toolCalls = message['tool_calls'];
      if (toolCalls is! List) continue;

      for (var i = 0; i < toolCalls.length; i++) {
        final call = toolCalls[i];
        if (call is! Map<String, dynamic>) continue;

        final type = call['type'];
        final function = call['function'];
        if (type != 'function' || function is! Map<String, dynamic>) {
          continue;
        }

        Object? name;
        Object? arguments;
        Object? id;
        if (function.containsKey('name')) {
          name = function['name'];
        }
        if (function.containsKey('arguments')) {
          arguments = function['arguments'];
        }
        if (call.containsKey('id')) {
          id = call['id'];
        }

        call.clear();
        if (name != null) {
          call['name'] = name;
        }
        if (arguments != null) {
          call['arguments'] = arguments;
        }
        if (id != null) {
          call['id'] = id;
        }
      }
    }
  }

  /// Moves tool calls into message content as JSON string.
  ///
  /// Matches llama.cpp's `workaround::move_tool_calls_to_content`.
  static void moveToolCallsToContent(
    List<Map<String, dynamic>> messages, {
    int indentSpaces = 2,
  }) {
    for (final message in messages) {
      final toolCalls = message['tool_calls'];
      if (toolCalls is! List) continue;

      final currentContent = message['content'];
      final contentText = currentContent == null
          ? ''
          : currentContent.toString();
      final payload = {'tool_calls': toolCalls};
      final toolCallsJson = indentSpaces <= 0
          ? jsonEncode(payload)
          : JsonEncoder.withIndent(' ' * indentSpaces).convert(payload);

      message['content'] = '$contentText$toolCallsJson';
      message.remove('tool_calls');
    }
  }

  static Map<String, dynamic> _argumentsToObject(Object? args) {
    if (args is Map<String, dynamic>) {
      return args;
    }

    if (args is Map) {
      return Map<String, dynamic>.from(args);
    }

    if (args is String) {
      final decoded = jsonDecode(args);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      throw const FormatException('Tool call arguments must be a JSON object.');
    }

    if (args == null) {
      return <String, dynamic>{};
    }

    throw FormatException(
      'Unsupported tool call argument type: ${args.runtimeType}',
    );
  }

  static List<LlamaChatMessage> _messagesFromJson(
    List<Map<String, dynamic>> messages,
  ) {
    return messages.map(_messageFromJson).toList();
  }

  static LlamaChatMessage _messageFromJson(Map<String, dynamic> message) {
    final role = _parseRole(message['role'] as String? ?? 'user');
    final parts = <LlamaContentPart>[];

    final reasoning = message['reasoning_content'];
    if (reasoning is String && reasoning.isNotEmpty) {
      parts.add(LlamaThinkingContent(reasoning));
    }

    final toolCalls = message['tool_calls'];
    if (toolCalls is List) {
      for (final item in toolCalls) {
        if (item is! Map<String, dynamic>) continue;

        final function = item['function'];
        final name =
            item['name'] as String? ??
            (function is Map<String, dynamic>
                ? function['name'] as String?
                : null);
        final arguments =
            item['arguments'] ??
            (function is Map<String, dynamic> ? function['arguments'] : null);
        if (name == null) continue;

        final argObject = _argumentsToObject(arguments);
        final rawJson = arguments is String ? arguments : jsonEncode(argObject);

        parts.add(
          LlamaToolCallContent(
            id: item['id'] as String?,
            name: name,
            arguments: argObject,
            rawJson: rawJson,
          ),
        );
      }
    }

    final content = message['content'];
    if (role == LlamaChatRole.tool) {
      parts.add(
        LlamaToolResultContent(
          id: message['tool_call_id'] as String?,
          name: message['name'] as String? ?? 'tool',
          result: content,
        ),
      );
    } else {
      final text = _extractTextContent(content);
      if (text.isNotEmpty) {
        parts.add(LlamaTextContent(text));
      }
    }

    if (parts.isEmpty) {
      return LlamaChatMessage.fromText(role: role, text: '');
    }

    return LlamaChatMessage.withContent(role: role, content: parts);
  }

  static String _extractTextContent(Object? content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is! List) return content.toString();

    final buffer = StringBuffer();
    for (final item in content) {
      if (item is Map<String, dynamic> && item['type'] == 'text') {
        final text = item['text'];
        if (text is String) {
          buffer.write(text);
        }
      }
    }
    return buffer.toString();
  }

  static LlamaChatRole _parseRole(String role) {
    switch (role) {
      case 'system':
        return LlamaChatRole.system;
      case 'assistant':
        return LlamaChatRole.assistant;
      case 'tool':
        return LlamaChatRole.tool;
      case 'user':
      default:
        return LlamaChatRole.user;
    }
  }

  static const Set<ChatFormat> _formatsNeedFuncArgsNormalization = {
    ChatFormat.commandR7B,
    ChatFormat.granite,
    ChatFormat.glm45,
    ChatFormat.qwen3CoderXml,
    ChatFormat.minimaxM2,
    ChatFormat.seedOss,
    ChatFormat.llama3,
    ChatFormat.llama3BuiltinTools,
    ChatFormat.mistralNemo,
    ChatFormat.generic,
  };

  static const Set<ChatFormat> _formatsNeedGenericSchema = {
    ChatFormat.granite,
    ChatFormat.generic,
  };

  static const Set<ChatFormat> _formatsNeedMoveToolCallsToContent = {
    ChatFormat.granite,
    ChatFormat.generic,
  };
}
