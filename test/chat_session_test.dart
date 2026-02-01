import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import 'engine_test.dart'; // To reuse MockLlamaBackend

void main() {
  late LlamaEngine engine;
  late MockLlamaBackend backend;
  late ChatSession session;

  setUp(() async {
    backend = MockLlamaBackend();
    engine = LlamaEngine(backend);
    await engine.loadModel('mock_path');
    session = ChatSession(engine);
  });

  group('ChatSession Unit Tests', () {
    test('Initial state', () {
      expect(session.history, isEmpty);
      expect(session.systemPrompt, isNull);
    });

    test('Add message to history', () {
      session.addMessage(
        const LlamaChatMessage(role: 'user', content: 'hello'),
      );
      expect(session.history.length, 1);
      expect(session.history.first.content, 'hello');
    });

    test('Chat updates history', () async {
      final response = await session.chatText('How are you?');

      expect(response, 'Hello world');
      expect(session.history.length, 2);
      expect(session.history[0].role, LlamaChatRole.user);
      expect(session.history[0].content, 'How are you?');
      expect(session.history[1].role, LlamaChatRole.assistant);
      expect(session.history[1].content, 'Hello world');
    });

    test('System prompt persistence', () async {
      session.systemPrompt = "You are a helpful assistant.";
      expect(session.systemPrompt, "You are a helpful assistant.");

      await session.chatText('Hi');
      // History should only contain user/assistant messages, system prompt is handled internally
      expect(session.history.length, 2);
    });

    test('Clear history', () {
      session.addMessage(const LlamaChatMessage(role: 'user', content: 'test'));
      session.clearHistory();
      expect(session.history, isEmpty);
    });

    test('Reset session', () {
      session.systemPrompt = "System";
      session.addMessage(const LlamaChatMessage(role: 'user', content: 'test'));

      // Default reset (keeps system prompt)
      session.reset();
      expect(session.history, isEmpty);
      expect(session.systemPrompt, "System");

      // Full reset
      session.reset(keepSystemPrompt: false);
      expect(session.systemPrompt, isNull);
    });

    test('History immutability via getter', () {
      expect(
        () => session.history.add(
          const LlamaChatMessage(role: 'user', content: 'x'),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
