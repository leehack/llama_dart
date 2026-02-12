@TestOn('vm')
library;

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:test/test.dart';

void main() {
  test('createBackend returns a LlamaBackend', () async {
    final backend = createBackend();
    expect(backend, isA<LlamaBackend>());
    await backend.dispose();
  });

  test('NativeLlamaBackend type is available', () {
    expect(NativeLlamaBackend, isNotNull);
  });
}
