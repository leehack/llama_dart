import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:llamadart/llamadart.dart';

/// Diagnostic script for checking multimodal functionality (Vision and Audio).
/// This example shows how to load a model and its projector, and verify
/// support for different modalities.
void main() async {
  // Example paths for Gemma 3 or similar multimodal models
  const modelPath = 'models/gemma-3-4b-it-Q4_K_M.gguf';
  const mmProjPath = 'models/gemma-3-unsloth-mmproj.gguf';
  const imagePath = 'test_assets/toy.jpg';
  const audioPath = 'test_assets/jfk.wav';

  print('--- Llama Engine Multimodal Diagnostics ---');

  if (!File(modelPath).existsSync()) {
    print('Warning: Model file not found at $modelPath');
    print(
      'Testing with default paths... please update script with your model paths.',
    );
  }

  final engine = LlamaEngine(LlamaBackend());

  try {
    print('Loading model: $modelPath...');
    await engine.loadModel(
      modelPath,
      modelParams: const ModelParams(gpuLayers: 99),
    );

    if (File(mmProjPath).existsSync()) {
      print('Loading multimodal projector: $mmProjPath...');
      await engine.loadMultimodalProjector(mmProjPath);
    } else {
      print('Skip loading projector: $mmProjPath not found.');
    }

    final vision = await engine.supportsVision;
    final audio = await engine.supportsAudio;
    print('Vision support detected: $vision');
    print('Audio support detected: $audio');

    // 1. Test Vision if supported
    if (vision && File(imagePath).existsSync()) {
      print('\n--- Testing Vision ---');
      final parts = [
        LlamaImageContent(bytes: File(imagePath).readAsBytesSync()),
      ];
      const prompt = '<__media__>\nDescribe this image.';

      print('Prompt: $prompt\n');
      stdout.write('Response: ');
      await for (final token in engine.generate(prompt, parts: parts)) {
        stdout.write(token);
      }
      print('\n');
    }

    // 2. Test Audio if supported
    if (audio && File(audioPath).existsSync()) {
      print('\n--- Testing Audio ---');
      final parts = [LlamaAudioContent(path: path.absolute(audioPath))];
      const prompt = '<__media__>\nTranscribe the audio.';
      print('Prompt: $prompt\n');
      stdout.write('Response: ');
      await for (final token in engine.generate(prompt, parts: parts)) {
        stdout.write(token);
      }
      print('\n');
    }

    print('\n--- Diagnostics Complete ---');
  } catch (e) {
    print('\nError during diagnostic: $e');
  } finally {
    await engine.dispose();
  }
}
