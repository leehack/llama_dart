import 'package:args/args.dart';
import 'package:llamadart/llamadart.dart';

const String _defaultModelUrl =
    'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/'
    'qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true';

/// Builds the CLI argument parser.
ArgParser buildServerCliArgParser() {
  return ArgParser()
    ..addOption(
      'model',
      abbr: 'm',
      defaultsTo: _defaultModelUrl,
      help: 'Path or URL to a GGUF model.',
    )
    ..addOption(
      'model-id',
      defaultsTo: 'llamadart-local',
      help: 'Model ID returned from `/v1/models` and completion responses.',
    )
    ..addOption(
      'host',
      defaultsTo: '127.0.0.1',
      help: 'Host/IP to bind the HTTP server to.',
    )
    ..addOption(
      'port',
      defaultsTo: '8080',
      help: 'TCP port for the HTTP server.',
    )
    ..addOption(
      'api-key',
      help: 'Optional API key required as `Authorization: Bearer <key>`.',
    )
    ..addOption(
      'context-size',
      defaultsTo: '4096',
      help: 'Model context size in tokens.',
    )
    ..addOption(
      'gpu-layers',
      defaultsTo: '${ModelParams.maxGpuLayers}',
      help: 'Number of layers to offload to GPU.',
    )
    ..addFlag(
      'enable-tool-execution',
      defaultsTo: false,
      help:
          'Enable server-side execution loop for model-emitted tool calls. '
          'This example includes built-in mock handlers for common demo tools.',
    )
    ..addOption(
      'max-tool-rounds',
      defaultsTo: '5',
      help: 'Maximum tool-call rounds per request when execution is enabled.',
    )
    ..addFlag(
      'log',
      abbr: 'g',
      defaultsTo: false,
      help:
          'Enable verbose Dart + request logging '
          '(native logs stay error-only).',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message.',
    );
}
