import 'dart:convert';
import 'package:llamadart/llamadart.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isInfo; // Non-conversation informational message
  final DateTime timestamp;
  final List<LlamaContentPart>? parts;
  final List<String> debugBadges;
  final LlamaChatRole? role;
  int? tokenCount; // Cache token count for sliding window optimization

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isInfo = false,
    this.parts,
    this.debugBadges = const [],
    this.role,
    DateTime? timestamp,
    this.tokenCount,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Derived property to check if this message is a tool call.
  bool get isToolCall {
    // 1. Explicit tool call part (best)
    if (parts?.any((p) => p is LlamaToolCallContent) ?? false) return true;

    // 2. Assistant role with JSON content (streaming or legacy fallback)
    if (role == LlamaChatRole.assistant) {
      final trimmed = text.trim();
      return trimmed.startsWith('{') || trimmed.startsWith('[{');
    }

    return false;
  }

  /// Derived property to get thinking content if present.
  String? get thinkingText {
    final thinkingPart = parts?.whereType<LlamaThinkingContent>().firstOrNull;
    return thinkingPart?.thinking;
  }

  ChatMessage copyWith({
    String? text,
    bool? isUser,
    bool? isInfo,
    List<LlamaContentPart>? parts,
    List<String>? debugBadges,
    LlamaChatRole? role,
    DateTime? timestamp,
    int? tokenCount,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      isInfo: isInfo ?? this.isInfo,
      parts: parts ?? this.parts,
      debugBadges: debugBadges ?? this.debugBadges,
      role: role ?? this.role,
      timestamp: timestamp ?? this.timestamp,
      tokenCount: tokenCount ?? this.tokenCount,
    );
  }

  factory ChatMessage.fromLlama(LlamaChatMessage msg) {
    final textParts = msg.parts.whereType<LlamaTextContent>().toList();

    // If there's no text but there's a tool call, use the raw JSON as text for now
    // (though the UI will show the "Executing Tool" view instead)
    String text = textParts.map((p) => p.text).join('\n');
    if (text.isEmpty) {
      final toolCall = msg.parts.whereType<LlamaToolCallContent>().firstOrNull;
      if (toolCall != null) {
        text = toolCall.rawJson;
      } else {
        final toolResult = msg.parts
            .whereType<LlamaToolResultContent>()
            .firstOrNull;
        if (toolResult != null) {
          final res = toolResult.result;
          if (res is String) {
            text = res;
          } else {
            text = jsonEncode(res);
          }
        }
      }
    }

    return ChatMessage(
      text: text,
      isUser: msg.role == LlamaChatRole.user,
      role: msg.role,
      parts: msg.parts,
      debugBadges: const [],
    );
  }
}
