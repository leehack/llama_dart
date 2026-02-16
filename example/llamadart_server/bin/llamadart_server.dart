import 'dart:io';

import 'package:llamadart_server/src/bootstrap/bootstrap.dart';

/// Starts a local OpenAI-compatible API server backed by llamadart.
Future<void> main(List<String> arguments) async {
  final statusCode = await runServerCli(arguments);
  if (statusCode != 0) {
    exitCode = statusCode;
  }
}
