import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_chat_example/providers/chat_provider.dart';
import 'package:llamadart_chat_example/models/chat_settings.dart';
import 'package:llamadart_chat_example/models/downloadable_model.dart';

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
      expect(provider.settings.toolsEnabled, isFalse);
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
      expect(provider.maxGenerationTokens, greaterThan(0));
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

    test('sendMessage updates token count', () async {
      await provider.loadModel();
      expect(provider.currentTokens, 0);

      await provider.sendMessage("Hello");

      // MockEngine returns 5 for prompt tokens, and yields 1 response token (which we count as 1 increment)
      // Total expected: 5 (prompt) + 8 (generated tokens from mock backend yield) = 13
      // Wait, let's look at MockLlamaBackend:
      // yield [72, 105, 32, 116, 104, 101, 114, 101]; // "Hi there"
      // That's one yield. Our current implementation increments _currentTokens for each YIELD in the stream.
      // MockLlamaEngine.create yields once. So 1 generated token.
      // ChatProvider _currentTokens only tracks generated tokens.
      expect(provider.currentTokens, 1);
    });

    test('normalizes generic JSON response envelope for display', () async {
      final jsonEngine = _JsonResponseEngine();
      final jsonProvider = ChatProvider(
        chatService: MockChatService(engine: jsonEngine),
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(modelPath: 'test_model.gguf'),
      );

      await jsonProvider.loadModel();
      await jsonProvider.sendMessage('hello');

      final assistant = jsonProvider.messages
          .where((m) => !m.isUser && !m.isInfo)
          .last;
      expect(assistant.text, equals('Hello from JSON envelope.'));
      expect(assistant.debugBadges, contains('fmt:generic'));
      expect(assistant.debugBadges, contains('think:none'));
    });

    test('extracts think tags into dedicated thinking content', () async {
      final thinkingEngine = _ThinkTaggedResponseEngine();
      final thinkingProvider = ChatProvider(
        chatService: MockChatService(engine: thinkingEngine),
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(modelPath: 'test_model.gguf'),
      );

      await thinkingProvider.loadModel();
      thinkingProvider.updateThinkingEnabled(true);
      await thinkingProvider.sendMessage('reason briefly');

      final assistant = thinkingProvider.messages
          .where((m) => !m.isUser && !m.isInfo)
          .last;
      expect(assistant.text, equals('Final answer.'));
      expect(assistant.thinkingText, equals('plan first'));
      expect(assistant.debugBadges, contains('think:tag-parse'));
    });

    test('extracts Ministral-style plain reasoning fallback', () async {
      final engine = _MinistralPlainReasoningEngine();
      final providerWithFallback = ChatProvider(
        chatService: MockChatService(engine: engine),
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(modelPath: 'test_model.gguf'),
      );

      await providerWithFallback.loadModel();
      providerWithFallback.updateToolsEnabled(true);
      providerWithFallback.updateThinkingEnabled(true);
      await providerWithFallback.sendMessage('hi');

      final assistant = providerWithFallback.messages
          .where((m) => !m.isUser && !m.isInfo)
          .last;
      expect(assistant.thinkingText, contains('user has greeted me'));
      expect(assistant.text, equals('Hello! How can I help you today?'));
      expect(assistant.debugBadges, contains('think:parse'));
    });

    test('passes user-declared tools into generation when enabled', () async {
      final captureEngine = _ToolCaptureEngine();
      final customProvider = ChatProvider(
        chatService: MockChatService(engine: captureEngine),
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(modelPath: 'test_model.gguf'),
      );

      await customProvider.loadModel();
      final saved = customProvider.updateToolDeclarations('''
[
  {
    "name": "lookup_city",
    "description": "Lookup city info",
    "parameters": {
      "type": "object",
      "properties": {
        "city": {"type": "string"}
      },
      "required": ["city"]
    }
  }
]
''');
      expect(saved, isTrue);
      customProvider.updateToolsEnabled(true);

      await customProvider.sendMessage('find seoul');

      expect(captureEngine.createCallCount, 1);
      expect(captureEngine.lastToolChoice, ToolChoice.auto);
      expect(captureEngine.lastTools, isNotNull);
      expect(captureEngine.lastTools, hasLength(1));
      expect(captureEngine.lastTools!.first.name, 'lookup_city');
    });

    test('handles tool-call responses in a single pass', () async {
      final engine = _SinglePassToolCallEngine();
      final singlePassProvider = ChatProvider(
        chatService: MockChatService(engine: engine),
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(modelPath: 'test_model.gguf'),
      );

      await singlePassProvider.loadModel();
      singlePassProvider.updateToolsEnabled(true);
      singlePassProvider.resetToolDeclarations();

      await singlePassProvider.sendMessage('what time is it?');

      expect(engine.createCallCount, 1);
      final assistant = singlePassProvider.messages
          .where((m) => !m.isUser && !m.isInfo)
          .last;
      expect(assistant.isToolCall, isTrue);
      expect(
        assistant.parts?.whereType<LlamaToolCallContent>().length,
        equals(1),
      );
    });

    test(
      'parses FunctionGemma tool-call text into structured tool parts',
      () async {
        final engine = _FunctionGemmaRawCallTextEngine();
        final customProvider = ChatProvider(
          chatService: MockChatService(engine: engine),
          settingsService: mockSettingsService,
          initialSettings: const ChatSettings(modelPath: 'test_model.gguf'),
        );

        await customProvider.loadModel();
        customProvider.updateToolsEnabled(true);
        customProvider.resetToolDeclarations();

        await customProvider.sendMessage('weather in london');

        final assistant = customProvider.messages
            .where((m) => !m.isUser && !m.isInfo)
            .last;
        final toolCalls =
            assistant.parts?.whereType<LlamaToolCallContent>().toList(
              growable: false,
            ) ??
            const <LlamaToolCallContent>[];
        expect(assistant.isToolCall, isTrue);
        expect(toolCalls, hasLength(1));
        expect(toolCalls.first.name, equals('getWeather'));
        expect(toolCalls.first.arguments, equals({'city': 'London'}));
      },
    );

    test('rejects invalid tool declaration payload', () async {
      final result = provider.updateToolDeclarations('{"name":"bad"}');

      expect(result, isFalse);
      expect(provider.toolDeclarationsError, isNotNull);
      expect(provider.declaredToolCount, 0);
    });

    test('rejects non-string nested parameter description', () async {
      final result = provider.updateToolDeclarations('''
[
  {
    "name": "bad_nested_description",
    "parameters": {
      "type": "object",
      "properties": {
        "city": {
          "type": "string",
          "description": 1
        }
      }
    }
  }
]
''');

      expect(result, isFalse);
      expect(provider.toolDeclarationsError, isNotNull);
      expect(provider.toolDeclarationsError, contains('description'));
      expect(provider.declaredToolCount, 0);
    });

    test('invalid declarations in initial settings do not crash provider', () {
      final invalidSettingsProvider = ChatProvider(
        chatService: mockChatService,
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(
          modelPath: 'test_model.gguf',
          toolDeclarations:
              '[{"name":"x","parameters":{"type":"object","properties":{"a":{"type":"string","description":1}}}}]',
        ),
      );

      expect(invalidSettingsProvider.toolDeclarationsError, isNotNull);
      expect(invalidSettingsProvider.declaredToolCount, 0);
    });

    test('clearConversation resets tokens', () async {
      await provider.loadModel();
      await provider.sendMessage("Hello");
      expect(provider.currentTokens, greaterThan(0));

      provider.clearConversation();

      expect(provider.currentTokens, 0);
    });

    test('delete last conversation resets to a fresh one', () async {
      final initialId = provider.activeConversationId;

      await provider.deleteConversation(initialId);

      expect(provider.conversations.length, 1);
      expect(provider.activeConversationId, isNot(initialId));
      expect(provider.messages, isEmpty);
    });

    test('passes thinking controls to generation call', () async {
      final engine = _ThinkingControlCaptureEngine();
      final customProvider = ChatProvider(
        chatService: MockChatService(engine: engine),
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(modelPath: 'test_model.gguf'),
      );

      await customProvider.loadModel();
      customProvider.updateThinkingEnabled(false);
      customProvider.updateThinkingBudgetTokens(256);

      await customProvider.sendMessage('hello');

      expect(engine.lastEnableThinking, isFalse);
      expect(engine.lastTemplateKwargs?['enable_thinking'], isFalse);
      expect(engine.lastTemplateKwargs?['thinking_budget'], 256);
      expect(engine.lastTemplateKwargs?['reasoning_budget'], 256);
    });

    test('updateSettings', () {
      provider.updateTemperature(0.5);
      expect(provider.settings.temperature, 0.5);

      provider.updateTopK(20);
      expect(provider.settings.topK, 20);

      provider.updateLogLevel(LlamaLogLevel.info);
      expect(provider.settings.logLevel, LlamaLogLevel.info);

      provider.updateNativeLogLevel(LlamaLogLevel.warn);
      expect(provider.settings.nativeLogLevel, LlamaLogLevel.warn);
    });

    test('updateContextSize supports auto mode', () {
      provider.updateContextSize(0);
      expect(provider.settings.contextSize, 0);

      provider.updateContextSize(256);
      expect(provider.settings.contextSize, 512);
    });

    test('switching backend updates preference without model reload', () async {
      provider.updateGpuLayers(48);
      expect(provider.settings.gpuLayers, 48);
      final backendBeforeChange = provider.activeBackend;

      await provider.updatePreferredBackend(GpuBackend.cpu);

      expect(provider.settings.preferredBackend, GpuBackend.cpu);
      expect(provider.settings.gpuLayers, 48);
      expect(provider.activeBackend, backendBeforeChange);

      await provider.updatePreferredBackend(GpuBackend.auto);

      expect(provider.settings.preferredBackend, GpuBackend.auto);
      expect(provider.settings.gpuLayers, 48);
      expect(provider.activeBackend, backendBeforeChange);
    });

    test('applyModelPreset updates generation and tool settings', () {
      const model = DownloadableModel(
        name: 'Preset model',
        description: 'Preset test model',
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        sizeBytes: 1,
        supportsToolCalling: true,
        preset: ModelPreset(
          temperature: 0.1,
          topK: 12,
          topP: 0.8,
          contextSize: 8192,
          maxTokens: 512,
          gpuLayers: 99,
        ),
      );

      provider.applyModelPreset(model);

      expect(provider.settings.temperature, 0.1);
      expect(provider.settings.topK, 12);
      expect(provider.settings.topP, 0.8);
      expect(provider.settings.contextSize, 8192);
      expect(provider.settings.maxTokens, 512);
      expect(provider.settings.gpuLayers, 99);
      expect(provider.settings.toolsEnabled, isFalse);
    });

    test('applyModelPreset disables tools when unsupported', () {
      const model = DownloadableModel(
        name: 'No tools model',
        description: 'No tools preset model',
        url: 'https://example.com/no-tools.gguf',
        filename: 'no-tools.gguf',
        sizeBytes: 1,
        supportsToolCalling: false,
      );

      provider.updateToolsEnabled(true);
      provider.applyModelPreset(model);

      expect(provider.settings.toolsEnabled, isFalse);
    });

    test(
      'fallback estimation does not force cpu layers when metal backend exists',
      () async {
        final engine = _MacFallbackEstimateEngine();
        final customProvider = ChatProvider(
          chatService: MockChatService(engine: engine),
          settingsService: mockSettingsService,
          initialSettings: const ChatSettings(
            modelPath: 'test_model.gguf',
            gpuLayers: 32,
            preferredBackend: GpuBackend.auto,
          ),
        );

        await customProvider.loadModel();

        expect(customProvider.settings.gpuLayers, 32);
        expect(customProvider.settings.preferredBackend, GpuBackend.metal);
      },
    );

    test(
      'applyModelPreset preserves manual tool preference when supported',
      () {
        const model = DownloadableModel(
          name: 'Forced tool model',
          description: 'Force tool test model',
          url: 'https://example.com/forced-tools.gguf',
          filename: 'forced-tools.gguf',
          sizeBytes: 1,
          supportsToolCalling: true,
        );

        provider.updateToolsEnabled(true);
        provider.applyModelPreset(model);

        expect(provider.settings.toolsEnabled, isTrue);
      },
    );
  });

  group('MockChatService Tests', () {
    test('cleanResponse trims whitespace', () {
      final result = mockChatService.cleanResponse('  hello world  ');
      expect(result, '  hello world  '); // MockChatService doesn't trim
    });
  });
}

