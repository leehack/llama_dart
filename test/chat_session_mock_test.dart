import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';

class MockLlamaBackend implements LlamaBackend {
  int _generateCallCount = 0;
  final List<String> _responses = [];
  int contextSize = 2048;
  String? lastPrompt;

  void queueResponse(String response) => _responses.add(response);

  @override
  bool get isReady => true;

  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async => 1;

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<int> getContextSize(int contextHandle) async => contextSize;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    lastPrompt = prompt;
    if (_generateCallCount < _responses.length) {
      yield utf8.encode(_responses[_generateCallCount++]);
    } else {
      yield utf8.encode('default response');
    }
  }

  @override
  void cancelGeneration() {}

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    return List.generate(text.length, (i) => i);
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async => 'decoded';

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {};

  @override
  Future<LlamaChatTemplateResult> applyChatTemplate(
    int modelHandle,
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
  }) async {
    final combined = messages
        .map((m) {
          return m.parts
              .whereType<LlamaTextContent>()
              .map((p) => p.text)
              .join("");
        })
        .join('\n');
    return LlamaChatTemplateResult(
      prompt: combined,
      stopSequences: [],
      tokenCount: combined.length,
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
  Future<void> dispose() async {}
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
  late ChatSession session;

  setUp(() async {
    backend = MockLlamaBackend();
    engine = LlamaEngine(backend);
    await engine.loadModel('test.gguf');
    session = ChatSession(engine);
  });

  group('ChatSession Mock Tests', () {
    test('onMessageAdded callback', () async {
      final added = <LlamaChatMessage>[];
      backend.queueResponse('Resp');
      await session.chat('Hi', onMessageAdded: (m) => added.add(m)).drain();
      expect(added.length, 2);
    });

    test('enforceContextLimit truncation', () async {
      backend.contextSize = 1000;
      session.maxContextTokens = 1000;
      for (int i = 0; i < 20; i++) {
        backend.queueResponse('R');
        await session.chat('M' * 50).drain();
      }
      expect(session.history, isNotEmpty);
      expect(session.history.length, lessThan(40));
    });

    test('multimodal marker injection', () async {
      final msg = LlamaChatMessage.multimodal(
        role: LlamaChatRole.user,
        parts: [
          LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
          const LlamaTextContent('What is this?'),
        ],
      );
      session.addMessage(msg);
      backend.queueResponse('An image');

      await session.chat('Explain').drain();

      expect(backend.lastPrompt, contains('<__media__>'));
    });

    test('_isToolCall variations', () async {
      final registry = ToolRegistry([
        ToolDefinition(
          name: 'test',
          description: 'test tool',
          handler: (p) async => 'result',
          parameters: [],
        ),
      ]);
      session.toolRegistry = registry;

      // Variation 1: OpenAI format
      backend.queueResponse(
        '{"type": "function", "function": {"name": "test", "parameters": {}}}',
      );
      backend.queueResponse('Final');
      await session.chat('call test').drain();
      expect(session.history.any((m) => m.role == LlamaChatRole.tool), true);

      // Variation 2: Direct name/parameters
      session.clearHistory();
      backend.queueResponse('{"name": "test", "parameters": {}}');
      backend.queueResponse('Final 2');
      await session.chat('call test again').drain();
      expect(session.history.any((m) => m.role == LlamaChatRole.tool), true);
    });
  });
}
