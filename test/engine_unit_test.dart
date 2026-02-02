import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  group('LlamaEngine Units (Logic only)', () {
    test('ModelParams copyWith', () {
      const params = ModelParams(contextSize: 1024);
      final updated = params.copyWith(gpuLayers: 10);
      expect(updated.contextSize, 1024);
      expect(updated.gpuLayers, 10);
    });

    test('GenerationParams copyWith', () {
      const params = GenerationParams(temp: 0.5);
      final updated = params.copyWith(maxTokens: 100);
      expect(updated.temp, 0.5);
      expect(updated.maxTokens, 100);
    });

    test('LlamaException toString', () {
      final ex = LlamaModelException('failed', 'io error');
      expect(ex.toString(), contains('LlamaException: failed (io error)'));
    });
  });
}
