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

    if (settings.modelPath!.startsWith('http')) {
      await _engine.loadModelFromUrl(
        settings.modelPath!,
        modelParams: ModelParams(
          gpuLayers: settings.gpuLayers,
          preferredBackend: settings.preferredBackend,
          contextSize: settings.contextSize,
        ),
        onProgress: onProgress,
      );
    } else {
      await _engine.loadModel(
        settings.modelPath!,
        modelParams: ModelParams(
          gpuLayers: settings.gpuLayers,
          preferredBackend: settings.preferredBackend,
          contextSize: settings.contextSize,
        ),
      );
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

  /// Disposes of the engine resources. Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _engine.dispose();
  }

  /// Cancels any ongoing generation.
  void cancelGeneration() {
    _engine.cancelGeneration();
  }
}
