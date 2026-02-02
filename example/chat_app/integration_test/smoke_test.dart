import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Native Smoke Test', () {
    testWidgets('Verify native library load and basic inference', (
      tester,
    ) async {
      try {
        // 1. Basic Init Check
        llama_backend_init();

        final sysInfoPtr = llama_print_system_info();
        expect(sysInfoPtr, isNotNull);
        sysInfoPtr.cast<Utf8>().toDartString();

        // 2. Download Tiny Model
        final modelUrl =
            'https://huggingface.co/ggml-org/tiny-llamas/resolve/main/stories15M.gguf';

        final Directory dataDir;
        if (Platform.isAndroid || Platform.isIOS) {
          dataDir = await getApplicationDocumentsDirectory();
        } else {
          dataDir = Directory(path.join(Directory.current.path, 'models'));
          if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
        }

        final modelPath = path.join(dataDir.path, 'test_model.gguf');
        final modelFile = File(modelPath);

        if (!modelFile.existsSync()) {
          final response = await http.get(Uri.parse(modelUrl));
          await modelFile.writeAsBytes(response.bodyBytes);
        }

        // 3. Full Inference Pipeline Test
        final backend = LlamaBackend();
        final engine = LlamaEngine(backend);

        await engine.loadModel(modelPath);
        expect(engine.isReady, isTrue);

        final stream = engine.generate(
          'Hello',
          params: const GenerationParams(maxTokens: 1),
        );
        final tokens = await stream.toList();

        expect(tokens, isNotEmpty);

        await engine.dispose();
        llama_backend_free();
      } catch (e) {
        fail('Smoke test failed: $e');
      }
    });
  });
}
