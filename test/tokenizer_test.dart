import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import 'test_helper.dart';
import 'dart:io';

void main() {
  group('LlamaTokenizer (Unit)', () {
    late LlamaTokenizer tokenizer;
    late MockLlamaBackend backend;

    setUp(() {
      backend = MockLlamaBackend();
      tokenizer = LlamaTokenizer(backend, 1);
    });

    tearDown(() async {
      await backend.dispose();
    });

    test('encode', () async {
      final tokens = await tokenizer.encode('test');
      expect(tokens, [1, 2, 3]);
    });

    test('decode', () async {
      final text = await tokenizer.decode([1, 2, 3]);
      expect(text, 'mock text');
    });

    test('count', () async {
      final count = await tokenizer.count('test');
      expect(count, 3);
    });
  });

  group('LlamaTokenizer (Integration)', () {
    late File modelFile;
    late LlamaBackend backend;
    int? modelHandle;
    late LlamaTokenizer tokenizer;

    setUpAll(() async {
      modelFile = await TestHelper.getTestModel();
      backend = LlamaBackend();
      modelHandle = await backend.modelLoad(
        modelFile.path,
        const ModelParams(),
      );
      tokenizer = LlamaTokenizer(backend, modelHandle!);
    });

    tearDownAll(() async {
      if (modelHandle != null) {
        await backend.modelFree(modelHandle!);
      }
      await backend.dispose();
    });

    test('real tokenization', () async {
      final tokens = await tokenizer.encode('Hello world');
      expect(tokens, isNotEmpty);

      final text = await tokenizer.decode(tokens);
      // Small models might detokenize slightly differently depending on special tokens,
      // but 'Hello world' should be there.
      expect(text.toLowerCase(), contains('hello world'));
    });

    test('count matches encode length', () async {
      const text = 'Testing token count';
      final tokens = await tokenizer.encode(text);
      final count = await tokenizer.count(text);
      expect(count, tokens.length);
    });
  });
}

class MockLlamaBackend implements LlamaBackend {
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
  Future<int> getContextSize(int contextHandle) async => 512;
  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {}
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
  }) async => "mock text";
  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {};
  @override
  Future<LlamaChatTemplateResult> applyChatTemplate(
    int modelHandle,
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
  }) async => const LlamaChatTemplateResult(prompt: "", stopSequences: []);
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
