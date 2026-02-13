@TestOn('browser')
library;

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/web/web_backend.dart';
import 'package:test/test.dart';

void main() {
  test('createBackend returns WebAutoBackend', () {
    final backend = createBackend();

    expect(backend, isA<LlamaBackend>());
    expect(backend, isA<WebAutoBackend>());
  });
}