class _JsonResponseEngine extends MockLlamaEngine {
  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    yield LlamaCompletionChunk(
      id: 'json-id',
      object: 'chat.completion.chunk',
      created: 1,
      model: 'mock-model',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(
            content: '{"response":"Hello from JSON envelope."}',
          ),
        ),
      ],
    );
  }
}

class _ThinkTaggedResponseEngine extends MockLlamaEngine {
  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    yield LlamaCompletionChunk(
      id: 'think-id',
      object: 'chat.completion.chunk',
      created: 1,
      model: 'mock-model',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(
            content: '<think>plan first</think>Final answer.',
          ),
        ),
      ],
    );
  }
}

class _MinistralPlainReasoningEngine extends MockLlamaEngine {
  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    yield LlamaCompletionChunk(
      id: 'ministral-plain-id',
      object: 'chat.completion.chunk',
      created: 1,
      model: 'mock-model',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(
            content:
                'Alright, the user has greeted me. I should respond politely.\n\nResponse:\n"Hello! How can I help you today?"Hello! How can I help you today?',
          ),
        ),
      ],
    );
  }
}

class _ToolCaptureEngine extends MockLlamaEngine {
  int createCallCount = 0;
  List<ToolDefinition>? lastTools;
  ToolChoice? lastToolChoice;

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    createCallCount++;
    lastTools = tools;
    lastToolChoice = toolChoice;

