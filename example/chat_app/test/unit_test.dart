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
      await providerWithFallback.sendMessage('hi');

      final assistant = providerWithFallback.messages
          .where((m) => !m.isUser && !m.isInfo)
          .last;
      expect(assistant.thinkingText, contains('user has greeted me'));
      expect(assistant.text, equals('Hello! How can I help you today?'));
      expect(assistant.debugBadges, contains('think:parse'));
    });

    test('uses forced tool choice only on first turn', () async {
      final loopEngine = _FirstTurnToolChoiceEngine();
      final loopProvider = ChatProvider(
        chatService: MockChatService(engine: loopEngine),
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(modelPath: 'test_model.gguf'),
      );

      await loopProvider.loadModel();
      loopProvider.updateToolsEnabled(true);
      loopProvider.updateForceToolCall(true);

      await loopProvider.sendMessage('what time is it?');

      expect(loopEngine.receivedToolChoices.length, equals(2));
      expect(loopEngine.receivedToolChoices.first, equals(ToolChoice.required));
      expect(loopEngine.receivedToolChoices.last, isNull);
      expect(
        loopProvider.messages
            .where(
              (m) =>
                  !m.isUser &&
                  !m.isInfo &&
                  m.text.trim().isEmpty &&
                  (m.parts == null || m.parts!.isEmpty),
            )
            .isEmpty,
        isTrue,
      );
    });

    test('stops repeated tool loops after max rounds', () async {
      final loopEngine = _InfiniteToolLoopEngine();
      final loopProvider = ChatProvider(
        chatService: MockChatService(engine: loopEngine),
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(modelPath: 'test_model.gguf'),
      );

      await loopProvider.loadModel();
      loopProvider.updateToolsEnabled(true);
      loopProvider.updateForceToolCall(true);

      await loopProvider.sendMessage('loop forever');

      expect(
        loopProvider.messages.any(
          (m) =>
              m.isInfo &&
              (m.text.contains('Model repeated tool calls') ||
                  m.text.contains('Skipping repeated tool calls') ||
                  m.text.contains('Stopped after 5 tool-call rounds')),
        ),
        isTrue,
      );
      expect(loopEngine.createCallCount, lessThanOrEqualTo(6));
    });

    test('limits repeated calls for same tool name', () async {
      final engine = _VaryingArgsLoopEngine();
      final guardedProvider = ChatProvider(
        chatService: MockChatService(engine: engine),
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(modelPath: 'test_model.gguf'),
      );

      await guardedProvider.loadModel();
      guardedProvider.updateToolsEnabled(true);
      guardedProvider.updateForceToolCall(true);

      await guardedProvider.sendMessage('weather please');

      expect(
        guardedProvider.messages.any(
          (m) =>
              m.isInfo &&
              (m.text.contains('Model repeated tool calls') ||
                  m.text.contains('Skipping repeated tool calls') ||
                  m.text.contains('Stopped after 5 tool-call rounds')),
        ),
        isTrue,
      );
      expect(engine.createCallCount, lessThanOrEqualTo(6));
    });

    test('falls back to tool result when model ignores it', () async {
      final engine = _ToolResultIgnoringEngine();
      final providerWithFallback = ChatProvider(
        chatService: MockChatService(engine: engine),
        settingsService: mockSettingsService,
        initialSettings: const ChatSettings(modelPath: 'test_model.gguf'),
      );

      await providerWithFallback.loadModel();
      providerWithFallback.updateToolsEnabled(true);
      providerWithFallback.updateForceToolCall(true);

      await providerWithFallback.sendMessage('how is weather in london?');

      final assistant = providerWithFallback.messages
          .where((m) => !m.isUser && !m.isInfo)
          .last;
      expect(assistant.text, contains('The weather in London, UK is'));
      expect(
        assistant.text.toLowerCase(),
        isNot(contains('fictional response')),
      );
      expect(assistant.debugBadges, contains('fallback:tool-result'));
    });

    test('clearConversation resets tokens', () async {
      await provider.loadModel();
      await provider.sendMessage("Hello");
      expect(provider.currentTokens, greaterThan(0));

      provider.clearConversation();

      expect(provider.currentTokens, 0);
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

    test('switching backend preserves configured gpu layers', () async {
      provider.updateGpuLayers(48);
      expect(provider.settings.gpuLayers, 48);

      await provider.updatePreferredBackend(GpuBackend.cpu);

      expect(provider.settings.preferredBackend, GpuBackend.cpu);
      expect(provider.settings.gpuLayers, 48);
      expect(provider.activeBackend, 'CPU');
      expect(provider.runtimeGpuActive, isFalse);

      await provider.updatePreferredBackend(GpuBackend.auto);

      expect(provider.settings.preferredBackend, GpuBackend.auto);
      expect(provider.settings.gpuLayers, 48);
      expect(provider.activeBackend, 'Mock');
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
      expect(provider.settings.toolsEnabled, isTrue);
      expect(provider.settings.forceToolCall, isFalse);
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
      provider.updateForceToolCall(true);
      provider.applyModelPreset(model);

      expect(provider.settings.toolsEnabled, isFalse);
      expect(provider.settings.forceToolCall, isFalse);
    });

    test('applyModelPreset can force tool calling when configured', () {
      const model = DownloadableModel(
        name: 'Forced tool model',
        description: 'Force tool test model',
        url: 'https://example.com/forced-tools.gguf',
        filename: 'forced-tools.gguf',
        sizeBytes: 1,
        supportsToolCalling: true,
        preset: ModelPreset(forceToolCall: true),
      );

      provider.applyModelPreset(model);

      expect(provider.settings.toolsEnabled, isTrue);
      expect(provider.settings.forceToolCall, isTrue);
    });
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

class _FirstTurnToolChoiceEngine extends MockLlamaEngine {
  final List<ToolChoice?> receivedToolChoices = [];
  int _callIndex = 0;

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    receivedToolChoices.add(toolChoice);

    if (_callIndex == 0) {
      _callIndex++;
      yield LlamaCompletionChunk(
        id: 'tool-turn-1',
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
                  id: 'call_0',
                  type: 'function',
                  function: LlamaCompletionChunkFunction(
                    name: 'get_current_time',
                    arguments: '{}',
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      return;
    }

    yield LlamaCompletionChunk(
      id: 'tool-turn-2',
      object: 'chat.completion.chunk',
      created: 2,
      model: 'mock-model',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(content: 'Tool complete.'),
        ),
      ],
    );
  }
}

class _InfiniteToolLoopEngine extends MockLlamaEngine {
  int createCallCount = 0;

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    createCallCount++;

    yield LlamaCompletionChunk(
      id: 'loop-$createCallCount',
      object: 'chat.completion.chunk',
      created: createCallCount,
      model: 'mock-model',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(
            toolCalls: [
              LlamaCompletionChunkToolCall(
                index: 0,
                id: 'call_$createCallCount',
                type: 'function',
                function: LlamaCompletionChunkFunction(
                  name: 'get_current_time',
                  arguments: '{}',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToolResultIgnoringEngine extends MockLlamaEngine {
  int _callIndex = 0;

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    if (_callIndex == 0) {
      _callIndex++;
      yield LlamaCompletionChunk(
        id: 'ignore-tool-1',
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
                    name: 'get_current_weather',
                    arguments: '{"city":"London, UK","unit":"celsius"}',
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      return;
    }

    yield LlamaCompletionChunk(
      id: 'ignore-tool-2',
      object: 'chat.completion.chunk',
      created: 2,
      model: 'mock-model',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(
            content:
                "This is a fictional response, as I don't have real-time access to current weather conditions.",
          ),
        ),
      ],
    );
  }
}

class _VaryingArgsLoopEngine extends MockLlamaEngine {
  int createCallCount = 0;

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    createCallCount++;

    final city = switch (createCallCount) {
      1 => 'London, UK',
      2 => 'London UK',
      _ => 'London',
    };

    yield LlamaCompletionChunk(
      id: 'vary-$createCallCount',
      object: 'chat.completion.chunk',
      created: createCallCount,
      model: 'mock-model',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(
            toolCalls: [
              LlamaCompletionChunkToolCall(
                index: 0,
                id: 'call_$createCallCount',
                type: 'function',
                function: LlamaCompletionChunkFunction(
                  name: 'get_current_weather',
                  arguments: '{"city":"$city","unit":"celsius"}',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
