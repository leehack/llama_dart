@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
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
        print('Native backend initialized.');

        final sysInfoPtr = llama_print_system_info();
        expect(sysInfoPtr, isNotNull);
        final sysInfo = sysInfoPtr.cast<Utf8>().toDartString();
        print('System Info: $sysInfo');

        // 2. Download Tiny Model
        final modelUrl =
            'https://huggingface.co/ggml-org/tiny-llamas/resolve/main/stories15M.gguf';
        final dataDir = Directory(path.join(Directory.current.path, 'models'));
        if (!dataDir.existsSync()) dataDir.createSync(recursive: true);

        final modelPath = path.join(dataDir.path, 'test_model.gguf');
        final modelFile = File(modelPath);

        if (!modelFile.existsSync()) {
          print('Downloading tiny model for inference test...');
          final response = await http.get(Uri.parse(modelUrl));
          if (response.statusCode != 200) {
            fail('Failed to download model: ${response.statusCode}');
          }
          await modelFile.writeAsBytes(response.bodyBytes);
          print('Model downloaded to $modelPath');
        }

        // 3. Full Inference Pipeline Test
        final backend = LlamaBackend();
        final engine = LlamaEngine(backend);

        print('Loading model...');
        await engine.loadModel(modelPath);
        expect(engine.isReady, isTrue);
        print('Model loaded successfully.');

        print('Running 5-token generation check...');
        final stream = engine.generate(
          'Hello',
          params: const GenerationParams(maxTokens: 5),
        );

        final tokens = <String>[];
        await for (final token in stream.timeout(const Duration(seconds: 60))) {
          print('Token received: "$token"');
          tokens.add(token);
        }

        print('Total tokens: ${tokens.length}');
        print('Inference output: ${tokens.join()}');
        expect(tokens, isNotEmpty, reason: 'No tokens were generated');

        await engine.dispose();
        llama_backend_free();
        print('SMOKE TEST SUCCESS');
      } catch (e, st) {
        print('SMOKE TEST FAILED: $e');
        print(st);
        rethrow;
      }
    });
  });
}
