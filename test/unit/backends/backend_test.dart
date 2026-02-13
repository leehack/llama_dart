import 'package:llamadart/src/backends/backend.dart';
import 'package:test/test.dart';

void main() {
  test('LlamaBackend interface is available', () {
    expect(LlamaBackend, isNotNull);
  });
}
