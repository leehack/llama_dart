import 'dart:io';
import 'package:llamadart/llamadart.dart';

/// Example of using the multimodal chat API with vision support.
void main() async {
  // Use a multimodal model like Moondream or Qwen2-VL
  const modelPath = 'models/moondream2-q5k.gguf';
  const mmProjPath = 'models/moondream2-mmproj.gguf';
  const imagePath = 'test_assets/toy.jpg';

  if (!File(modelPath).existsSync() || !File(mmProjPath).existsSync()) {
    print('Error: Model or mmproj file not found.');
    print(
      'Please ensure models/moondream2-q5k.gguf and models/moondream2-mmproj.gguf exist.',
    );
    return;
  }

  print('--- Multimodal Chat Example ---');
  final engine = LlamaEngine(LlamaBackend());

  try {
    print('Loading model...');
    await engine.loadModel(modelPath);

    print('Loading multimodal projector...');
    await engine.loadMultimodalProjector(mmProjPath);

    print('Sending multimodal chat request...');
    final messages = [
      LlamaChatMessage.multimodal(
        role: LlamaChatRole.user,
        parts: [
          if (File(imagePath).existsSync()) LlamaImageContent(path: imagePath),
          const LlamaTextContent('What is in this image? Describe it briefly.'),
        ],
      ),
    ];

    // Use ChatSession.singleTurnStream for stateless chat
    final response = ChatSession.singleTurnStream(engine, messages);

    stdout.write('Assistant: ');
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
