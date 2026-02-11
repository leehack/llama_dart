import 'package:llamadart/src/core/models/chat/chat_role.dart';

import '../models/chat/chat_message.dart';
import 'template_caps.dart';

/// Template workarounds matching llama.cpp's `workaround` namespace.
///
/// These handle known quirks in model templates that need pre-processing
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
      // Merge system content into next message
      final next = result[0];
      result[0] = LlamaChatMessage(
        role: next.role.name,
        content: '${systemMsg.content}\n${next.content}',
      );
    }
    // If system was the only message, it's dropped (matches llama.cpp)

    return result;
  }

  /// Ensures tool_call arguments are JSON objects, not strings.
  ///
  /// Some templates receive arguments as a JSON string; this parses them
  /// into objects. Matches llama.cpp's `workaround::func_args_not_string`.
  static List<Map<String, dynamic>> normalizeToolCallArgs(
    List<Map<String, dynamic>> messages,
  ) {
    // This operates on the JSON-serialized message list that goes into Jinja
    for (final message in messages) {
      final toolCalls = message['tool_calls'];
      if (toolCalls is List) {
        for (final toolCall in toolCalls) {
          if (toolCall is Map<String, dynamic>) {
            final function = toolCall['function'];
            if (function is Map<String, dynamic>) {
              final args = function['arguments'];
              if (args is String) {
                try {
                  // ignore: avoid_dynamic_calls
                  function['arguments'] = (args as dynamic) is String
                      ? args
                      : args;
                } catch (_) {
                  // Keep as string if parsing fails
                }
              }
            }
          }
        }
      }
    }
    return messages;
  }
}
