import 'package:args/args.dart';

/// Whether the parsed args requested help output.
bool isHelpRequested(ArgResults results) {
  return results['help'] as bool;
}

/// Builds CLI help output.
String buildServerCliHelp(ArgParser parser) {
  return '''llamadart OpenAI-compatible API Server Example

${parser.usage}

Example:
  dart run llamadart_server --model ./models/model.gguf --api-key dev-key''';
}
