@TestOn('vm')
library;

import 'package:llamadart/src/backends/llama_cpp/worker.dart';
import 'package:test/test.dart';

void main() {
  test('llamaWorkerEntry function is available', () {
    expect(llamaWorkerEntry, isA<Function>());
  });
}
