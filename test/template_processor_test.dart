import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import 'test_helper.dart';
import 'dart:io';

void main() {
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
