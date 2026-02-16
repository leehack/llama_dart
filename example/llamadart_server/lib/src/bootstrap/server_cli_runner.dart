import 'dart:io';

import 'package:args/args.dart';

import 'cli/cli.dart';
import 'server_runtime.dart';

const int _exitSuccess = 0;
const int _exitUsage = 64;
const int _exitSoftware = 70;

/// Runs the server CLI workflow and returns a process exit code.
Future<int> runServerCli(List<String> arguments) async {
  final parser = buildServerCliArgParser();

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on ArgParserException catch (error) {
    _writeUsageError(error.message);
    return _exitUsage;
  }

  if (isHelpRequested(results)) {
    stdout.writeln(buildServerCliHelp(parser));
    return _exitSuccess;
  }

  final ServerCliConfig config;
  try {
    config = parseServerCliConfig(results);
  } on ArgumentError catch (error) {
    _writeUsageError(error.message ?? '$error');
    return _exitUsage;
  }

  try {
    await runServerFromConfig(config);
    return _exitSuccess;
  } on Exception catch (error) {
    stderr.writeln('Error: $error');
    return _exitSoftware;
  } on Error catch (error) {
    stderr.writeln('Error: $error');
    return _exitSoftware;
  }
}

void _writeUsageError(String message) {
  stderr.writeln('Error: $message');
  stderr.writeln('Run with --help to see usage.');
}
