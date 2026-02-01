import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:llamadart/llamadart.dart';

/// Diagnostic script for Gemma 3 (ISWA) multimodal functionality.
/// Supports text, image, and audio input.
void main() async {
  const modelPath = 'models/gemma-3-4b-it-Q4_K_M.gguf';
  const mmProjPath = 'models/gemma-3-unsloth-mmproj.gguf';
  const imagePath = 'test_assets/toy.jpg';
  const audioPath = 'test_assets/jfk.wav';

  if (!File(modelPath).existsSync() || !File(mmProjPath).existsSync()) {
    print('Error: Gemma 3 4B model files not found in models/ directory.');
    print('Please download them using these commands:');
    print('  mkdir -p models');
    print(
      '  curl -L "https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf?download=true" -o $modelPath',
    );
    print(
      '  curl -L "https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF/resolve/main/mmproj-model-f16.gguf?download=true" -o $mmProjPath',
    );
    return;
  }

  print('--- Initializing Llama Engine (Gemma 3 ISWA) ---');
  final engine = LlamaEngine(NativeLlamaBackend());

  try {
    print('Loading model: $modelPath...');
    // Gemma 3 4B is relatively large, ensure enough memory/GPU layers
    await engine.loadModel(
      modelPath,
      modelParams: const ModelParams(gpuLayers: 99),
    );

    print('Loading multimodal projector: $mmProjPath...');
    await engine.loadMultimodalProjector(mmProjPath);

    final vision = await engine.supportsVision;
    final audio = await engine.supportsAudio;
    print('Vision support: $vision');
    print('Audio support: $audio');

    // 1. Test Vision
    if (vision && File(imagePath).existsSync()) {
      print('\n--- Testing Vision ---');
      final parts = [
        LlamaImageContent(bytes: File(imagePath).readAsBytesSync()),
      ];
      const prompt = '<__media__>\nDescribe this image.';

      print('Prompt: $prompt\n');

      await for (final token in engine.generate(prompt, parts: parts)) {
        stdout.write(token);
      }
      print('\n');
    }

    // 2. Test Audio (if asset exists)
    if (audio && File(audioPath).existsSync()) {
      print('\n--- Testing Audio ---');
      final parts = [LlamaAudioContent(path: path.absolute(audioPath))];
      const prompt = '<__media__>\nTranscribe the audio.';
      print('Prompt: $prompt\n');

      await for (final token in engine.generate(prompt, parts: parts)) {
        stdout.write(token);
      }
      print('\n');
    }

    print('\n--- All Tests Complete ---');
  } catch (e) {
    print('\nError during inference: $e');
  } finally {
    await engine.dispose();
  }
}
