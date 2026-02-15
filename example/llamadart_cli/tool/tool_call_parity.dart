import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:llamadart_cli_example/llamadart_cli.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'model',
      help: 'Path to local GGUF model used by both servers.',
      defaultsTo: 'models/GLM-4.7-Flash-UD-Q4_K_XL.gguf',
    )
    ..addOption(
      'llama-server-path',
      help: 'Path to llama.cpp llama-server binary.',
      defaultsTo: '.parity_tools/llama.cpp/build/bin/llama-server',
    )
    ..addOption(
      'api-server-entry',
      help: 'Path to Dart llamadart_server entrypoint.',
      defaultsTo: '../llamadart_server/bin/llamadart_server.dart',
    )
    ..addOption(
      'model-id',
      help: 'OpenAI model id exposed by both servers.',
      defaultsTo: 'llamadart-local',
    )
    ..addOption(
      'working-dir',
      help: 'Working directory where commands are executed.',
      defaultsTo: Directory.current.path,
    )
    ..addOption(
      'timeout-ms',
      help: 'Per-request timeout in milliseconds.',
      defaultsTo: '300000',
    )
    ..addOption(
      'startup-timeout-ms',
      help: 'Server startup timeout in milliseconds.',
      defaultsTo: '180000',
    )
    ..addOption(
      'report-dir',
      help: 'Directory where parity artifacts are written.',
      defaultsTo: '.parity_reports_tool',
    )
    ..addFlag(
      'include-auto-scenario',
      help: 'Include additional auto tool-choice scenario.',
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
    stdout.writeln('Tool-call parity harness (llama-server vs llamadart API)');
    stdout.writeln(parser.usage);
    return;
  }

  final workingDirectory = _normalizePath(
    Directory.current.path,
    results['working-dir'] as String,
  );
  final timeoutMs = int.tryParse(results['timeout-ms'] as String);
  final startupTimeoutMs = int.tryParse(
    results['startup-timeout-ms'] as String,
  );

  if (timeoutMs == null || timeoutMs <= 0) {
    stderr.writeln('Invalid --timeout-ms value: ${results['timeout-ms']}');
    exitCode = 64;
    return;
  }

  if (startupTimeoutMs == null || startupTimeoutMs <= 0) {
    stderr.writeln(
      'Invalid --startup-timeout-ms value: ${results['startup-timeout-ms']}',
    );
    exitCode = 64;
    return;
  }

  final modelPath = _normalizePath(
    workingDirectory,
    results['model'] as String,
  );
  final llamaServerPath = _normalizePath(
    workingDirectory,
    results['llama-server-path'] as String,
  );
  final apiServerEntryPath = _normalizePath(
    workingDirectory,
    results['api-server-entry'] as String,
  );
  final modelId = results['model-id'] as String;

  final missing = <String>[];
  if (!File(modelPath).existsSync()) {
    missing.add('model not found: $modelPath');
  }
  if (!File(llamaServerPath).existsSync()) {
    missing.add('llama-server not found: $llamaServerPath');
  }
  if (!File(apiServerEntryPath).existsSync()) {
    missing.add('api server entry not found: $apiServerEntryPath');
  }
  if (missing.isNotEmpty) {
    stderr.writeln(missing.join('\n'));
    exitCode = 66;
    return;
  }

  final config = ToolCallParityConfig(
    workingDirectory: workingDirectory,
    modelPath: modelPath,
    llamaServerPath: llamaServerPath,
    apiServerEntryPath: apiServerEntryPath,
    modelId: modelId,
    startupTimeout: Duration(milliseconds: startupTimeoutMs),
    requestTimeout: Duration(milliseconds: timeoutMs),
    includeAutoScenario: results['include-auto-scenario'] as bool,
  );

  final harness = ToolCallParityHarness();
  try {
    stdout.writeln('Running tool-call parity harness...');
    stdout.writeln('model      : $modelPath');
    stdout.writeln('llama-server: $llamaServerPath');
    stdout.writeln('api-entry  : $apiServerEntryPath');

    final report = await harness.run(config);
    _printReportSummary(report);

    final reportDir = Directory(
      _normalizePath(workingDirectory, results['report-dir'] as String),
    );
    if (!reportDir.existsSync()) {
      reportDir.createSync(recursive: true);
    }

    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final basePath = p.join(reportDir.path, 'tool_parity_$stamp');

    await File('${basePath}_report.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
    await File('${basePath}_deltas.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        report.deltas.map((delta) => delta.toJson()).toList(growable: false),
      ),
    );
    await File(
      '${basePath}_llama_server.stdout.txt',
    ).writeAsString(report.llamaServerStdout);
    await File(
      '${basePath}_llama_server.stderr.txt',
    ).writeAsString(report.llamaServerStderr);
    await File(
      '${basePath}_llamadart_server.stdout.txt',
    ).writeAsString(report.llamaDartServerStdout);
    await File(
      '${basePath}_llamadart_server.stderr.txt',
    ).writeAsString(report.llamaDartServerStderr);

    stdout.writeln('Reports written to: ${reportDir.path}');
    if (!report.isMatch) {
      exitCode = 1;
    }
  } catch (error, stackTrace) {
    stderr.writeln('Tool-call parity run failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    harness.dispose();
  }
}

void _printReportSummary(ToolCallParityReport report) {
  stdout.writeln('');
  stdout.writeln('Scenarios: ${report.scenarios.length}');
  for (final scenario in report.scenarios) {
    stdout.writeln(
      '- ${scenario.scenarioId}: ${scenario.isMatch ? 'MATCH' : 'DIFFERENT'}',
    );
  }

  if (report.isMatch) {
    stdout.writeln('Overall: MATCH');
    return;
  }

  stdout.writeln('Overall: DIFFERENT');
  stdout.writeln(
    'First ${report.deltas.length < 20 ? report.deltas.length : 20} deltas:',
  );
  for (final delta in report.deltas.take(20)) {
    stdout.writeln(
      '- [${delta.scenarioId}/${delta.phase}] ${delta.field}: '
      'expected=${delta.expected} actual=${delta.actual}',
    );
  }
}

String _normalizePath(String base, String value) {
  if (p.isAbsolute(value)) {
    return p.normalize(value);
  }
  return p.normalize(p.join(base, value));
}
