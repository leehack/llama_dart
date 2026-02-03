@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:llamadart/src/common/loader.dart';

void main() {
  group('Native Symbol Availability', () {
    test('Verify multimodal symbols are resolvable', () {
      // These calls will throw an ArgumentError if the symbol is missing
      // because they are resolved by the Dart VM using Native Assets.

      expect(
        () => mtmd_context_params_default(),
        returnsNormally,
        reason: 'mtmd_context_params_default symbol is missing.',
      );

      // We don't call mtmd_init_from_file here because it requires a model,
      // but just resolving mtmd_context_params_default is enough to prove mtmd is linked.
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
      expect(() => llama_numa_init(ggml_numa_strategy.GGML_NUMA_STRATEGY_DISABLED), returnsNormally);
    });
  });
}
