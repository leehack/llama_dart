@Tags(<String>['local-only'])
library;

import 'dart:io';

import 'package:llamadart_cli_example/llamadart_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Tool-call parity gate', () {
    final config = _ToolParityGateConfig.fromEnvironment();

    test('matches llama.cpp tool-call round-trip behavior', () async {
      final skipReason = config.skipReason;
      if (skipReason != null) {
        // ignore: avoid_print
        print(skipReason);
        return;
      }

      final harness = ToolCallParityHarness();
      try {
        final report = await harness.run(config.runConfig);

        expect(report.scenarios, isNotEmpty);
        expect(report.isMatch, isTrue, reason: _mismatchReason(report));
      } finally {
        harness.dispose();
      }
    });
  });
}

String _mismatchReason(ToolCallParityReport report) {
  final lines = <String>[
    'Scenarios: ${report.scenarios.length}',
    'Total deltas: ${report.deltas.length}',
    for (final delta in report.deltas.take(6))
      '[${delta.scenarioId}/${delta.phase}] ${delta.field}\n'
          'expected=${delta.expected}\n'
          'actual=${delta.actual}',
  ];
  return lines.join('\n');
}

class _ToolParityGateConfig {
  final ToolCallParityConfig runConfig;
  final String? skipReason;

  const _ToolParityGateConfig({
    required this.runConfig,
    required this.skipReason,
  });

  factory _ToolParityGateConfig.fromEnvironment() {
    final env = Platform.environment;

    final workingDirectory = Directory.current.path;
    final modelPath = _normalizePath(
      workingDirectory,
      env['LLAMADART_TOOL_PARITY_MODEL'] ??
          p.join('models', 'GLM-4.7-Flash-UD-Q4_K_XL.gguf'),
    );
    final llamaServerPath = _normalizePath(
      workingDirectory,
      env['LLAMADART_TOOL_PARITY_LLAMA_SERVER'] ??
          p.join('.parity_tools', 'llama.cpp', 'build', 'bin', 'llama-server'),
    );
    final apiServerEntryPath = _normalizePath(
      workingDirectory,
      env['LLAMADART_TOOL_PARITY_API_SERVER_ENTRY'] ??
          p.join('..', 'llamadart_server', 'bin', 'llamadart_server.dart'),
    );

    final timeoutMs =
        int.tryParse(env['LLAMADART_TOOL_PARITY_TIMEOUT_MS'] ?? '') ?? 300000;
    final startupTimeoutMs =
        int.tryParse(env['LLAMADART_TOOL_PARITY_STARTUP_TIMEOUT_MS'] ?? '') ??
        180000;
    final includeAutoScenario =
        (env['LLAMADART_TOOL_PARITY_INCLUDE_AUTO'] ?? '').toLowerCase() ==
        'true';

    final missing = <String>[];
    if (!File(modelPath).existsSync()) {
      missing.add('model: $modelPath');
    }
    if (!File(llamaServerPath).existsSync()) {
      missing.add('llama-server: $llamaServerPath');
    }
    if (!File(apiServerEntryPath).existsSync()) {
      missing.add('api entry: $apiServerEntryPath');
    }

    final skipReason = missing.isEmpty
        ? null
        : 'Missing local tool-parity dependencies: ${missing.join(' | ')}';

    return _ToolParityGateConfig(
      runConfig: ToolCallParityConfig(
        workingDirectory: workingDirectory,
        modelPath: modelPath,
        llamaServerPath: llamaServerPath,
        apiServerEntryPath: apiServerEntryPath,
        modelId: env['LLAMADART_TOOL_PARITY_MODEL_ID'] ?? 'llamadart-local',
        startupTimeout: Duration(milliseconds: startupTimeoutMs),
        requestTimeout: Duration(milliseconds: timeoutMs),
        includeAutoScenario: includeAutoScenario,
      ),
      skipReason: skipReason,
    );
  }
}

String _normalizePath(String base, String value) {
  if (p.isAbsolute(value)) {
    return p.normalize(value);
  }
  return p.normalize(p.join(base, value));
}