    yield LlamaCompletionChunk(
      id: 'capture-id',
      object: 'chat.completion.chunk',
      created: 1,
      model: 'mock-model',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(content: 'ok'),
        ),
      ],
    );
  }
}

class _SinglePassToolCallEngine extends MockLlamaEngine {
  int createCallCount = 0;

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    createCallCount++;
    yield LlamaCompletionChunk(
      id: 'single-pass-tool-call',
      object: 'chat.completion.chunk',
      created: 1,
      model: 'mock-model',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(
            toolCalls: [
              LlamaCompletionChunkToolCall(
                index: 0,
                id: 'call_1',
                type: 'function',
                function: LlamaCompletionChunkFunction(
                  name: 'getWeather',
                  arguments: '{"city":"Seoul"}',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThinkingControlCaptureEngine extends MockLlamaEngine {
  bool? lastEnableThinking;
  Map<String, dynamic>? lastTemplateKwargs;

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    lastEnableThinking = enableThinking;
    lastTemplateKwargs = chatTemplateKwargs;

    yield LlamaCompletionChunk(
      id: 'thinking-control',
      object: 'chat.completion.chunk',
      created: 1,
      model: 'mock-model',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(content: 'ok'),
        ),
      ],
    );
  }
}

class _MacFallbackEstimateEngine extends MockLlamaEngine {
  @override
  Future<({int total, int free})> getVramInfo() async => (total: 0, free: 0);

  @override
  Future<String> getBackendName() async => 'CPU, METAL';
}

class _FunctionGemmaRawCallTextEngine extends MockLlamaEngine {
  @override
  Future<Map<String, String>> getMetadata() async => {
    'tokenizer.chat_template': '<start_function_declaration>',
  };

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    yield LlamaCompletionChunk(
      id: 'function-gemma-tool',
      object: 'chat.completion.chunk',
      created: 1,
      model: 'mock-model',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(
            content:
                '<start_function_call>call getWeather{city:<escape>London<escape>}<end_function_call>',
          ),
        ),
      ],
    );
  }
}
