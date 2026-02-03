@TestOn('vm')
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
        modelParams: const ModelParams(
          contextSize: 256,
          logLevel: LlamaLogLevel.none,
        ),
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

      // 7. Context Size
      final ctxSize = await engine.getContextSize();
      expect(ctxSize, 256);

      // 8. Chat Template
      final messages = [
        const LlamaChatMessage.text(role: LlamaChatRole.user, content: 'Hi'),
      ];
      final templateResult = await engine.chatTemplate(messages);
      expect(templateResult.prompt, isNotEmpty);
      expect(templateResult.tokenCount, greaterThan(0));

      // 9. Token Count
      final count = await engine.getTokenCount('Once upon a time');
      expect(count, greaterThan(0));
    });

    test('Chat interface via ChatSession', () async {
      if (!engine.isReady) {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(
            contextSize: 256,
            logLevel: LlamaLogLevel.none,
          ),
        );
      }

      final messages = [
        const LlamaChatMessage.text(role: LlamaChatRole.user, content: 'Hi'),
      ];
      final result = await ChatSession.singleTurn(
        engine,
        messages,
        params: const GenerationParams(maxTokens: 10),
      );
      expect(result, isNotEmpty);
      print('Chat Response: "$result"');
    });

    test('Cancel generation', () async {
      if (!engine.isReady) {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(
            contextSize: 256,
            logLevel: LlamaLogLevel.none,
          ),
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
    });

    test('loadModelFromUrl throws Unimplemented on Native', () async {
      expect(engine.loadModelFromUrl('http://test'), throwsUnimplementedError);
    });

    test('getContextSize prefers active context over metadata', () async {
      // Force reload with a new context size to verify dynamic reporting
      await engine.loadModel(
        modelFile.path,
        modelParams: const ModelParams(
          contextSize: 512,
          logLevel: LlamaLogLevel.none,
        ),
      );
      final size = await engine.getContextSize();
      expect(size, 512);
    });

    test('Error when not initialized', () async {
      final freshBackend = LlamaBackend();
      final freshEngine = LlamaEngine(freshBackend);
      expect(
        freshEngine.generate('test'),
        emitsError(isA<LlamaContextException>()),
      );
      await freshEngine.dispose();
    });
  });
}
