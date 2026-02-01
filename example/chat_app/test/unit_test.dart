import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart_chat_example/providers/chat_provider.dart';
import 'package:llamadart_chat_example/models/chat_settings.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatProvider provider;
  late MockChatService mockChatService;
  late MockSettingsService mockSettingsService;
  late MockLlamaEngine mockEngine;

  setUp(() async {
    mockEngine = MockLlamaEngine();
    mockChatService = MockChatService(engine: mockEngine);
    mockSettingsService = MockSettingsService();
    final initialSettings = const ChatSettings(modelPath: "test_model.gguf");
    mockSettingsService.settings = initialSettings;

    provider = ChatProvider(
      chatService: mockChatService,
      settingsService: mockSettingsService,
      initialSettings: initialSettings,
    );
  });

  group('ChatProvider Unit Tests', () {
    test('Initial state', () {
      expect(provider.messages, isEmpty);
      expect(provider.isInitializing, isFalse);
    });

    test('loadModel success', () async {
      await provider.loadModel();

      expect(provider.isLoaded, isTrue);
      expect(provider.error, isNull);

      expect(
        provider.messages.any(
          (m) => m.text.contains('Model loaded successfully'),
        ),
        isTrue,
      );
      expect(mockEngine.initialized, isTrue);
    });

    test('loadModel failure', () async {
      final failingProvider = ChatProvider(
        chatService: mockChatService,
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(modelPath: ""),
      );

      await failingProvider.loadModel();

      expect(failingProvider.isLoaded, isFalse);
      expect(failingProvider.error, isNotNull);
    });

    test('sendMessage', () async {
      await provider.loadModel();
      final initialMessageCount = provider.messages.length;

      await provider.sendMessage("Hello");

      // Should have: [Welcome, User Msg, Assistant Response]
      expect(provider.messages.length, initialMessageCount + 2);
      expect(
        provider.messages.any((m) => m.text == "Hello" && m.isUser),
        isTrue,
      );
      expect(provider.messages.last.isUser, isFalse);
      expect(provider.messages.last.text, contains("Hi there"));
    });

    test('clearConversation', () async {
      await provider.loadModel();
      await provider.sendMessage("Hello");
      expect(provider.messages.length, greaterThan(1));

      provider.clearConversation();

      expect(provider.messages.length, 1);
      expect(provider.messages.first.text, contains("Conversation cleared"));
    });

    test('updateSettings', () {
      provider.updateTemperature(0.5);
      expect(provider.settings.temperature, 0.5);

      provider.updateTopK(20);
      expect(provider.settings.topK, 20);
    });
  });

  group('MockChatService Tests', () {
    test('generate stream', () async {
      final stream = mockChatService.generate([], const ChatSettings());
      final result = await stream.join();
      expect(result, "Hi there");
    });
  });
}
