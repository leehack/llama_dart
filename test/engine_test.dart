import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';

class MockLlamaBackend implements LlamaBackend {
  bool _isReady = false;
  bool shouldFailLoad = false;
  @override
  bool get isReady => _isReady;

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    if (shouldFailLoad) throw Exception("Failed");
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
  Future<void> modelFree(int modelHandle) async {
    _isReady = false;
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    return 100;
  }

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    yield utf8.encode("Hello world");
  }

  @override
  void cancelGeneration() {}

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    return [1, 2, 3];
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async {
    return "mock text";
  }

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    return {"general.name": "mock-model"};
  }

  @override
  Future<LlamaChatTemplateResult> applyChatTemplate(
    int modelHandle,
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
  }) async {
    return const LlamaChatTemplateResult(
      prompt: "mock chat prompt",
      stopSequences: ["</s>"],
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
  Future<String> getBackendName() async => "Mock";

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
  ) async => 1;

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}

  @override
  Future<bool> supportsAudio(int mmContextHandle) async => false;

  @override
  Future<bool> supportsVision(int mmContextHandle) async => false;
}

void main() {
  late LlamaEngine engine;
  late MockLlamaBackend backend;

  setUp(() {
    backend = MockLlamaBackend();
    engine = LlamaEngine(backend);
  });

  tearDown(() async {
    await engine.dispose();
  });

  group('LlamaEngine Unit Tests', () {
    test('Initialization state', () {
      expect(engine.isReady, isFalse);
    });

    test('Load model', () async {
      await engine.loadModel('mock_path');
      expect(engine.isReady, isTrue);
      expect(engine.modelHandle, 1);
      expect(engine.contextHandle, 100);
      expect(engine.tokenizer, isNotNull);
      expect(engine.templateProcessor, isNotNull);
    });

    test('Tokenize and Detokenize', () async {
      await engine.loadModel('mock_path');
      final tokens = await engine.tokenize('hello');
      expect(tokens, [1, 2, 3]);

      final text = await engine.detokenize(tokens);
      expect(text, 'mock text');
    });

    test('Generate', () async {
      await engine.loadModel('mock_path');
      final stream = engine.generate('test prompt');
      final result = await stream.join();
      expect(result, 'Hello world');
    });

    test('Chat', () async {
      await engine.loadModel('mock_path');
      final messages = [const LlamaChatMessage(role: 'user', content: 'hi')];
      final stream = engine.chat(messages);
      final result = await stream.join();
      expect(result, 'Hello world');
    });

    test('Metadata', () async {
      await engine.loadModel('mock_path');
      final meta = await engine.getMetadata();
      expect(meta['general.name'], 'mock-model');
    });

    test('Dispose', () async {
      await engine.loadModel('mock_path');
      await engine.dispose();
      expect(engine.isReady, isFalse);
    });

    test('loadModelFromUrl throws Unimplemented on Native mock', () async {
      expect(engine.loadModelFromUrl('http://test'), throwsUnimplementedError);
    });

    test('loadModel throws LlamaModelException on backend error', () async {
      backend.shouldFailLoad = true;
      expect(engine.loadModel('fail'), throwsA(isA<LlamaModelException>()));
    });

    test('tokenize/detokenize throw when not ready', () {
      expect(
        () => engine.tokenize('hi'),
        throwsA(isA<LlamaContextException>()),
      );
      expect(
        () => engine.detokenize([1]),
        throwsA(isA<LlamaContextException>()),
      );
      expect(
        () => engine.chatTemplate([]),
        throwsA(isA<LlamaContextException>()),
      );
    });

    test('Error when not initialized', () {
      expect(engine.generate('test'), emitsError(isA<LlamaContextException>()));
    });
  });

  group('LlamaTokenizer Unit Tests', () {
    test('encode/decode/count', () async {
      final tokenizer = LlamaTokenizer(backend, 1);
      expect(await tokenizer.encode('test'), [1, 2, 3]);
      expect(await tokenizer.decode([1, 2, 3]), 'mock text');
      expect(await tokenizer.count('test'), 3);
    });
  });

  group('ChatTemplateProcessor Unit Tests', () {
    test('apply/detectStopSequences', () async {
      final processor = ChatTemplateProcessor(backend, 1);
      final result = await processor.apply([]);
      expect(result.prompt, 'mock chat prompt');
      expect(result.stopSequences, ['</s>']);
      expect(await processor.detectStopSequences(), ['</s>']);
    });
  });

  group('Model Models Unit Tests', () {
    test('ModelParams copyWith', () {
      const params = ModelParams(contextSize: 1024);
      final updated = params.copyWith(gpuLayers: 10);
      expect(updated.contextSize, 1024);
      expect(updated.gpuLayers, 10);
    });

    test('GenerationParams copyWith', () {
      const params = GenerationParams(temp: 0.5);
      final updated = params.copyWith(maxTokens: 100);
      expect(updated.temp, 0.5);
      expect(updated.maxTokens, 100);
    });

    test('LlamaException toString', () {
      final ex = LlamaModelException('failed', 'io error');
      expect(ex.toString(), contains('LlamaException: failed (io error)'));
    });
  });
}
