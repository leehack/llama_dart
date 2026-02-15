import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Command execution input for parity runs.
class ParityCommand {
  /// Shell command string to execute.
  final String command;

  /// Optional process working directory.
  final String? workingDirectory;

  /// Creates an executable command descriptor.
  const ParityCommand({required this.command, this.workingDirectory});
}

/// One command execution result.
class ParityCommandResult {
  /// Original command descriptor.
  final ParityCommand command;

  /// Process exit code (`-1` when timing out).
  final int exitCode;

  /// Captured stdout text.
  final String stdoutText;

  /// True when stdout capture was truncated due to byte cap.
  final bool stdoutTruncated;

  /// Number of stdout bytes captured (post-truncation cap).
  final int stdoutCapturedBytes;

  /// Captured stderr text.
  final String stderrText;

  /// True when stderr capture was truncated due to byte cap.
  final bool stderrTruncated;

  /// Number of stderr bytes captured (post-truncation cap).
  final int stderrCapturedBytes;

  /// Whether the process timed out.
  final bool timedOut;

  /// Total elapsed duration.
  final Duration elapsed;

  /// Creates an immutable run result.
  const ParityCommandResult({
    required this.command,
    required this.exitCode,
    required this.stdoutText,
    required this.stdoutTruncated,
    required this.stdoutCapturedBytes,
    required this.stderrText,
    required this.stderrTruncated,
    required this.stderrCapturedBytes,
    required this.timedOut,
    required this.elapsed,
  });
}

/// One normalized mismatch between llama.cpp and llamadart outputs.
class TranscriptDelta {
  /// One-based normalized line number.
  final int lineNumber;

  /// Expected line from llama.cpp output.
  final String expected;

  /// Actual line from llamadart output.
  final String actual;

  /// Creates an output delta entry.
  const TranscriptDelta({
    required this.lineNumber,
    required this.expected,
    required this.actual,
  });
}

/// Complete parity report between two command runs.
class ParityReport {
  /// llama.cpp command execution result.
  final ParityCommandResult llamaCpp;

  /// llamadart CLI command execution result.
  final ParityCommandResult llamaDart;

  /// Normalized llama.cpp transcript.
  final String normalizedLlamaCpp;

  /// Normalized llamadart transcript.
  final String normalizedLlamaDart;

  /// First N deltas discovered in normalized output.
  final List<TranscriptDelta> deltas;

  /// Creates an immutable parity report.
  const ParityReport({
    required this.llamaCpp,
    required this.llamaDart,
    required this.normalizedLlamaCpp,
    required this.normalizedLlamaDart,
    required this.deltas,
  });

  /// True if both exit codes match and normalized output matches exactly.
  bool get isMatch {
    return llamaCpp.exitCode == llamaDart.exitCode &&
        !llamaCpp.timedOut &&
        !llamaDart.timedOut &&
        deltas.isEmpty;
  }
}

/// Transcript normalizer used before comparing outputs.
class TranscriptNormalizer {
  static final RegExp _ansiEscape = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
  static final RegExp _lineEnding = RegExp(r'\r\n?|\n');

  /// Creates a transcript normalizer.
  const TranscriptNormalizer();

  /// Normalizes raw terminal output into comparable text.
  String normalize(String rawText) {
    final withoutAnsi = rawText.replaceAll(_ansiEscape, '');
    final lines = withoutAnsi
        .split(_lineEnding)
        .map((line) => line.replaceAll(RegExp(r'\s+$'), ''))
        .where((line) => line.trim().isNotEmpty)
        .where((line) => !_isNoiseLine(line))
        .map(_normalizePromptPrefixes)
        .toList(growable: false);

    return lines.join('\n');
  }

  bool _isNoiseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    return trimmed.startsWith('== llamadart-cli ==') ||
        trimmed.startsWith('Running build hooks...') ||
        trimmed.startsWith('mode    :') ||
        trimmed.startsWith('model   :') ||
        trimmed.startsWith('context :') ||
        trimmed.startsWith('sample  :') ||
        trimmed.startsWith('fit     :') ||
        trimmed.startsWith('type `/help` for commands') ||
        trimmed.startsWith('Resolved ') ||
        trimmed.startsWith('Downloading...') ||
        trimmed.startsWith('Loaded model:') ||
        trimmed.startsWith('Loading model...') ||
        trimmed.startsWith('build      :') ||
        trimmed.startsWith('model      :') ||
        trimmed.startsWith('modalities :') ||
        trimmed.startsWith('L L A M A D A R T') ||
        trimmed.startsWith('available commands:') ||
        trimmed.startsWith('/exit or Ctrl+C') ||
        trimmed.startsWith('/regen') ||
        trimmed.startsWith('/clear') ||
        trimmed.startsWith('/read') ||
        trimmed.startsWith('Exiting...') ||
        trimmed.startsWith('[Start thinking]') ||
        trimmed == '>' ||
        trimmed.startsWith('▄▄') ||
        trimmed.startsWith('██') ||
        trimmed.startsWith('▀▀');
  }

  String _normalizePromptPrefixes(String line) {
    var output = line;
    if (output.startsWith('assistant> ')) {
      output = output.substring('assistant> '.length);
    }
    if (output.startsWith('user> ')) {
      output = output.substring('user> '.length);
    }
    return output;
  }
}

/// Runs llama.cpp and llamadart CLI commands, then compares normalized outputs.
class ParityHarness {
  /// Process timeout for each command.
  final Duration timeout;

  /// Output normalizer used before diffing.
  final TranscriptNormalizer normalizer;

