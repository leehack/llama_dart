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
    });
  });
}
