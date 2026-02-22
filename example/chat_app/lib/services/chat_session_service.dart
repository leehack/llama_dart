import 'package:llamadart/llamadart.dart';

import '../models/chat_message.dart';

/// Creates and restores [ChatSession] instances from UI message state.
class ChatSessionService {
  const ChatSessionService();

  ChatSession createSession({
    required LlamaEngine engine,
    required int contextSize,
    String? systemPrompt,
  }) {
    return ChatSession(
      engine,
      maxContextTokens: contextSize > 0 ? contextSize : null,
      systemPrompt: systemPrompt,
    );
  }

  ChatSession rebuildFromMessages({
    required LlamaEngine engine,
    required int contextSize,
    String? systemPrompt,
    required Iterable<ChatMessage> messages,
  }) {
    final session = createSession(
      engine: engine,
      contextSize: contextSize,
      systemPrompt: systemPrompt,
    );

    for (final message in messages) {
      final serialized = toLlamaChatMessage(message);
      if (serialized != null) {
        session.addMessage(serialized);
      }
    }

    return session;
  }

  LlamaChatMessage? toLlamaChatMessage(ChatMessage message) {
    if (message.isInfo) {
      return null;
    }

    final role =
        message.role ??
        (message.isUser ? LlamaChatRole.user : LlamaChatRole.assistant);
    final parts = message.parts != null && message.parts!.isNotEmpty
        ? List<LlamaContentPart>.from(message.parts!)
        : <LlamaContentPart>[
            if (message.text.trim().isNotEmpty) LlamaTextContent(message.text),
          ];

    if (parts.isEmpty) {
      return null;
    }

    return LlamaChatMessage.withContent(role: role, content: parts);
  }
}
