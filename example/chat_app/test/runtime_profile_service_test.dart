import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_chat_example/services/runtime_profile_service.dart';

void main() {
  const service = RuntimeProfileService();

  group('RuntimeProfileService', () {
    test('computes runtime diagnostics fields', () {
      final diagnostics = service.buildDiagnostics(
        metadata: const <String, String>{
          'llamadart.webgpu.n_gpu_layers': '32',
          'llamadart.webgpu.n_threads': '8',
        },
      );

      expect(diagnostics.runtimeGpuLayers, 32);
      expect(diagnostics.runtimeThreads, 8);
    });

    test('returns fallback estimate when VRAM unavailable', () {
      final estimate = service.estimateDynamicSettings(
        totalVramBytes: 0,
        freeVramBytes: 0,
        isWeb: false,
        preferredBackend: GpuBackend.cpu,
        currentContextSize: 4096,
        backendInfo: 'CPU',
      );

      expect(estimate.gpuLayers, 0);
      expect(estimate.contextSize, 4096);
    });

    test('returns VRAM-based estimate when data is available', () {
      final estimate = service.estimateDynamicSettings(
        totalVramBytes: 8 * 1024 * 1024 * 1024,
        freeVramBytes: 4 * 1024 * 1024 * 1024,
        isWeb: false,
        preferredBackend: GpuBackend.auto,
        currentContextSize: 8192,
      );

      expect(estimate.gpuLayers, greaterThan(0));
      expect(estimate.contextSize, anyOf(2048, 4096));
    });
  });
}
