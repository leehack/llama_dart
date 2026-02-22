import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_chat_example/models/chat_message.dart';
import 'package:llamadart_chat_example/services/chat_session_service.dart';

import 'mocks.dart';

void main() {
  const service = ChatSessionService();

  group('ChatSessionService', () {
    test('serializes chat message with text when parts are absent', () {
      final serialized = service.toLlamaChatMessage(
        ChatMessage(text: 'hello', isUser: true),
      );

      expect(serialized, isNotNull);
      expect(serialized!.role, LlamaChatRole.user);
      expect(
        serialized.parts.whereType<LlamaTextContent>().first.text,
        'hello',
      );
    });

    test('ignores informational messages during serialization', () {
      final serialized = service.toLlamaChatMessage(
        ChatMessage(text: 'info', isUser: false, isInfo: true),
      );

      expect(serialized, isNull);
    });

    test('rebuilds session from conversation messages', () {
      final engine = MockLlamaEngine()..initialized = true;
      final session = service.rebuildFromMessages(
        engine: engine,
        contextSize: 4096,
        systemPrompt: 'system',
        messages: <ChatMessage>[
          ChatMessage(text: 'hello', isUser: true),
          ChatMessage(text: 'world', isUser: false),
          ChatMessage(text: 'info', isUser: false, isInfo: true),
        ],
      );

      expect(session.history, hasLength(2));
      expect(session.history.first.role, LlamaChatRole.user);
      expect(session.history.last.role, LlamaChatRole.assistant);
    });
  });
}
