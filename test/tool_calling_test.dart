import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';

class MockLlamaBackend implements LlamaBackend {
  bool _isReady = false;
  final List<String> prompts = [];
  final List<GenerationParams> paramsList = [];

  final _generateQueuedTokens = <List<String>>[];
  int _generateCallCount = 0;

  @override
  bool get isReady => _isReady;

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    _isReady = true;
    return 1;
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async {
    _isReady = true;
    return 1;
  }

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<int> getContextSize(int contextHandle) async => 2048;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    prompts.add(prompt);
    paramsList.add(params);

    if (_generateCallCount < _generateQueuedTokens.length) {
      final tokens = _generateQueuedTokens[_generateCallCount];
      _generateCallCount++;
      for (final t in tokens) {
        yield utf8.encode(t);
      }
    }
  }

  void queueResponse(List<String> tokens) {
    _generateQueuedTokens.add(tokens);
  }

  @override
  void cancelGeneration() {}

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async => [1, 2, 3];

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async => 'decoded';

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {
    'general.architecture': 'llama',
    'tokenizer.chat_template': 'default',
  };

  @override
  Future<LlamaChatTemplateResult> applyChatTemplate(
    int modelHandle,
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
  }) async {
    return LlamaChatTemplateResult(
      prompt: 'templated',
      stopSequences: ['</s>'],
    );
  }

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async {}

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async {}

  @override
  Future<void> clearLoraAdapters(int contextHandle) async {}

  @override
  Future<String> getBackendName() async => 'Mock';

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<bool> isGpuSupported() async => false;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {
    _isReady = false;
  }

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async => null;

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}

  @override
  Future<bool> supportsVision(int mmContextHandle) async => false;

  @override
  Future<bool> supportsAudio(int mmContextHandle) async => false;
}

void main() {
  late MockLlamaBackend backend;
  late LlamaEngine engine;
  late ToolRegistry registry;

  setUp(() async {
    backend = MockLlamaBackend();
    engine = LlamaEngine(backend);
    await engine.loadModel('mock.gguf');

    registry = ToolRegistry([
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [
          ToolParam.string(
            'location',
            description: 'City name',
            required: true,
          ),
        ],
        handler: (params) async =>
            'Sunny in ${params.getRequiredString("location")}',
      ),
    ]);
  });

  group('ToolRegistry', () {
    test('generateSystemPrompt includes tool definitions', () {
      final prompt = registry.generateSystemPrompt();
      expect(prompt, contains('get_weather'));
      expect(prompt, contains('Get weather'));
      expect(prompt, contains('location'));
    });

    test('invoke handles valid tool call', () async {
      final result = await registry.invoke('get_weather', {
        'location': 'London',
      });
      expect(result, 'Sunny in London');
    });
  });

  group('ChatSession Tool Calling', () {
    test('chat flow executes tool and generates final response', () async {
      final session = ChatSession(engine, toolRegistry: registry);

      // First call generates tool call JSON
      backend.queueResponse([
        '{"type": "function", "function": {"name": "get_weather", "parameters": {"location": "London"}}}',
      ]);
      // Second call (after tool result) generates final response
      backend.queueResponse(['The weather in London is sunny.']);

      final stream = session.chat('Weather?');
      final result = await stream.join();

      expect(result, contains('London is sunny'));
      expect(session.history.length, 4);
      expect(session.history[1].role, LlamaChatRole.assistant);
      expect(session.history[2].role, LlamaChatRole.tool);
      expect(session.history[3].role, LlamaChatRole.assistant);
    });

    test('forceToolCall: true results in grammar usage on FIRST call', () async {
      final session = ChatSession(
        engine,
        toolRegistry: registry,
        forceToolCall: true,
      );

      backend.queueResponse([
        '{"type": "function", "function": {"name": "get_weather", "parameters": {"location": "London"}}}',
      ]);
      backend.queueResponse(['Final']);

      await session.chat('Weather?').toList();

      expect(
        backend.paramsList.first.grammar,
        isNotNull,
        reason:
            'Grammar should be used on the first call when forceToolCall is true',
      );
      expect(
        backend.paramsList.last.grammar,
        isNull,
        reason:
            'Grammar should NOT be used on the final response (natural language)',
      );
    });

    test('forceToolCall: false does NOT use grammar', () async {
      final session = ChatSession(
        engine,
        toolRegistry: registry,
        forceToolCall: false,
      );

      backend.queueResponse([
        '{"type": "function", "function": {"name": "get_weather", "parameters": {"location": "London"}}}',
      ]);
      backend.queueResponse(['Final']);

      await session.chat('Weather?').toList();

      expect(
        backend.paramsList.first.grammar,
        isNull,
        reason: 'Grammar should NOT be used when forceToolCall is false',
      );
    });

    test('singleTurn with tools', () async {
      backend.queueResponse([
        '{"type": "function", "function": {"name": "get_weather", "parameters": {"location": "London"}}}',
      ]);
      backend.queueResponse(['Final response']);

      final result = await ChatSession.singleTurn(engine, [
        const LlamaChatMessage.text(
          role: LlamaChatRole.user,
          content: 'Weather?',
        ),
      ], toolRegistry: registry);

      expect(result, 'Final response');
    });

    test('tools are skipped when toolsEnabled is false', () async {
      final session = ChatSession(
        engine,
        toolRegistry: registry,
        toolsEnabled: false,
      );

      backend.queueResponse(['Direct response without tools']);

      final result = await session.chat('Weather?').join();

      expect(result, contains('Direct response without tools'));
      expect(
        session.history.length,
        2,
      ); // User + Assistant (no tool calls/results)
    });
  });
}
