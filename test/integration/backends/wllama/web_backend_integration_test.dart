@TestOn('browser')
library;

import 'package:test/test.dart';
import 'package:llamadart/src/backends/wllama/wllama_backend.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';

void main() {
  group('WebLlamaBackend Integration', () {
    late WebLlamaBackend backend;

    setUp(() {
      backend = WebLlamaBackend();
    });

    tearDown(() async {
      await backend.dispose();
    });

    test('Properties and initial state', () async {
      expect(backend.isReady, isFalse);
      expect(await backend.getBackendName(), contains('WASM'));
      expect(await backend.isGpuSupported(), isFalse);
    });

    test('Dispose works', () async {
      await backend.dispose();
      expect(backend.isReady, isFalse);
    });

    test('setLogLevel is no-op but callable', () async {
      await backend.setLogLevel(LlamaLogLevel.debug);
    });
  });
}
