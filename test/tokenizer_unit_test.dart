import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import 'test_helper.dart';

void main() {
  group('LlamaTokenizer (Unit)', () {
    late LlamaTokenizer tokenizer;
    late MockLlamaBackend backend;

    setUp(() {
      backend = MockLlamaBackend();
      tokenizer = LlamaTokenizer(backend, 1);
    });

    tearDown(() async {
      await backend.dispose();
    });

    test('encode', () async {
      final tokens = await tokenizer.encode('test');
      expect(tokens, [1, 2, 3]);
    });

    test('decode', () async {
      final text = await tokenizer.decode([1, 2, 3]);
      expect(text, 'mock text');
    });

    test('count', () async {
      final count = await tokenizer.count('test');
      expect(count, 3);
    });
  });
}
