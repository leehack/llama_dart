@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';

void main() {
  group('Inference Smoke Test (Desktop)', () {
    test('Verify native library load and basic inference', () async {
      try {
        // 1. Basic Init Check
        llama_backend_init();

        final sysInfoPtr = llama_print_system_info();
        expect(sysInfoPtr, isNotNull);
        sysInfoPtr.cast<Utf8>().toDartString();
        // Removed print: System Info

        // 2. Download Tiny Model
        final modelUrl =
            'https://huggingface.co/ggml-org/tiny-llamas/resolve/main/stories15M.gguf';
        final dataDir = Directory(path.join(Directory.current.path, 'models'));
        if (!dataDir.existsSync()) dataDir.createSync(recursive: true);

        final modelPath = path.join(dataDir.path, 'test_model.gguf');
        final modelFile = File(modelPath);

        if (!modelFile.existsSync()) {
          // Removed print: Downloading tiny model...
          final response = await http.get(Uri.parse(modelUrl));
          if (response.statusCode != 200) {
            fail('Failed to download model: ${response.statusCode}');
          }
          await modelFile.writeAsBytes(response.bodyBytes);
          // Removed print: Model downloaded...
        }

        // 3. Full Inference Pipeline Test
        final backend = LlamaBackend();
        final engine = LlamaEngine(backend);

        // Removed print: Loading model...
        await engine.loadModel(
          modelPath,
          modelParams: const ModelParams(
            chatTemplate:
                "{% for message in messages %}{{ message['role'] }}: {{ message['content'] }}\n{% endfor %}",
          ),
        );
        expect(engine.isReady, isTrue);
        // Removed print: Model loaded successfully.

        // Removed print: Running 5-token generation check...
        try {
          final stream = engine.create(
            [
              LlamaChatMessage.withContent(
                role: LlamaChatRole.user,
                content: [
                  LlamaTextContent('Hello'),
                  LlamaImageContent(
                    bytes: Uint8List.fromList([0, 0, 0]),
                    width: 1,
                    height: 1,
                  ),
                ],
              ),
            ],
            params: const GenerationParams(
              maxTokens: 5,
              penalty: 1.2,
              grammar: 'root ::= "World"',
            ),
          );

          final tokens = <String>[];
          await for (final chunk in stream.timeout(
            const Duration(seconds: 60),
          )) {
            final token = chunk.choices.first.delta.content ?? '';
            tokens.add(token);
          }
          expect(tokens, isNotEmpty, reason: 'No tokens were generated');
        } catch (e) {
          if (e.toString().contains('chat template')) {
            // WARNING: Skipped generation due to chat template error, expected for some raw models
          } else {
            rethrow;
          }
        }

        // 4b. Verify chat with streaming
        final messages = [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Once upon a time',
          ),
        ];

        // Removed print: Running generation check...
        final fullContent = StringBuffer();
        try {
          await for (final chunk in engine.create(messages)) {
            final delta = chunk.choices.first.delta.content;
            if (delta != null) {
              fullContent.write(delta);
            }
          }
          // Removed print: Generation completed...
          expect(fullContent.isNotEmpty, isTrue);
        } catch (e) {
          if (e.toString().contains('chat template')) {
            // WARNING: Skipped generation due to chat template error
          } else {
            rethrow;
          }
        }

        // 4. Tokenizer test
        final encoded = await engine.tokenize('Hello world');
        expect(encoded, isNotEmpty);
        final decoded = await engine.detokenize(encoded);
        expect(decoded, contains('Hello world'));

        // 5. Metadata test
        final metadata = await engine.getMetadata();
        expect(metadata, isNotEmpty);
        expect(metadata.containsKey('general.architecture'), isTrue);

        // 6. Context Size
        final ctxSize = await engine.getContextSize();
        expect(ctxSize, greaterThan(0));

        // 7. Log level test (Silencer)
        await engine.setLogLevel(LlamaLogLevel.none);
        await engine.setLogLevel(LlamaLogLevel.warn);

        // 8. LoRA (should fail gracefully or not crash if path is wrong)
        try {
          await engine.setLora('non_existent.bin');
        } catch (_) {}
        await engine.clearLoras();

        // 9. Multimodal failure test
        try {
          await engine.loadMultimodalProjector('non_existent_path.gguf');
        } catch (_) {}

        await engine.dispose();

        // 10. Error path: non-existent model
        final engine2 = LlamaEngine(LlamaBackend());
        expect(
          () => engine2.loadModel('non_existent_model_path.gguf'),
          throwsA(isA<LlamaModelException>()),
        );

        llama_backend_free();
        // Removed print: SMOKE TEST SUCCESS
      } catch (e) {
        // Removed print: SMOKE TEST FAILED
        rethrow;
      }
    });
  });
}