  /// Maximum number of deltas returned in report.
  final int maxDeltas;

  /// Maximum captured bytes per output stream (stdout/stderr) per command.
  final int maxCapturedBytes;

  /// Creates a harness with optional timeout and comparer behavior.
  const ParityHarness({
    this.timeout = const Duration(minutes: 10),
    this.normalizer = const TranscriptNormalizer(),
    this.maxDeltas = 50,
    this.maxCapturedBytes = 8 * 1024 * 1024,
  });

  /// Executes both commands with the same prompt script and compares outputs.
  Future<ParityReport> run({
    required ParityCommand llamaCpp,
    required ParityCommand llamaDart,
    required List<String> prompts,
    bool appendExitCommand = true,
    bool strictRaw = false,
    bool rawIncludeStderr = false,
  }) async {
    final stdinScript = _buildStdinScript(prompts, appendExitCommand);

    final llamaCppResult = await _runCommand(llamaCpp, stdinScript);
    final llamaDartResult = await _runCommand(llamaDart, stdinScript);

    final normalizedCpp = strictRaw
        ? _buildRawComparableText(
            llamaCppResult,
            includeStderr: rawIncludeStderr,
          )
        : normalizer.normalize(llamaCppResult.stdoutText);
    final normalizedDart = strictRaw
        ? _buildRawComparableText(
            llamaDartResult,
            includeStderr: rawIncludeStderr,
          )
        : normalizer.normalize(llamaDartResult.stdoutText);

    final deltas = computeDeltas(
      expected: normalizedCpp,
      actual: normalizedDart,
      maxDeltas: maxDeltas,
    );

    return ParityReport(
      llamaCpp: llamaCppResult,
      llamaDart: llamaDartResult,
      normalizedLlamaCpp: normalizedCpp,
      normalizedLlamaDart: normalizedDart,
      deltas: deltas,
    );
  }

  String _buildRawComparableText(
    ParityCommandResult result, {
    required bool includeStderr,
  }) {
    if (!includeStderr) {
      return result.stdoutText;
    }

    return '${result.stdoutText}\n\n--- stderr ---\n${result.stderrText}';
  }

  String _buildStdinScript(List<String> prompts, bool appendExitCommand) {
    final lines = prompts.where((line) => line.trim().isNotEmpty).toList();
    if (appendExitCommand) {
      lines.add('/exit');
    }
    return '${lines.join('\n')}\n';
  }

  Future<ParityCommandResult> _runCommand(
    ParityCommand command,
    String stdinScript,
  ) async {
    final startedAt = DateTime.now();
    final process = await Process.start(
      '/bin/bash',
      <String>['-lc', command.command],
      workingDirectory: command.workingDirectory,
      runInShell: false,
    );

    final stdoutCapture = _LimitedTextCapture(maxCapturedBytes);
    final stderrCapture = _LimitedTextCapture(maxCapturedBytes);

    final stdoutDone = process.stdout
        .listen(stdoutCapture.add)
        .asFuture<void>();
    final stderrDone = process.stderr
        .listen(stderrCapture.add)
        .asFuture<void>();

    process.stdin.write(stdinScript);
    await process.stdin.close();

    var timedOut = false;
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      exitCode = -1;
    }

    await stdoutDone;
    await stderrDone;

    final stdoutText = stdoutCapture.text;
    final stderrText = stderrCapture.text;

    return ParityCommandResult(
      command: command,
      exitCode: exitCode,
      stdoutText: stdoutText,
      stdoutTruncated: stdoutCapture.truncated,
      stdoutCapturedBytes: stdoutCapture.capturedBytes,
      stderrText: stderrText,
      stderrTruncated: stderrCapture.truncated,
      stderrCapturedBytes: stderrCapture.capturedBytes,
      timedOut: timedOut,
      elapsed: DateTime.now().difference(startedAt),
    );
  }
}

class _LimitedTextCapture {
  final int _limitBytes;
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  bool truncated = false;

  _LimitedTextCapture(this._limitBytes);

  int get capturedBytes => _bytes.length;

  String get text => utf8.decode(_bytes.toBytes(), allowMalformed: true);

  void add(List<int> chunk) {
    if (chunk.isEmpty) {
      return;
    }

    final remaining = _limitBytes - _bytes.length;
    if (remaining <= 0) {
      truncated = true;
      return;
    }

    if (chunk.length <= remaining) {
      _bytes.add(chunk);
      return;
    }

    _bytes.add(chunk.sublist(0, remaining));
    truncated = true;
  }
}

/// Computes line-by-line deltas between normalized expected and actual text.
List<TranscriptDelta> computeDeltas({
  required String expected,
  required String actual,
  int maxDeltas = 50,
}) {
  final expectedLines = expected.isEmpty
      ? const <String>[]
      : expected.split('\n');
  final actualLines = actual.isEmpty ? const <String>[] : actual.split('\n');

  final longest = expectedLines.length > actualLines.length
      ? expectedLines.length
      : actualLines.length;

  final deltas = <TranscriptDelta>[];
  for (var index = 0; index < longest; index++) {
    final left = index < expectedLines.length ? expectedLines[index] : '<EOF>';
    final right = index < actualLines.length ? actualLines[index] : '<EOF>';
    if (left == right) {
      continue;
    }

    deltas.add(
      TranscriptDelta(lineNumber: index + 1, expected: left, actual: right),
    );

    if (deltas.length >= maxDeltas) {
      break;
    }
  }

  return deltas;
}
