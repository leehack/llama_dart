import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:llamadart/llamadart.dart';

void main() async {
  const modelPath = 'models/moondream2-q5k.gguf';
  const mmProjPath = 'models/moondream2-mmproj.gguf';
  const imagePath = 'test_assets/toy.jpg';

  print('--- Final Moondream Test ---');
  final engine = LlamaEngine(NativeLlamaBackend());

  try {
    print('Loading model...');
    await engine.loadModel(modelPath);
    await engine.loadMultimodalProjector(mmProjPath);

    print('\n--- Testing Vision ---');
    final visionParts = [LlamaImageContent(path: path.absolute(imagePath))];
    // Try Moondream standard format
    final visionPrompt =
        '<__media__>\n\nQuestion: Describe this image accurately.\n\nAnswer:';

    await for (final token in engine.generate(
      visionPrompt,
      parts: visionParts,
    )) {
      stdout.write(token);
    }
    print('\n');

    print('\n--- Done ---');
  } catch (e) {
    print('Error: $e');
  } finally {
    await engine.dispose();
  }
}
