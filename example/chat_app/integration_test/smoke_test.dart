import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/common/loader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Native Smoke Test', () {
    testWidgets('Verify native library load and basic inference', (
      tester,
    ) async {
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
          print('Downloading tiny model for inference test...');
          final response = await http.get(Uri.parse(modelUrl));
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

        print('Running 1-token generation check...');
        final stream = engine.generate(
          'Hello',
          params: const GenerationParams(maxTokens: 1),
        );
        final tokens = await stream.toList();

        print('Inference output: ${tokens.join()}');
        expect(tokens, isNotEmpty);

        await engine.dispose();
        llama_backend_free();
        print('SMOKE TEST SUCCESS');
      } catch (e, st) {
        print('SMOKE TEST FAILED: $e');
        print(st);
        fail('Smoke test failed: $e');
      }
    });
  });
}
