import 'package:llamadart_cli_example/llamadart_cli.dart';
import 'package:test/test.dart';

void main() {
  group('HfModelSpec', () {
    test('parses repository and quant hint', () {
      final spec = HfModelSpec.parse('unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL');

      expect(spec.repository, 'unsloth/GLM-4.7-Flash-GGUF');
      expect(spec.fileHint, 'UD-Q4_K_XL');
    });

    test('parses repository only', () {
      final spec = HfModelSpec.parse('owner/repo');

      expect(spec.repository, 'owner/repo');
      expect(spec.fileHint, isNull);
    });
  });

  group('selectBestGgufFile', () {
    test('picks file by normalized quant hint', () {
      final selected = selectBestGgufFile([
        'GLM-4.7-Flash-IQ2_XS.gguf',
        'GLM-4.7-Flash-UD-Q4_K_XL.gguf',
      ], hint: 'UD-Q4_K_XL');

      expect(selected, 'GLM-4.7-Flash-UD-Q4_K_XL.gguf');
    });

    test('returns first sorted gguf when hint is missing', () {
      final selected = selectBestGgufFile(['b.gguf', 'a.gguf']);

      expect(selected, 'a.gguf');
    });

    test('throws when no gguf file exists', () {
      expect(
        () => selectBestGgufFile(['README.md', 'config.json']),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
