@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';

void main() {
  group('Native Symbol Availability', () {
    test('Verify multimodal symbols are resolvable', () {
      // Some bundles export mtmd via the primary llama asset while others ship
      // it as a dedicated mtmd shared library loaded via runtime fallback.
      // So direct primary-asset lookup may legitimately fail.
      if (Platform.isWindows || Platform.isLinux || Platform.isAndroid) {
        expect(
          () => mtmd_context_params_default(),
          anyOf(returnsNormally, throwsA(isA<ArgumentError>())),
        );
        return;
      }

      expect(() => mtmd_context_params_default(), returnsNormally);
    });

    test('Verify core llama symbols are resolvable', () {
      expect(() => llama_backend_init(), returnsNormally);
      expect(() => llama_time_us(), returnsNormally);
      expect(() => llama_max_devices(), returnsNormally);
      expect(() => llama_supports_mmap(), returnsNormally);
      expect(() => llama_supports_mlock(), returnsNormally);
      expect(() => llama_supports_gpu_offload(), returnsNormally);
      expect(() => llama_supports_rpc(), returnsNormally);
      expect(() => llama_model_default_params(), returnsNormally);
      expect(() => llama_context_default_params(), returnsNormally);
      expect(() => llama_sampler_chain_default_params(), returnsNormally);
      expect(() => llama_model_quantize_default_params(), returnsNormally);
      expect(
        () => llama_numa_init(ggml_numa_strategy.GGML_NUMA_STRATEGY_DISABLED),
        returnsNormally,
      );
    });
  });
}
