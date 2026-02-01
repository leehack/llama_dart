@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import 'test_helper.dart';

void main() async {
  late File modelFile;
  late LlamaEngine engine;
  late LlamaBackend backend;

  setUpAll(() async {
    modelFile = await TestHelper.getTestModel();
    backend = LlamaBackend();
    engine = LlamaEngine(backend);
  });

  tearDownAll(() async {
    await engine.dispose();
  });

  group('LlamaEngine Integration', () {
    test('full lifecycle: load, tokenize, generate, metadata', () async {
      // 1. Load Model
      await engine.loadModel(
        modelFile.path,
        modelParams: const ModelParams(contextSize: 128),
      );
      expect(engine.isReady, isTrue);
      expect(engine.modelHandle, isNotNull);
      expect(engine.contextHandle, isNotNull);

      // 2. Tokenize
      final tokens = await engine.tokenize('Once upon a time');
      expect(tokens, isNotEmpty);

      // 3. Detokenize
      final text = await engine.detokenize(tokens);
      expect(text, contains('Once upon a time'));

      // 4. Generate
      final stream = engine.generate(
        'The dog',
        params: const GenerationParams(maxTokens: 10),
      );
      final result = await stream.join();
      expect(result, isNotEmpty);
      print('Generated: "$result"');

      // 5. Metadata
      final metadata = await engine.getMetadata();
      expect(metadata, isNotEmpty);
      expect(metadata['general.architecture'], 'llama');

      // 6. Backend Info
      expect(await engine.getBackendName(), isNotEmpty);
      expect(await engine.isGpuSupported(), isA<bool>());
    });

    test('Chat interface', () async {
      if (!engine.isReady) {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(contextSize: 128),
        );
      }

      final messages = [const LlamaChatMessage(role: 'user', content: 'Hi')];
      final stream = engine.chat(
        messages,
        params: const GenerationParams(maxTokens: 10),
      );
      final result = await stream.join();
      expect(result, isNotEmpty);
      print('Chat Response: "$result"');
    });

    test('Cancel generation', () async {
      if (!engine.isReady) {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(contextSize: 128),
        );
      }

      final stream = engine.generate(
        'Long story about a cat',
        params: const GenerationParams(maxTokens: 100),
      );

      String accumulated = '';
      final subscription = stream.listen((token) {
        accumulated += token;
        if (accumulated.length > 5) {
          engine.cancelGeneration();
        }
      });

      // Increased timeout to allow generation to start and be cancelled
      await Future.delayed(const Duration(seconds: 5));
      await subscription.cancel();

      expect(accumulated, isNotEmpty, reason: 'Generation should have started');
      // It should have stopped before 100 tokens
    });
  });
}
