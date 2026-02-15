@Tags(<String>['local-only'])
library;

import 'dart:io';

import 'package:llamadart_cli_example/llamadart_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Real parity gate', () {
    final config = _ParityGateConfig.fromEnvironment();

    test('keeps flappy-bird scripted parity with llama.cpp', () async {
      final skipReason = config.skipReason;
      if (skipReason != null) {
        // ignore: avoid_print
        print(skipReason);
        return;
      }

      final promptsFile = File(config.promptsFilePath);
      final prompts = await promptsFile.readAsLines().then(
        (lines) => lines
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false),
      );

      expect(prompts, isNotEmpty, reason: 'Prompt script is empty.');

      final harness = ParityHarness(
        timeout: Duration(milliseconds: config.timeoutMs),
        maxDeltas: 30,
        maxCapturedBytes: 2 * 1024 * 1024,
      );

      final report = await harness.run(
        llamaCpp: ParityCommand(
          command: config.llamaCppCommand,
          workingDirectory: Directory.current.path,
        ),
        llamaDart: ParityCommand(
          command: config.llamaDartCommand,
          workingDirectory: Directory.current.path,
        ),
        prompts: prompts,
        appendExitCommand: true,
      );

      expect(report.isMatch, isTrue, reason: _mismatchReason(report));
    });
  });
}

String _mismatchReason(ParityReport report) {
  final lines = <String>[
    'llama.cpp exit=${report.llamaCpp.exitCode} timeout=${report.llamaCpp.timedOut}',
    'llamadart exit=${report.llamaDart.exitCode} timeout=${report.llamaDart.timedOut}',
    if (report.deltas.isEmpty) 'No text deltas, process status mismatch only.',
    for (final delta in report.deltas.take(5))
      'line ${delta.lineNumber}: expected="${delta.expected}" actual="${delta.actual}"',
  ];
  return lines.join('\n');
}

class _ParityGateConfig {
  final String? skipReason;
  final String promptsFilePath;
  final int timeoutMs;
  final String llamaCppCommand;
  final String llamaDartCommand;

  const _ParityGateConfig({
    required this.skipReason,
    required this.promptsFilePath,
    required this.timeoutMs,
    required this.llamaCppCommand,
    required this.llamaDartCommand,
  });

  factory _ParityGateConfig.fromEnvironment() {
    final env = Platform.environment;

    final modelPath = _normalizePath(
      env['LLAMADART_PARITY_MODEL'] ??
          p.join('models', 'GLM-4.7-Flash-UD-Q4_K_XL.gguf'),
    );
    final llamaCliPath = _normalizePath(
      env['LLAMADART_PARITY_LLAMA_CPP_CLI'] ??
          p.join('.parity_tools', 'llama.cpp', 'build', 'bin', 'llama-cli'),
    );
    final llamadartCliPath = _normalizePath(
      env['LLAMADART_PARITY_LLAMADART_CLI'] ??
          p.join(
            '.parity_tools',
            'build_cli',
            'bundle',
            'bin',
            'llamadart_cli',
          ),
    );
    final promptsFilePath = _normalizePath(
      env['LLAMADART_PARITY_PROMPTS_FILE'] ??
          p.join('tool', 'parity_prompts', 'flappy_bird.txt'),
    );
    final timeoutMs =
        int.tryParse(env['LLAMADART_PARITY_TIMEOUT_MS'] ?? '') ?? 900000;

    final missing = <String>[];
    if (!_fileExists(llamaCliPath)) {
      missing.add('llama.cpp cli: $llamaCliPath');
    }
    if (!_fileExists(llamadartCliPath)) {
      missing.add('llamadart cli: $llamadartCliPath');
    }
    if (!_fileExists(modelPath)) {
      missing.add('model: $modelPath');
    }
    if (!_fileExists(promptsFilePath)) {
      missing.add('prompts file: $promptsFilePath');
    }

    final skipReason = missing.isEmpty
        ? null
        : 'Missing local parity dependencies: ${missing.join(' | ')}';

    final llamaCppCommand =
        '${_shellQuote(llamaCliPath)} '
        '--model ${_shellQuote(modelPath)} '
        '--ctx-size 8192 '
        '--seed 3407 '
        '--temp 1.0 '
        '--top-p 0.95 '
        '--min-p 0.01 '
        '--repeat-penalty 1.0 '
        '--fit on '
        '--jinja '
        '--simple-io '
        '--no-show-timings '
        '--log-disable '
        '-n 16';

    final llamaDartCommand =
        '${_shellQuote(llamadartCliPath)} '
        '--model ${_shellQuote(modelPath)} '
        '--ctx-size 8192 '
        '--seed 3407 '
        '--temp 1.0 '
        '--top-p 0.95 '
        '--min-p 0.01 '
        '--repeat-penalty 1.0 '
        '--fit on '
        '--jinja '
        '--simple-io '
        '-n 16';

    return _ParityGateConfig(
      skipReason: skipReason,
      promptsFilePath: promptsFilePath,
      timeoutMs: timeoutMs,
      llamaCppCommand: llamaCppCommand,
      llamaDartCommand: llamaDartCommand,
    );
  }
}

String _normalizePath(String path) {
  if (p.isAbsolute(path)) {
    return p.normalize(path);
  }
  return p.normalize(p.join(Directory.current.path, path));
}

bool _fileExists(String path) => File(path).existsSync();

String _shellQuote(String value) {
  final escaped = value.replaceAll("'", "'\"'\"'");
  return "'$escaped'";
}
