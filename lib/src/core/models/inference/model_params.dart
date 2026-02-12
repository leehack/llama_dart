import '../config/gpu_backend.dart';

import '../config/lora_config.dart';

/// Configuration parameters for loading a Llama model.
///
/// These parameters affect the initial model loading and context allocation.
/// Most of these cannot be changed once the model is loaded.
///
/// Example:
/// ```dart
/// final params = ModelParams(
///   contextSize: 4096,
///   gpuLayers: 33, // Offload 33 layers to GPU
///   logLevel: LlamaLogLevel.info,
/// );
/// await engine.loadModel('path/to/model.gguf', modelParams: params);
/// ```
class ModelParams {
  /// Context size (n_ctx) in tokens.
  final int contextSize;

  /// Number of model layers to offload to the GPU (n_gpu_layers).
  final int gpuLayers;

  /// Preferred GPU backend for inference.
  final GpuBackend preferredBackend;

  /// Initial LoRA adapters to load along with the model.
  final List<LoraAdapterConfig> loras;

  /// Optional chat template to override the model's default template.
  final String? chatTemplate;

  /// Number of threads to use for generation (n_threads).
  ///
  /// Set to 0 for automatic detection.
  final int numberOfThreads;

  /// Number of threads to use for batch processing (n_threads_batch).
  ///
  /// Set to 0 for automatic detection.
  final int numberOfThreadsBatch;

  /// Maximum number of GPU layers to safely offload all layers.
  static const int maxGpuLayers = 999;

  /// Creates configuration for the model.
  const ModelParams({
    this.contextSize = 4096,
    this.gpuLayers = maxGpuLayers,
    this.preferredBackend = GpuBackend.auto,
    this.loras = const [],
    this.chatTemplate,
    this.numberOfThreads = 0,
    this.numberOfThreadsBatch = 0,
  });

  /// Creates a copy of this [ModelParams] with updated fields.
  ModelParams copyWith({
    int? contextSize,
    int? gpuLayers,
    GpuBackend? preferredBackend,
    List<LoraAdapterConfig>? loras,
    String? chatTemplate,
    int? numberOfThreads,
    int? numberOfThreadsBatch,
  }) {
    return ModelParams(
      contextSize: contextSize ?? this.contextSize,
      gpuLayers: gpuLayers ?? this.gpuLayers,
      preferredBackend: preferredBackend ?? this.preferredBackend,
      loras: loras ?? this.loras,
      chatTemplate: chatTemplate ?? this.chatTemplate,
      numberOfThreads: numberOfThreads ?? this.numberOfThreads,
      numberOfThreadsBatch: numberOfThreadsBatch ?? this.numberOfThreadsBatch,
    );
  }
}
