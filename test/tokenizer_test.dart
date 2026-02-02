@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import 'test_helper.dart';
import 'dart:io';

void main() {
  group('LlamaTokenizer (Integration)', () {
    late File modelFile;
    late LlamaBackend backend;
    int? modelHandle;
    late LlamaTokenizer tokenizer;

    setUpAll(() async {
      modelFile = await TestHelper.getTestModel();
      backend = LlamaBackend();
      modelHandle = await backend.modelLoad(
        modelFile.path,
        const ModelParams(logLevel: LlamaLogLevel.none),
      );
      tokenizer = LlamaTokenizer(backend, modelHandle!);
    });

    tearDownAll(() async {
      if (modelHandle != null) {
        await backend.modelFree(modelHandle!);
      }
      await backend.dispose();
    });

    test('real tokenization', () async {
      final tokens = await tokenizer.encode('Hello world');
      expect(tokens, isNotEmpty);

      final text = await tokenizer.decode(tokens);
      expect(text.toLowerCase(), contains('hello world'));
    });

    test('count matches encode length', () async {
      const text = 'Testing token count';
      final tokens = await tokenizer.encode(text);
      final count = await tokenizer.count(text);
      expect(count, tokens.length);
    });
  });
}
