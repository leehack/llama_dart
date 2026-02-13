import '../core/models/inference/model_params.dart';
import '../core/models/inference/generation_params.dart';
import '../core/models/chat/content_part.dart';
import '../core/models/config/log_level.dart';

import 'llama_cpp/llama_cpp_backend.dart'
    if (dart.library.js_interop) 'web/web_backend.dart';

/// Platform-agnostic interface for Llama model inference.
abstract class LlamaBackend {
  /// Factory to create the appropriate backend for the current platform.
  factory LlamaBackend() => createBackend();

  /// Whether the backend is currently initialized and ready for inference.
  bool get isReady;

  /// Initializes the model from a local file [path].
  Future<int> modelLoad(String path, ModelParams params);

  /// Initializes the model from a remote [url].
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  });

  /// Releases the allocated [modelHandle].
  Future<void> modelFree(int modelHandle);

  /// Creates a new inference context for the given [modelHandle].
  Future<int> contextCreate(int modelHandle, ModelParams params);

  /// Releases the allocated [contextHandle].
  Future<void> contextFree(int contextHandle);

  /// Returns the actual context size used by the given [contextHandle].
  Future<int> getContextSize(int contextHandle);

  /// Generates a stream of token bytes for a given prompt and context.
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  });

  /// Immediately cancels the current generation.
  void cancelGeneration();

  /// Encodes the given [text] into a list of token IDs.
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  });

  /// Decodes a list of [tokens] back into a human-readable string.
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  });

  /// Retrieves all available metadata from the loaded model.
  Future<Map<String, String>> modelMetadata(int modelHandle);

  /// Dynamically loads or updates a LoRA adapter's scale.
  Future<void> setLoraAdapter(int contextHandle, String path, double scale);

  /// Removes a specific LoRA adapter from the active session.
  Future<void> removeLoraAdapter(int contextHandle, String path);

  /// Removes all active LoRA adapters from the current context.
  Future<void> clearLoraAdapters(int contextHandle);

  /// Returns the name of the active GPU backend.
  Future<String> getBackendName();

  /// Whether this backend supports loading from URLs directly (e.g. WASM).
  ///
  /// Backends that support this (like Web) will handle URL-based model loading
  /// natively, while others may require the engine to download the file first.
  bool get supportsUrlLoading;

  /// Returns true if the hardware and backend support GPU acceleration.
  Future<bool> isGpuSupported();

  /// Updates the minimum log level for the backend.
  Future<void> setLogLevel(LlamaLogLevel level);

  /// Releases all allocated backend resources.
  Future<void> dispose();

  // NEW: Multimodal context methods
  /// Loads a multimodal projector for vision/audio support.
  Future<int?> multimodalContextCreate(int modelHandle, String mmProjPath);

  /// Frees the multimodal context.
  Future<void> multimodalContextFree(int mmContextHandle);

  /// Checks if the model supports vision input.
  Future<bool> supportsVision(int mmContextHandle);

  /// Checks if the model supports audio input.
  Future<bool> supportsAudio(int mmContextHandle);

  /// Returns the total and free VRAM in bytes.
  Future<({int total, int free})> getVramInfo();

  /// Applies the model's chat template to the given [messages].
  ///
  /// If [customTemplate] is provided, it will be used instead of the model's
  /// default template.
  ///
  /// Returns the formatted prompt string.
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  });
}
