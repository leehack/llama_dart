import 'dart:io';

import '../cli/server_cli_config.dart';

/// Prints server startup endpoint summary.
void printServerStartup(ServerCliConfig config) {
  final host = config.address.address;
  final port = config.port;

  stdout.writeln('\nServer started.');
  stdout.writeln('  Base URL: http://$host:$port');
  stdout.writeln('  Health:   http://$host:$port/healthz');
  stdout.writeln('  OpenAPI:  http://$host:$port/openapi.json');
  stdout.writeln('  Swagger:  http://$host:$port/docs');
  stdout.writeln('  Models:   http://$host:$port/v1/models');
  stdout.writeln('  Chat:     http://$host:$port/v1/chat/completions');
  stdout.writeln(
    config.authEnabled
        ? '  Auth:     enabled (Bearer token required)'
        : '  Auth:     disabled',
  );
  stdout.writeln(
    '  Tools:    ${config.enableToolExecution ? 'server execution enabled' : 'pass-through only'}',
  );
  if (config.enableToolExecution) {
    stdout.writeln('  Tool rounds: ${config.maxToolRounds}');
  }
}

/// Prints server shutdown message.
void printServerStopping() {
  stdout.writeln('\nStopping server...');
}
