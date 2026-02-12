@TestOn('browser')
library;

import 'package:llamadart/src/backends/wllama/interop.dart';
import 'package:test/test.dart';

void main() {
  test('Wllama interop types are available', () {
    expect(Wllama, isNotNull);
    expect(WllamaConfig, isNotNull);
    expect(LoadModelOptions, isNotNull);
    expect(CompletionOptions, isNotNull);
  });
}
