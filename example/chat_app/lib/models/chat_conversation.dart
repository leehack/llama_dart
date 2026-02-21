import 'chat_message.dart';
import 'chat_settings.dart';

class ChatConversation {
  final String id;
  final String title;
  final DateTime updatedAt;
  final ChatSettings settings;
  final List<ChatMessage> messages;
  final int currentTokens;
  final bool isPruning;

  const ChatConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.settings,
    required this.messages,
    required this.currentTokens,
    required this.isPruning,
  });

  ChatConversation copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
    ChatSettings? settings,
    List<ChatMessage>? messages,
    int? currentTokens,
    bool? isPruning,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      settings: settings ?? this.settings,
      messages: messages ?? this.messages,
      currentTokens: currentTokens ?? this.currentTokens,
      isPruning: isPruning ?? this.isPruning,
    );
  }
}
