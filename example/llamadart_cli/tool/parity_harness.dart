import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:llamadart_cli_example/llamadart_cli.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('llama-cpp-command', help: 'Command used to run llama.cpp CLI.')
    ..addOption(
      'llamadart-command',
      help: 'Command used to run the Dart CLI clone.',
      defaultsTo: 'dart run bin/llamadart_cli.dart',
    )
    ..addOption(
      'prompts-file',
      help: 'Path to a newline-separated prompt script.',
      defaultsTo: 'tool/parity_prompts/flappy_bird.txt',
    )
    ..addMultiOption(
      'prompt',
      help: 'Inline prompts. Can be specified multiple times.',
    )
    ..addOption(
      'working-dir',
      help: 'Working directory used for command execution.',
      defaultsTo: Directory.current.path,
    )
    ..addOption(
      'timeout-ms',
      help: 'Per-command timeout in milliseconds.',
      defaultsTo: '600000',
    )
    ..addOption(
      'max-deltas',
      help: 'Maximum mismatched lines to display.',
      defaultsTo: '50',
    )
    ..addOption(
      'max-captured-kb',
      help: 'Max captured KB for each stdout/stderr stream.',
      defaultsTo: '8192',
    )
    ..addOption(
      'report-dir',
      help: 'Directory where raw/normalized transcripts are written.',
      defaultsTo: '.parity_reports',
    )
    ..addFlag(
      'append-exit',
      help: 'Append `/exit` to the end of stdin script.',
      defaultsTo: true,
    )
    ..addFlag(
      'strict-raw',
      help: 'Compare raw output instead of normalized transcript output.',
      defaultsTo: false,
    )
    ..addFlag(
      'raw-include-stderr',
      help: 'Include stderr in strict raw comparison.',
      defaultsTo: false,
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('Argument error: ${error.message}');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  if (results['help'] as bool) {
    stdout.writeln('llamadart-cli parity harness');
    stdout.writeln(parser.usage);
    stdout.writeln('');
    stdout.writeln('Example:');
    stdout.writeln(
      '  dart run tool/parity_harness.dart '
      '--llama-cpp-command "./llama.cpp/llama-cli --model model.gguf '
      '--ctx-size 16384 --seed 3407 --temp 1.0 --top-p 0.95 --min-p 0.01 '
      '--fit on --jinja"',
    );
    return;
  }

  final llamaCppCommand = _trimmedOrNull(
    results['llama-cpp-command'] as String?,
  );
  if (llamaCppCommand == null) {
    stderr.writeln('Missing required option: --llama-cpp-command');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final workingDirectory = results['working-dir'] as String;
  final timeoutMs = int.tryParse(results['timeout-ms'] as String);
  final maxDeltas = int.tryParse(results['max-deltas'] as String);
  final maxCapturedKb = int.tryParse(results['max-captured-kb'] as String);

  if (timeoutMs == null || timeoutMs <= 0) {
    stderr.writeln('Invalid --timeout-ms value: ${results['timeout-ms']}');
    exitCode = 64;
    return;
  }
  if (maxDeltas == null || maxDeltas <= 0) {
    stderr.writeln('Invalid --max-deltas value: ${results['max-deltas']}');
    exitCode = 64;
    return;
  }
  if (maxCapturedKb == null || maxCapturedKb <= 0) {
    stderr.writeln(
      'Invalid --max-captured-kb value: ${results['max-captured-kb']}',
    );
    exitCode = 64;
    return;
  }

  final prompts = await _resolvePrompts(
    promptsFilePath: results['prompts-file'] as String,
    inlinePrompts: results['prompt'] as List<String>,
  );
  if (prompts.isEmpty) {
    stderr.writeln(
      'No prompts found. Provide --prompt or a non-empty prompts file.',
    );
    exitCode = 64;
    return;
  }

  final harness = ParityHarness(
    timeout: Duration(milliseconds: timeoutMs),
    maxDeltas: maxDeltas,
    maxCapturedBytes: maxCapturedKb * 1024,
  );

  stdout.writeln('Running parity harness...');
  stdout.writeln('working-dir : $workingDirectory');
  stdout.writeln('prompts     : ${prompts.length}');
  stdout.writeln('capture cap : ${maxCapturedKb}KB per stream');
  stdout.writeln('strict-raw  : ${results['strict-raw']}');
  stdout.writeln('raw-stderr  : ${results['raw-include-stderr']}');

  final report = await harness.run(
    llamaCpp: ParityCommand(
      command: llamaCppCommand,
      workingDirectory: workingDirectory,
    ),
    llamaDart: ParityCommand(
      command: results['llamadart-command'] as String,
      workingDirectory: workingDirectory,
    ),
    prompts: prompts,
    appendExitCommand: results['append-exit'] as bool,
    strictRaw: results['strict-raw'] as bool,
    rawIncludeStderr: results['raw-include-stderr'] as bool,
  );

  _printRunSummary(report);

  final reportDir = Directory(p.normalize(results['report-dir'] as String));
  if (!reportDir.existsSync()) {
    reportDir.createSync(recursive: true);
  }

  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final base = p.join(reportDir.path, 'parity_$stamp');

  await File(
    '${base}_llama_cpp.stdout.txt',
  ).writeAsString(report.llamaCpp.stdoutText);
  await File(
    '${base}_llama_cpp.stderr.txt',
  ).writeAsString(report.llamaCpp.stderrText);
  await File(
    '${base}_llamadart.stdout.txt',
  ).writeAsString(report.llamaDart.stdoutText);
  await File(
    '${base}_llamadart.stderr.txt',
  ).writeAsString(report.llamaDart.stderrText);
  await File(
    '${base}_llama_cpp.normalized.txt',
  ).writeAsString(report.normalizedLlamaCpp);
  await File(
    '${base}_llamadart.normalized.txt',
  ).writeAsString(report.normalizedLlamaDart);
  await File('${base}_deltas.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(
      report.deltas
          .map(
            (delta) => {
              'line': delta.lineNumber,
              'expected': delta.expected,
              'actual': delta.actual,
            },
          )
          .toList(growable: false),
    ),
  );

  stdout.writeln('Reports written to: ${reportDir.path}');

  if (!report.isMatch) {
    exitCode = 1;
  }
}

