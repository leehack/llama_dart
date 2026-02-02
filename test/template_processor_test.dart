@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import 'test_helper.dart';
import 'dart:io';

void main() {
  group('ChatTemplateProcessor (Unit)', () {
    late ChatTemplateProcessor processor;
    late MockLlamaBackend backend;

    setUp(() {
      backend = MockLlamaBackend();
      processor = ChatTemplateProcessor(backend, 1);
    });

    tearDown(() async {
      await backend.dispose();
    });

    test('apply returns mock result', () async {
      final messages = [const LlamaChatMessage(role: 'user', content: 'hi')];
      final result = await processor.apply(messages);
      expect(result.prompt, 'mock prompt');
      expect(result.stopSequences, ['</s>']);
    });

    test('detectStopSequences', () async {
      final stops = await processor.detectStopSequences();
      expect(stops, ['</s>']);
    });
  });

  group('ChatTemplateProcessor (Integration)', () {
    late File modelFile;
    late LlamaBackend backend;
    int? modelHandle;
    late ChatTemplateProcessor processor;

    setUpAll(() async {
      modelFile = await TestHelper.getTestModel();
      backend = LlamaBackend();
      modelHandle = await backend.modelLoad(
        modelFile.path,
        const ModelParams(),
      );
      processor = ChatTemplateProcessor(backend, modelHandle!);
    });

    tearDownAll(() async {
      if (modelHandle != null) {
        await backend.modelFree(modelHandle!);
      }
      await backend.dispose();
    });

    test('real template application', () async {
      final messages = [const LlamaChatMessage(role: 'user', content: 'Hello')];
      final result = await processor.apply(messages);
      expect(result.prompt, isNotEmpty);
      expect(result.prompt, contains('Hello'));
      expect(result.stopSequences, isNotEmpty);
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
  }) async => [];
  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async => "";
  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {};
  @override
  Future<LlamaChatTemplateResult> applyChatTemplate(
    int modelHandle,
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
  }) async => const LlamaChatTemplateResult(
    prompt: "mock prompt",
    stopSequences: ["</s>"],
  );
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
