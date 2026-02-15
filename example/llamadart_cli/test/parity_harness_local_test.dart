@Tags(<String>['local-only'])
library;

import 'dart:io';

import 'package:llamadart_cli_example/llamadart_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ParityHarness local integration', () {
    late String scriptPath;
    late String dartExecutable;

    setUpAll(() {
      scriptPath = p.join('test', 'fixtures', 'mock_cli.dart');
      dartExecutable = Platform.resolvedExecutable;
    });

    test('reports match for equivalent transcript behavior', () async {
      const harness = ParityHarness(timeout: Duration(seconds: 10));

      final report = await harness.run(
        llamaCpp: ParityCommand(
          command: '$dartExecutable $scriptPath --style llama',
          workingDirectory: Directory.current.path,
        ),
        llamaDart: ParityCommand(
          command: '$dartExecutable $scriptPath --style dart',
          workingDirectory: Directory.current.path,
        ),
        prompts: const <String>['alpha', 'beta'],
      );

      expect(report.llamaCpp.exitCode, 0);
      expect(report.llamaDart.exitCode, 0);
      expect(report.deltas, isEmpty);
      expect(report.isMatch, isTrue);
    });

    test('reports delta list when outputs diverge', () async {
      const harness = ParityHarness(timeout: Duration(seconds: 10));

      final report = await harness.run(
        llamaCpp: ParityCommand(
          command: '$dartExecutable $scriptPath --style llama',
          workingDirectory: Directory.current.path,
        ),
        llamaDart: ParityCommand(
          command: '$dartExecutable $scriptPath --style dart --mismatch',
          workingDirectory: Directory.current.path,
        ),
        prompts: const <String>['alpha', 'beta'],
      );

      expect(report.llamaCpp.exitCode, 0);
      expect(report.llamaDart.exitCode, 0);
      expect(report.deltas, isNotEmpty);
      expect(report.isMatch, isFalse);
      expect(report.deltas.first.lineNumber, 2);
    });
  });
}
