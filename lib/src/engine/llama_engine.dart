import 'dart:async';
import 'dart:convert';
import '../backend/llama_backend_interface.dart';
import 'llama_tokenizer.dart';
import 'chat_template_processor.dart';
import '../common/exceptions.dart';
import '../models/llama_log_level.dart';
import '../models/llama_chat_message.dart';
import '../models/model_params.dart';
import '../models/generation_params.dart';
import '../models/llama_content_part.dart';
import '../models/llama_chat_template_result.dart';

/// Low-level engine that orchestrates models and contexts.
///
/// [LlamaEngine] provides core functionality for loading models, running
/// inference, and managing tokenization. For high-level chat functionality
/// with history management and tool support, use [ChatSession].
///
/// Example:
/// ```dart
/// final engine = LlamaEngine(LlamaBackend());
/// await engine.loadModel('path/to/model.gguf');
///
/// // Low-level: raw prompt generation
/// await for (final token in engine.generate('Hello, world!')) {
///   print(token);
/// }
///
/// // For chat, use ChatSession instead:
/// final session = ChatSession(engine);
/// await for (final token in session.chat('Hello!')) {
///   print(token);
/// }
/// ```
class LlamaEngine {
  final LlamaBackend _backend;
  int? _modelHandle;
  int? _contextHandle;
  int? _mmContextHandle;
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
    try {
      final name = await _backend.getBackendName();
      if (name.startsWith("WASM")) {
        return loadModelFromUrl(path, modelParams: modelParams);
      }
    } catch (_) {}

    try {
      await _backend.setLogLevel(modelParams.logLevel);
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

    throw UnimplementedError(
      "loadModelFromUrl for Native should be handled by the caller or a helper.",
    );
  }

  /// Loads a multimodal projector model for vision/audio support.
  Future<void> loadMultimodalProjector(String mmProjPath) async {
    if (!_isReady || _modelHandle == null) {
      throw LlamaContextException("Load model before loading projector.");
    }
    _mmContextHandle = await _backend.multimodalContextCreate(
      _modelHandle!,
      mmProjPath,
    );
  }

  /// Whether the loaded model supports vision.
  Future<bool> get supportsVision async =>
      _mmContextHandle != null &&
      await _backend.supportsVision(_mmContextHandle!);

  /// Whether the loaded model supports audio.
  Future<bool> get supportsAudio async =>
      _mmContextHandle != null &&
      await _backend.supportsAudio(_mmContextHandle!);

  /// Generates a stream of text tokens based on the provided raw [prompt].
  ///
  /// This is the low-level generation API. For chat-style interactions with
  /// proper template formatting, use [ChatSession.chat] instead.
  ///
  /// If [parts] contains media content, markers will be automatically injected
  /// into the prompt if missing.
  Stream<String> generate(
    String prompt, {
    GenerationParams params = const GenerationParams(),
    List<LlamaContentPart>? parts,
  }) async* {
    if (!_isReady || _contextHandle == null) {
      throw LlamaContextException("Engine not ready. Call loadModel first.");
    }

    // Safeguard: Inject markers if they are missing from the prompt but parts are provided.
    final mediaCount =
        parts
            ?.where((p) => p is LlamaImageContent || p is LlamaAudioContent)
            .length ??
        0;
    final markerCount = '<__media__>'.allMatches(prompt).length;

    String finalPrompt = prompt;
    if (mediaCount > 0 && markerCount == 0) {
      // Prepend missing markers at the start of the prompt
      finalPrompt = ('<__media__>\n' * mediaCount) + prompt;
    }

    final stream = _backend.generate(
      _contextHandle!,
      finalPrompt,
      params,
      parts: parts,
    );

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

  /// Formats a list of [messages] into a prompt string using the model's template.
  ///
  /// This is useful for preparing messages before calling [generate] directly,
  /// or for inspecting the formatted prompt for debugging purposes.
  Future<LlamaChatTemplateResult> chatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
  }) async {
    if (!_isReady || _templateProcessor == null) {
      throw LlamaContextException("Engine not ready.");
    }
    final result = await _templateProcessor!.apply(
      messages,
      addAssistant: addAssistant,
    );
    final tokens = await tokenize(result.prompt);
    return LlamaChatTemplateResult(
      prompt: result.prompt,
      stopSequences: result.stopSequences,
      tokenCount: tokens.length,
    );
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
    if (_isReady && _contextHandle != null) {
      final size = await _backend.getContextSize(_contextHandle!);
      if (size > 0) return size;
    }
    final meta = await getMetadata();
    // Try common context length keys in metadata
    final ctx =
        meta['llm.context_length'] ??
        meta['llama.context_length'] ??
        meta['model.context_length'] ??
        meta['n_ctx'] ??
        "0";
    return int.tryParse(ctx) ?? 0;
  }

  /// Utility to count the number of tokens in [text] without running inference.
  Future<int> getTokenCount(String text) async {
    final tokens = await tokenize(text);
    return tokens.length;
  }

  /// Releases all allocated resources.
  Future<void> dispose() async {
    if (_mmContextHandle != null) {
      await _backend.multimodalContextFree(_mmContextHandle!);
    }
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
