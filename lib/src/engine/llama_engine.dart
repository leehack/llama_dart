import 'dart:async';
import 'dart:convert';
import '../backend/llama_backend_interface.dart';
import 'llama_tokenizer.dart';
import 'chat_template_processor.dart';
import '../common/exceptions.dart';
import '../models/llama_log_level.dart';
import '../models/model_params.dart';
import '../models/generation_params.dart';
import '../models/llama_chat_message.dart';
import '../models/llama_chat_template_result.dart';

/// High-level engine that orchestrates models and contexts.
class LlamaEngine {
  final LlamaBackend _backend;
  int? _modelHandle;
  int? _contextHandle;
  bool _isReady = false;

  LlamaTokenizer? _tokenizer;
  ChatTemplateProcessor? _templateProcessor;

  /// Creates a new [LlamaEngine] with the given [backend].
  LlamaEngine(this._backend);

  /// Whether the engine is initialized and ready for inference.
  bool get isReady => _isReady;

  /// The tokenizer associated with the loaded model.
  LlamaTokenizer? get tokenizer => _tokenizer;

  /// The chat template processor associated with the loaded model.
  ChatTemplateProcessor? get templateProcessor => _templateProcessor;

  /// Loads a model from a local [path].
  Future<void> loadModel(
    String path, {
    ModelParams modelParams = const ModelParams(),
  }) async {
    // If backend supports URL loading (e.g. WASM), use it.
    // We check this via a string for now to avoid potential initialization issues
    // with some backends that might not be ready.
    try {
      final name = await _backend.getBackendName();
      if (name.startsWith("WASM")) {
        return loadModelFromUrl(path, modelParams: modelParams);
      }
    } catch (_) {}

    try {
      _modelHandle = await _backend.modelLoad(path, modelParams);
      _contextHandle = await _backend.contextCreate(_modelHandle!, modelParams);

      _tokenizer = LlamaTokenizer(_backend, _modelHandle!);
      _templateProcessor = ChatTemplateProcessor(_backend, _modelHandle!);

      _isReady = true;
    } catch (e) {
      throw LlamaModelException("Failed to load model from $path", e);
    }
  }

  /// Loads a model from a [url].
  Future<void> loadModelFromUrl(
    String url, {
    ModelParams modelParams = const ModelParams(),
    Function(double progress)? onProgress,
  }) async {
    // If it's Web, wllama supports loading directly from URL.
    final backendName = await _backend.getBackendName();
    if (backendName.startsWith("WASM")) {
      _modelHandle = await _backend.modelLoadFromUrl(
        url,
        modelParams,
        onProgress: onProgress,
      );
      _contextHandle = await _backend.contextCreate(_modelHandle!, modelParams);
      _tokenizer = LlamaTokenizer(_backend, _modelHandle!);
      _templateProcessor = ChatTemplateProcessor(_backend, _modelHandle!);
      _isReady = true;
      return;
    }

    // For native, we still need to download to a file first.
    // We'll use a platform-agnostic way to get a temp path if possible,
    // or just use the backend's helper if we add one.
    // For now, since LlamaEngine is meant to be shared, we keep the download logic
    // but try to avoid dart:io if we can.
    // Actually, LlamaEngine can still use dart:io if we use conditional imports.
    // But to keep it simple and 100% web-safe, we'll let the user provide the path
    // or move this to a helper.

    // Let's implement a minimal download for Native without importing dart:io in the main path.
    throw UnimplementedError(
      "loadModelFromUrl for Native should be handled by the caller or a helper.",
    );
  }

  /// Generates a stream of text tokens based on the provided [prompt].
  Stream<String> generate(
    String prompt, {
    GenerationParams params = const GenerationParams(),
  }) async* {
    if (!_isReady || _contextHandle == null) {
      throw LlamaContextException("Engine not ready. Call loadModel first.");
    }

    final stream = _backend.generate(_contextHandle!, prompt, params);

    // Pipe through UTF-8 decoder to handle multi-byte characters correctly
    final controller = StreamController<List<int>>();
    final sub = stream.listen(
      (bytes) => controller.add(bytes),
      onDone: () => controller.close(),
      onError: (e) => controller.addError(e),
    );

    try {
      yield* controller.stream.transform(
        const Utf8Decoder(allowMalformed: true),
      );
    } finally {
      await sub.cancel();
    }
  }

