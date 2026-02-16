import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_server/llamadart_server.dart';
import 'package:relic/io_adapter.dart';

const String _defaultModelUrl =
    'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/'
    'qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true';

/// Starts a local OpenAI-compatible API server backed by llamadart.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
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

  final results = parser.parse(arguments);
  if (results['help'] as bool) {
    stdout.writeln('llamadart OpenAI-compatible API Server Example\n');
    stdout.writeln(parser.usage);
    stdout.writeln('\nExample:');
    stdout.writeln(
      '  dart run llamadart_server --model ./models/model.gguf '
      '--api-key dev-key',
    );
    return;
  }

  final modelInput = results['model'] as String;
  final modelId = results['model-id'] as String;
  final host = results['host'] as String;
  final apiKey = results['api-key'] as String?;
  final enableDartLogs = results['log'] as bool;
  final enableToolExecution = results['enable-tool-execution'] as bool;

  final port = _parseIntOption(results['port'] as String, 'port');
  final contextSize = _parseIntOption(
    results['context-size'] as String,
    'context-size',
  );
  final gpuLayers = _parseIntOption(
    results['gpu-layers'] as String,
    'gpu-layers',
  );
  final maxToolRounds = _parseIntOption(
    results['max-tool-rounds'] as String,
    'max-tool-rounds',
  );

  if (maxToolRounds < 1) {
    throw ArgumentError('`max-tool-rounds` must be >= 1.');
  }

  final address = InternetAddress.tryParse(host);
  if (address == null) {
    throw ArgumentError('Invalid --host value: $host');
  }

  final modelService = ModelService();
  final engine = LlamaEngine(LlamaBackend());
  final serverEngine = LlamaApiServerEngine(engine);

  await engine.setNativeLogLevel(LlamaLogLevel.error);

  if (enableDartLogs) {
    await engine.setDartLogLevel(LlamaLogLevel.info);
  }

  Future<void> Function()? closeServer;
  try {
    stdout.writeln('Resolving model path...');
    final modelFile = await modelService.ensureModel(modelInput);

    stdout.writeln('Loading model: ${modelFile.path}');
    await engine.loadModel(
      modelFile.path,
      modelParams: ModelParams(contextSize: contextSize, gpuLayers: gpuLayers),
    );

    final OpenAiToolInvoker? toolInvoker = enableToolExecution
        ? _invokeExampleTool
        : null;

    final apiServer = OpenAiApiServer(
      engine: serverEngine,
      modelId: modelId,
      apiKey: apiKey,
      toolInvoker: toolInvoker,
      maxToolRounds: maxToolRounds,
      enableRequestLogs: enableDartLogs,
    );

    final server = await apiServer.buildApp().serve(
      address: address,
      port: port,
    );
    closeServer = server.close;

    stdout.writeln('\nServer started.');
    stdout.writeln('  Base URL: http://${address.address}:$port');
    stdout.writeln('  Health:   http://${address.address}:$port/healthz');
    stdout.writeln('  OpenAPI:  http://${address.address}:$port/openapi.json');
    stdout.writeln('  Swagger:  http://${address.address}:$port/docs');
    stdout.writeln('  Models:   http://${address.address}:$port/v1/models');
    stdout.writeln(
      '  Chat:     http://${address.address}:$port/v1/chat/completions',
    );
    if (apiKey != null && apiKey.isNotEmpty) {
      stdout.writeln('  Auth:     enabled (Bearer token required)');
    } else {
      stdout.writeln('  Auth:     disabled');
    }
    stdout.writeln(
      '  Tools:    ${enableToolExecution ? 'server execution enabled' : 'pass-through only'}',
    );
    if (enableToolExecution) {
      stdout.writeln('  Tool rounds: $maxToolRounds');
    }

    await _waitForShutdownSignal();
    stdout.writeln('\nStopping server...');
  } finally {
    if (closeServer != null) {
      await closeServer();
    }
    await engine.dispose();
  }
}

int _parseIntOption(String raw, String fieldName) {
  final value = int.tryParse(raw);
  if (value == null || value < 0) {
    throw ArgumentError('`$fieldName` must be a non-negative integer.');
  }
  return value;
}

Future<void> _waitForShutdownSignal() {
  final completer = Completer<void>();

  late final StreamSubscription<ProcessSignal> sigIntSub;
  late final StreamSubscription<ProcessSignal> sigTermSub;

  void completeIfNeeded() {
    if (completer.isCompleted) {
      return;
    }

    completer.complete();
    sigIntSub.cancel();
    sigTermSub.cancel();
  }

  sigIntSub = ProcessSignal.sigint.watch().listen((_) => completeIfNeeded());
  sigTermSub = ProcessSignal.sigterm.watch().listen((_) => completeIfNeeded());

  return completer.future;
}

Future<Object?> _invokeExampleTool(
  String toolName,
  Map<String, dynamic> arguments,
) async {
  switch (toolName) {
    case 'get_current_time':
    case 'get_time':
      final timezone =
          _extractStringValue(arguments['timezone'])?.toLowerCase() ?? 'local';
      final now = timezone == 'utc' ? DateTime.now().toUtc() : DateTime.now();
      return {
        'ok': true,
        'tool': toolName,
        'timezone': timezone,
        'iso8601': now.toIso8601String(),
      };

    case 'get_current_weather':
    case 'get_weather':
      final city =
          _extractStringValue(arguments['city']) ??
          _extractStringValue(arguments['location']) ??
          'unknown';
      final unit = (_extractStringValue(arguments['unit']) ?? 'celsius')
          .toLowerCase();
      const celsius = 23;
      final temperature = unit == 'fahrenheit'
          ? (celsius * 9 / 5 + 32).round()
          : celsius;

      return {
        'ok': true,
        'tool': toolName,
        'city': city,
        'unit': unit,
        'condition': 'sunny',
        'temperature': temperature,
      };

    default:
      throw UnsupportedError(
        'No server-side handler registered for `$toolName`.',
      );
  }
}

String? _extractStringValue(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  if (value is num || value is bool) {
    return value.toString();
  }

  if (value is List) {
    for (final item in value) {
      final extracted = _extractStringValue(item);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
    }
    return null;
  }

  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    if (map.containsKey('value')) {
      final extracted = _extractStringValue(map['value']);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
    }

    for (final entry in map.entries) {
      final extracted = _extractStringValue(entry.value);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
    }
  }

  return null;
}
