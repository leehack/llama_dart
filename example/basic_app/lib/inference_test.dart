import 'dart:io';
import 'package:llamadart/llamadart.dart';

/// A Helper class to run inference tests.
class InferenceTest {
  final LlamaService _service;

  /// Creates an [InferenceTest] with the given [LlamaService].
  InferenceTest(this._service);

  /// Runs the inference test on the model at [modelPath].
  Future<void> run(String modelPath, {String prompt = "Hello, world!"}) async {
    print('\nStarting Inference Test...');
    print('Model: $modelPath');

    try {
      if (!File(modelPath).existsSync()) {
        throw Exception('Model file not found: $modelPath');
      }

      print('Loading model...');
      await _service.init(modelPath);
      print('Model loaded successfully.');

      print('Prompt: "$prompt"');
      print('Response:');

      final buffer = StringBuffer();
      await for (final token in _service.generate(prompt)) {
        stdout.write(token);
        buffer.write(token);
      }

      print('\n\nInference complete.');

      if (buffer.isEmpty) {
        throw Exception('Inference produced no output.');
      }

      print('Test Passed! ✅');
    } catch (e) {
      print('Test Failed! ❌');
      print('Error: $e');
      rethrow;
    } finally {
      // Note: service disposal is handled by the caller or typical lifecycle
      await _service.dispose();
    }
  }
}
