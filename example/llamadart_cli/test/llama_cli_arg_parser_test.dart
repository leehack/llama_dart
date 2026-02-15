import 'package:llamadart_cli_example/llamadart_cli.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaCliArgParser', () {
    test('parses unsloth GLM llama.cpp style command', () {
      final parser = LlamaCliArgParser();

      final config = parser.parse([
        '-hf',
        'unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL',
        '--jinja',
        '--ctx-size',
        '16384',
        '--temp',
        '1.0',
        '--top-p',
        '0.95',
        '--min-p',
        '0.01',
        '--fit',
        'on',
      ]);

      expect(config.huggingFaceSpec, 'unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL');
      expect(config.modelPathOrUrl, isNull);
      expect(config.contextSize, 16384);
      expect(config.temperature, 1.0);
      expect(config.topP, 0.95);
      expect(config.minP, 0.01);
      expect(config.fitContext, isTrue);
      expect(config.jinja, isTrue);
      expect(config.interactive, isTrue);
      expect(config.simpleIo, isFalse);
      expect(config.color, isTrue);
    });

    test('converts multi-letter short options', () {
      final parser = LlamaCliArgParser();

      final config = parser.parse([
        '--model',
        'model.gguf',
        '-ngl',
        '48',
        '-c',
        '8192',
        '-n',
        '256',
        '-tb',
        '2',
      ]);

      expect(config.modelPathOrUrl, 'model.gguf');
      expect(config.gpuLayers, 48);
      expect(config.contextSize, 8192);
      expect(config.maxTokens, 256);
      expect(config.threadsBatch, 2);
    });

    test('accepts common long alias spellings', () {
      final parser = LlamaCliArgParser();

      final config = parser.parse([
        '--hf',
        'unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL',
        '--ctx_size',
        '4096',
        '--n-predict',
        '512',
        '--top_p=1.0',
        '--min_p=0.01',
        '--repeat_penalty',
        '1.0',
        '--simple_io',
      ]);

      expect(config.huggingFaceSpec, 'unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL');
      expect(config.contextSize, 4096);
      expect(config.maxTokens, 512);
      expect(config.topP, 1.0);
      expect(config.minP, 0.01);
      expect(config.repeatPenalty, 1.0);
      expect(config.simpleIo, isTrue);
    });

    test('prompt disables interactive by default', () {
      final parser = LlamaCliArgParser();

      final config = parser.parse(['--model', 'model.gguf', '--prompt', 'Hi']);

      expect(config.prompt, 'Hi');
      expect(config.interactive, isFalse);
    });

    test('prompt file disables interactive by default', () {
      final parser = LlamaCliArgParser();

      final config = parser.parse(['--model', 'model.gguf', '--file', 'p.txt']);

      expect(config.promptFile, 'p.txt');
      expect(config.interactive, isFalse);
    });

    test('supports simple-io, instruct, and no-color flags', () {
      final parser = LlamaCliArgParser();

      final config = parser.parse([
        '--model',
        'model.gguf',
        '--simple-io',
        '--instruct',
        '--no-color',
      ]);

      expect(config.simpleIo, isTrue);
      expect(config.instruct, isTrue);
      expect(config.color, isFalse);
    });

    test('throws when prompt and prompt file are both set', () {
      final parser = LlamaCliArgParser();

      expect(
        () => parser.parse([
          '--model',
          'model.gguf',
          '--prompt',
          'hello',
          '--file',
          'p.txt',
        ]),
        throwsA(isA<LlamaCliArgException>()),
      );
    });

    test('throws when model source is missing', () {
      final parser = LlamaCliArgParser();

      expect(() => parser.parse([]), throwsA(isA<LlamaCliArgException>()));
    });
  });
}
