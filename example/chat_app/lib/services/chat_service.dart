import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import '../models/chat_settings.dart';

/// Service for managing the LLM engine lifecycle.
///
/// This service handles model loading and provides access to the engine.
/// For chat functionality, use [ChatSession] which is created by the provider.
class ChatService {
  final LlamaEngine _engine;
  bool _disposed = false;

  ChatService({LlamaEngine? engine})
    : _engine = engine ?? LlamaEngine(LlamaBackend());

  /// The underlying LlamaEngine instance.
  LlamaEngine get engine => _engine;

  /// Initializes the engine with the given settings.
  Future<void> init(
    ChatSettings settings, {
    Function(double progress)? onProgress,
  }) async {
    if (settings.modelPath == null) throw Exception("Model path is null");

    // Unload existing model if any
    if (_engine.isReady) {
      await _engine.unloadModel();
    }

    Timer? syntheticProgressTimer;
    var syntheticProgress = 0.0;
    var emittedProgress = 0.0;

    void emitProgress(double value) {
      if (onProgress == null) {
        return;
      }
      final clamped = value.clamp(0.0, 1.0);
      if (clamped <= emittedProgress) {
        return;
      }
      emittedProgress = clamped;
      onProgress(clamped);
    }

    if (onProgress != null) {
      syntheticProgressTimer = Timer.periodic(
        const Duration(milliseconds: 160),
        (_) {
          syntheticProgress =
              (syntheticProgress + (1 - syntheticProgress) * 0.1).clamp(
                0.0,
                0.9,
              );
          emitProgress(syntheticProgress);
        },
      );
    }

    try {
      if (settings.modelPath!.startsWith('http')) {
        await _engine.loadModelFromUrl(
          settings.modelPath!,
          modelParams: ModelParams(
            gpuLayers: settings.gpuLayers,
            preferredBackend: settings.preferredBackend,
            contextSize: settings.contextSize,
            numberOfThreads: settings.numberOfThreads,
            numberOfThreadsBatch: settings.numberOfThreadsBatch,
          ),
          onProgress: onProgress == null
              ? null
              : (progress) {
                  emitProgress(progress);
                },
        );
      } else {
        await _engine.loadModel(
          settings.modelPath!,
          modelParams: ModelParams(
            gpuLayers: settings.gpuLayers,
            preferredBackend: settings.preferredBackend,
            contextSize: settings.contextSize,
            numberOfThreads: settings.numberOfThreads,
            numberOfThreadsBatch: settings.numberOfThreadsBatch,
          ),
        );
      }

      emitProgress(1.0);
    } finally {
      syntheticProgressTimer?.cancel();
    }

    if (settings.mmprojPath != null && settings.mmprojPath!.isNotEmpty) {
      try {
        await _engine.loadMultimodalProjector(settings.mmprojPath!);
        debugPrint("Loaded multimodal projector from ${settings.mmprojPath}");
      } catch (e) {
        debugPrint("Failed to load multimodal projector: $e");
        throw Exception(
          'Failed to load multimodal projector (${settings.mmprojPath}). '
          'Please verify this mmproj matches the selected model.',
        );
      }
    }
  }

  /// Cleans whitespace from response text.
  String cleanResponse(String response) {
    return response.trim();
  }

  /// Unloads the currently loaded model but keeps engine alive.
  Future<void> unloadModel() async {
    _engine.cancelGeneration();
    if (_engine.isReady) {
      await _engine.unloadModel();
    }
  }

  /// Disposes of the engine resources. Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _engine.cancelGeneration();
    await _engine.dispose();
  }

  /// Cancels any ongoing generation.
  void cancelGeneration() {
    _engine.cancelGeneration();
  }
}
