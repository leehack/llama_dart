import 'dart:io';

import 'package:llamadart_cli_example/llamadart_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('TranscriptNormalizer', () {
    test('matches golden normalized transcript', () async {
      final rawPath = p.join('test', 'fixtures', 'transcript_raw.txt');
      final goldenPath = p.join(
        'test',
        'goldens',
        'transcript_normalized.golden.txt',
      );

      final raw = await File(rawPath).readAsString();
      final expected = await File(goldenPath).readAsString();

      const normalizer = TranscriptNormalizer();
      final normalized = normalizer.normalize(raw);

      expect(normalized, expected.trimRight());
    });
  });

  group('computeDeltas', () {
    test('returns mismatched line list', () {
      final deltas = computeDeltas(
        expected: 'a\nb\nc',
        actual: 'a\nB\nc\nd',
        maxDeltas: 10,
      );

      expect(deltas.length, 2);
      expect(deltas[0].lineNumber, 2);
      expect(deltas[0].expected, 'b');
      expect(deltas[0].actual, 'B');
      expect(deltas[1].lineNumber, 4);
      expect(deltas[1].expected, '<EOF>');
      expect(deltas[1].actual, 'd');
    });
  });
}
