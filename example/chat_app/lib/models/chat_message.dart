import 'package:llamadart/llamadart.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isInfo; // Non-conversation informational message
  final DateTime timestamp;
  final List<LlamaContentPart>? parts;
  int? tokenCount; // Cache token count for sliding window optimization

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isInfo = false,
    this.parts,
    DateTime? timestamp,
    this.tokenCount,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? text,
    bool? isUser,
    bool? isInfo,
    List<LlamaContentPart>? parts,
    DateTime? timestamp,
    int? tokenCount,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      isInfo: isInfo ?? this.isInfo,
      parts: parts ?? this.parts,
      timestamp: timestamp ?? this.timestamp,
      tokenCount: tokenCount ?? this.tokenCount,
    );
  }
}
