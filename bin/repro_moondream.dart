import 'dart:io';
import 'package:llamadart/llamadart.dart';

void main() async {
  const modelPath = 'models/moondream2-q5k.gguf';
  const mmProjPath = 'models/moondream2-mmproj.gguf';
  const imagePath = 'test_assets/toy.jpg';

  print('--- Repro Moondream Issue ---');
  final engine = LlamaEngine(NativeLlamaBackend());

  try {
    print('Loading model...');
    await engine.loadModel(modelPath);
    await engine.loadMultimodalProjector(mmProjPath);

    print('Sending chat request...');
    final reproMessages = [
      LlamaChatMessage.multimodal(
        role: LlamaChatRole.user,
        parts: [
          LlamaImageContent(path: imagePath),
          const LlamaTextContent('What is in this image?'),
        ],
      ),
    ];

    final response = engine.chat(reproMessages);

    await for (final token in response) {
      stdout.write(token);
    }
    print('\n\n--- Done ---');
  } catch (e) {
    print('Error: $e');
  } finally {
    await engine.dispose();
  }
}
