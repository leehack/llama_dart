import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  group('GenerationParams grammar', () {
    test('defaults grammarRoot to root', () {
      final params = GenerationParams(grammar: 'root ::= "test"');
      expect(params.grammarRoot, 'root');
    });

    test('copyWith preserves grammar', () {
      final params = GenerationParams(grammar: 'root ::= "a" | "b"');
      final copied = params.copyWith(maxTokens: 100);
      expect(copied.grammar, 'root ::= "a" | "b"');
      expect(copied.grammarRoot, 'root');
    });

    test('copyWith can update grammar', () {
      final params = GenerationParams(grammar: 'root ::= "a"');
      final copied = params.copyWith(grammar: 'root ::= "b"');
      expect(copied.grammar, 'root ::= "b"');
    });

    test('copyWith can update grammarRoot', () {
      final params = GenerationParams(grammarRoot: 'root');
      final copied = params.copyWith(grammarRoot: 'main');
      expect(copied.grammarRoot, 'main');
    });
  });
}
