import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../models/chat_settings.dart';

/// Stateless helpers for managing conversation snapshots.
class ConversationStateService {
  const ConversationStateService();

  String newConversationId({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return timestamp.microsecondsSinceEpoch.toString();
  }

  int activeConversationIndex({
    required List<ChatConversation> conversations,
    required String activeConversationId,
  }) {
    return conversations.indexWhere((conversation) {
      return conversation.id == activeConversationId;
    });
  }

  ChatConversation createEmptyConversation({
    required String id,
    required ChatSettings settings,
    DateTime? now,
  }) {
    return ChatConversation(
      id: id,
      title: 'New conversation',
      updatedAt: now ?? DateTime.now(),
      settings: settings,
      messages: const <ChatMessage>[],
      currentTokens: 0,
      isPruning: false,
    );
  }

  String deriveConversationTitle({
    required List<ChatMessage> messages,
    required String fallback,
  }) {
    for (final message in messages) {
      if (!message.isUser) {
        continue;
      }

      final trimmed = message.text.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      if (trimmed.length > 52) {
        return '${trimmed.substring(0, 52)}...';
      }
      return trimmed;
    }

    return fallback;
  }

  ChatConversation buildSnapshot({
    required ChatConversation existing,
    required List<ChatMessage> messages,
    required ChatSettings settings,
    required int currentTokens,
    required bool isPruning,
    required bool touchUpdatedAt,
    DateTime? now,
  }) {
    return existing.copyWith(
      title: deriveConversationTitle(
        messages: messages,
        fallback: existing.title,
      ),
      updatedAt: touchUpdatedAt ? (now ?? DateTime.now()) : existing.updatedAt,
      settings: settings,
      messages: List<ChatMessage>.from(messages),
      currentTokens: currentTokens,
      isPruning: isPruning,
    );
  }
}