Future<List<String>> _resolvePrompts({
  required String promptsFilePath,
  required List<String> inlinePrompts,
}) async {
  if (inlinePrompts.isNotEmpty) {
    return inlinePrompts
        .map((prompt) => prompt.trim())
        .where((prompt) => prompt.isNotEmpty)
        .toList(growable: false);
  }

  final promptFile = File(promptsFilePath);
  if (!promptFile.existsSync()) {
    return const <String>[];
  }

  final lines = await promptFile.readAsLines();
  return lines
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
}

void _printRunSummary(ParityReport report) {
  stdout.writeln('');
  stdout.writeln('Command results:');
  stdout.writeln(
    '- llama.cpp   exit=${report.llamaCpp.exitCode} '
    'timeout=${report.llamaCpp.timedOut} '
    'elapsed=${report.llamaCpp.elapsed.inMilliseconds}ms '
    'stdout=${report.llamaCpp.stdoutCapturedBytes}B${report.llamaCpp.stdoutTruncated ? '+' : ''} '
    'stderr=${report.llamaCpp.stderrCapturedBytes}B${report.llamaCpp.stderrTruncated ? '+' : ''}',
  );
  stdout.writeln(
    '- llamadart   exit=${report.llamaDart.exitCode} '
    'timeout=${report.llamaDart.timedOut} '
    'elapsed=${report.llamaDart.elapsed.inMilliseconds}ms '
    'stdout=${report.llamaDart.stdoutCapturedBytes}B${report.llamaDart.stdoutTruncated ? '+' : ''} '
    'stderr=${report.llamaDart.stderrCapturedBytes}B${report.llamaDart.stderrTruncated ? '+' : ''}',
  );
  stdout.writeln('');

  if (report.isMatch) {
    stdout.writeln('Parity status: MATCH');
    return;
  }

  stdout.writeln('Parity status: DIFFERENT');
  if (report.deltas.isEmpty) {
    stdout.writeln('No text deltas, but process status differed.');
    return;
  }

  stdout.writeln('First ${report.deltas.length} deltas:');
  for (final delta in report.deltas) {
    stdout.writeln('line ${delta.lineNumber}:');
    stdout.writeln('  expected: ${delta.expected}');
    stdout.writeln('  actual  : ${delta.actual}');
  }
}

String? _trimmedOrNull(String? value) {
  if (value == null) {
    return null;
  }

  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
