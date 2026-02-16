import 'dart:io';

import 'package:llamadart/llamadart.dart';

import '../../features/model_management/model_management.dart';
import '../../features/server_engine/server_engine.dart';
import '../cli/server_cli_config.dart';

/// Creates and initializes a server engine for the provided CLI config.
Future<LlamaApiServerEngine> createInitializedServerEngine(
  ServerCliConfig config, {
  required ModelService modelService,
}) async {
  final engine = LlamaEngine(LlamaBackend());
  final serverEngine = LlamaApiServerEngine(engine);

  try {
    await _configureEngineLogs(engine, enableDartLogs: config.enableDartLogs);

    stdout.writeln('Resolving model path...');
    final modelFile = await modelService.ensureModel(config.modelInput);

    stdout.writeln('Loading model: ${modelFile.path}');
    await engine.loadModel(
      modelFile.path,
      modelParams: ModelParams(
        contextSize: config.contextSize,
        gpuLayers: config.gpuLayers,
      ),
    );

    return serverEngine;
  } catch (_) {
    await engine.dispose();
    rethrow;
  }
}

Future<void> _configureEngineLogs(
  LlamaEngine engine, {
  required bool enableDartLogs,
}) async {
  await engine.setNativeLogLevel(LlamaLogLevel.error);

  if (enableDartLogs) {
    await engine.setDartLogLevel(LlamaLogLevel.info);
  }
}
