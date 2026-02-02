import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:llamadart/llamadart.dart';

class TestHelper {
  static const String modelUrl =
      'https://huggingface.co/ggml-org/tiny-llamas/resolve/main/stories15M.gguf';
  static const String modelFileName = 'stories15M.gguf';

  static Future<File> getTestModel() async {
    final modelsDir = Directory(path.join(Directory.current.path, 'models'));
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    final modelFile = File(path.join(modelsDir.path, modelFileName));
    if (modelFile.existsSync()) {
      return modelFile;
    }

    print('Downloading test model from $modelUrl...');
    final response = await http.get(Uri.parse(modelUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to download model: ${response.statusCode}');
    }

    await modelFile.writeAsBytes(response.bodyBytes);
    print('Test model downloaded to ${modelFile.path}');
    return modelFile;
  }
}

/// Mock implementation of LlamaBackend for unit testing.
/// This mock can be shared across multiple test files to avoid duplication.
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
  }) async => 'mock text';
  
  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {};
  
  @override
  Future<LlamaChatTemplateResult> applyChatTemplate(
    int modelHandle,
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
  }) async => const LlamaChatTemplateResult(
    prompt: 'mock prompt',
    stopSequences: ['</s>'],
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
  ) async => 1;

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}

  @override
  Future<bool> supportsAudio(int mmContextHandle) async => false;

  @override
  Future<bool> supportsVision(int mmContextHandle) async => false;
}