  /// High-level chat interface.
  Stream<String> chat(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
  }) async* {
    if (!_isReady || _modelHandle == null) {
      throw LlamaContextException("Engine not ready.");
    }

    final result = await chatTemplate(messages);
    final stops = {...result.stopSequences, ...?params?.stopSequences}.toList();

    yield* generate(
      result.prompt,
      params: (params ?? const GenerationParams()).copyWith(
        stopSequences: stops,
      ),
    );
  }

  /// Formats a list of [messages] into a single prompt string.
  Future<LlamaChatTemplateResult> chatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
  }) {
    if (!_isReady || _templateProcessor == null) {
      throw LlamaContextException("Engine not ready.");
    }
    return _templateProcessor!.apply(messages, addAssistant: addAssistant);
  }

  /// Encodes the given [text] into a list of token IDs.
  Future<List<int>> tokenize(String text, {bool addSpecial = true}) {
    if (!_isReady || _tokenizer == null) {
      throw LlamaContextException("Engine not ready.");
    }
    return _tokenizer!.encode(text, addSpecial: addSpecial);
  }

  /// Decodes a list of [tokens] back into a human-readable string.
  Future<String> detokenize(List<int> tokens, {bool special = false}) {
    if (!_isReady || _tokenizer == null) {
      throw LlamaContextException("Engine not ready.");
    }
    return _tokenizer!.decode(tokens, special: special);
  }

  /// Retrieves all available metadata from the loaded model.
  Future<Map<String, String>> getMetadata() {
    if (!_isReady || _modelHandle == null) {
      return Future.value({});
    }
    return _backend.modelMetadata(_modelHandle!);
  }

  /// Dynamically loads or updates a LoRA adapter's scale.
  Future<void> setLora(String path, {double scale = 1.0}) {
    if (!_isReady || _contextHandle == null) {
      throw LlamaContextException("Engine not ready.");
    }
    return _backend.setLoraAdapter(_contextHandle!, path, scale);
  }

  /// Removes a specific LoRA adapter from the active session.
  Future<void> removeLora(String path) {
    if (!_isReady || _contextHandle == null) {
      throw LlamaContextException("Engine not ready.");
    }
    return _backend.removeLoraAdapter(_contextHandle!, path);
  }

  /// Removes all active LoRA adapters from the current context.
  Future<void> clearLoras() {
    if (!_isReady || _contextHandle == null) {
      throw LlamaContextException("Engine not ready.");
    }
    return _backend.clearLoraAdapters(_contextHandle!);
  }

  /// Immediately cancels any ongoing generation process.
  void cancelGeneration() {
    _backend.cancelGeneration();
  }

  /// Internal model handle.
  int? get modelHandle => _modelHandle;

  /// Internal context handle.
  int? get contextHandle => _contextHandle;

  /// Returns the name of the active GPU backend.
  Future<String> getBackendName() => _backend.getBackendName();

  /// Returns true if the current hardware and backend support GPU acceleration.
  Future<bool> isGpuSupported() => _backend.isGpuSupported();

  /// Updates the minimum log level for the backend.
  Future<void> setLogLevel(LlamaLogLevel level) => _backend.setLogLevel(level);

  /// Returns the actual context size being used by the current session.
  Future<int> getContextSize() async {
    final meta = await getMetadata();
    // Native uses llama.context_length, Web/wllama uses n_ctx
    return int.tryParse(meta['llama.context_length'] ?? meta['n_ctx'] ?? "0") ??
        0;
  }

  /// Utility to count the number of tokens in [text] without running inference.
  Future<int> getTokenCount(String text) async {
    final tokens = await tokenize(text);
    return tokens.length;
  }

  /// Releases all allocated resources.
  Future<void> dispose() async {
    if (_contextHandle != null) {
      await _backend.contextFree(_contextHandle!);
    }
    if (_modelHandle != null) {
      await _backend.modelFree(_modelHandle!);
    }
    await _backend.dispose();
    _isReady = false;
  }
}
