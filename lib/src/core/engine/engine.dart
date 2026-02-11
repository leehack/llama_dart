import 'dart:async';
import 'dart:convert';
import '../../backends/backend.dart';
import '../template/chat_template_engine.dart';
import '../exceptions.dart';
import '../models/config/log_level.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/completion_chunk.dart';
import '../models/chat/content_part.dart';
import '../models/chat/chat_template_result.dart';
import '../llama_logger.dart';

import '../models/inference/model_params.dart';
import '../models/inference/generation_params.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';

/// Stateless chat completions engine (like OpenAI's Chat Completions API).
///
/// [LlamaEngine] is the primary API for chat-based inference. Each call to
/// [create] is stateless - you must pass the full conversation history.
/// For automatic history management, use [ChatSession] instead.
///
/// Example (OpenAI-style stateless usage):
/// ```dart
/// final engine = LlamaEngine(LlamaBackend());
/// await engine.loadModel('path/to/model.gguf');
///
/// // Build messages array (you manage history)
/// final messages = [
///   LlamaChatMessage.fromText(role: LlamaChatRole.system, text: 'You are helpful.'),
///   LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello!'),
/// ];
///
/// // Create completion
/// final response = await engine.create(messages).join();
///
/// // Append response and continue conversation
/// messages.add(LlamaChatMessage.fromText(role: LlamaChatRole.assistant, text: response));
/// messages.add(LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Follow up?'));
/// final response2 = await engine.create(messages).join();
/// ```
class LlamaEngine {
  /// The backend implementation used for inference.
  final LlamaBackend backend;
  int? _modelHandle;
  int? _contextHandle;
  int? _mmContextHandle;
  bool _isReady = false;
  String? _modelPath;
  LlamaLogLevel _logLevel = LlamaLogLevel.none;

  /// Configures logging for the library.
  ///
  /// [level] determines which logs are output.
  /// [handler] is an optional custom callback. If null and level != none,
  /// logs are printed to stdout.
  static void configureLogging({
    LlamaLogLevel level = LlamaLogLevel.none,
    LlamaLogHandler? handler,
  }) {
    LlamaLogger.instance.setLevel(level);
    LlamaLogger.instance.setHandler(handler);
  }

  /// Creates a new [LlamaEngine] instance with the given [backend].
  LlamaEngine(this.backend);

  /// Sets the log level for the engine and the underlying native backend.
  ///
  /// This can be called at any time to change the verbosity of logs.
  Future<void> setLogLevel(LlamaLogLevel level) async {
    _logLevel = level;
    // Update Dart logger
    LlamaLogger.instance.setLevel(level);
    // Update native backend
    await backend.setLogLevel(level);
  }

  // ============================================================
  // MODEL LIFECYCLE
  // ============================================================

  /// Whether the engine is initialized and ready for inference.
  bool get isReady => _isReady;

  /// Loads a model from a local [path].
  ///
  /// Optionally provide [ModelParams] to configure context size, GPU offloading,
  /// and more.
  Future<void> loadModel(
    String path, {
    ModelParams modelParams = const ModelParams(),
  }) async {
    final modelName = path.split('/').last;
    LlamaLogger.instance.info('Loading model: $modelName');

    // If backend supports URL loading (e.g. WASM), use it.
    try {
      try {
        final name = await backend.getBackendName();
        if (name.contains("WASM") || name.contains("Wllama")) {
          LlamaLogger.instance.info(
            'Backend $name supports URL loading, attempting loadModelFromUrl.',
          );
          return loadModelFromUrl(path, modelParams: modelParams);
        }
      } catch (e, stackTrace) {
        LlamaLogger.instance.warning(
          'Could not determine backend name or it does not support URL loading: $e',
          e,
          stackTrace,
        );
      }
    } catch (e, stackTrace) {
      LlamaLogger.instance.warning(
        'Error during initial backend check for URL loading: $e',
        e,
        stackTrace,
      );
    }

    try {
      await backend.setLogLevel(_logLevel);
      _ensureNotReady();
      _modelPath = path;
      _modelHandle = await backend.modelLoad(path, modelParams);
      _contextHandle = await backend.contextCreate(_modelHandle!, modelParams);
      _isReady = true;
      LlamaLogger.instance.info(
        'Model $modelName loaded successfully from $path',
      );
    } catch (e, stackTrace) {
      LlamaLogger.instance.error(
        'Failed to load model $modelName from $path',
        e,
        stackTrace,
      );
      throw LlamaModelException("Failed to load model from $path", e);
    }
  }

  /// Loads a model from a [url].
  ///
  /// This is typically used on the Web platform. Use [ModelParams] to
  /// configure loading options.
  Future<void> loadModelFromUrl(
    String url, {
    ModelParams modelParams = const ModelParams(),
    Function(double progress)? onProgress,
  }) async {
    final modelName = url.split('/').last;
    LlamaLogger.instance.info('Loading model from URL: $modelName');

    try {
      final backendName = await backend.getBackendName();
      if (backendName.startsWith("WASM")) {
        _modelHandle = await backend.modelLoadFromUrl(
          url,
          modelParams,
          onProgress: onProgress,
        );
        _contextHandle = await backend.contextCreate(
          _modelHandle!,
          modelParams,
        );
        LlamaLogger.instance.info(
          'Model $modelName loaded successfully from $url',
        );
        return;
      }
    } catch (e, stackTrace) {
      LlamaLogger.instance.error(
        'Failed to load model $modelName from URL $url',
        e,
        stackTrace,
      );
      throw LlamaModelException("Failed to load model from $url", e);
    }

    throw UnimplementedError(
      "loadModelFromUrl for Native should be handled by the caller or a helper.",
    );
  }

  /// Loads a multimodal projector model for vision/audio support.
  Future<void> loadMultimodalProjector(String mmProjPath) async {
    final mmProjName = mmProjPath.split('/').last;
    LlamaLogger.instance.info('Loading multimodal projector: $mmProjName');
    _ensureReady(requireContext: false);
    try {
      _mmContextHandle = await backend.multimodalContextCreate(
        _modelHandle!,
        mmProjPath,
      );
      LlamaLogger.instance.info(
        'Multimodal projector $mmProjName loaded successfully',
      );
    } catch (e, stackTrace) {
      LlamaLogger.instance.error(
        'Failed to load multimodal projector $mmProjName',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Releases all allocated resources.
  Future<void> dispose() async {
    await unloadModel();
    await backend.dispose();
  }

  /// Unloads the currently loaded model and frees its resources.
  Future<void> unloadModel() async {
    if (!isReady && _modelHandle == null && _mmContextHandle == null) return;
    LlamaLogger.instance.info('Unloading model...');
    if (_contextHandle != null) {
      await backend.contextFree(_contextHandle!);
      _contextHandle = null;
    }
    if (_mmContextHandle != null) {
      await backend.multimodalContextFree(_mmContextHandle!);
      _mmContextHandle = null;
    }
    if (_modelHandle != null) {
      await backend.modelFree(_modelHandle!);
      _modelHandle = null;
    }
    _modelPath = null;
    _isReady = false;
    LlamaLogger.instance.info('Model unloaded.');
  }

  // ============================================================
  // CHAT COMPLETIONS (Primary API)
  // ============================================================

  /// Creates a chat completion from a list of [messages].
  ///
  /// This is the primary stateless API (like OpenAI's Chat Completions).
  /// You must pass the full conversation history with each call.
  ///
  /// Pass [tools] to enable function calling. Use [toolChoice] to control
  /// whether the model should use tools:
  /// - [ToolChoice.none]: Model won't call any tool
  /// - [ToolChoice.auto]: Model can choose (default when tools present)
  /// - [ToolChoice.required]: Model must call at least one tool
  ///
  /// Example:
  /// ```dart
  /// final messages = [
  ///   LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello!'),
  /// ];
  /// await for (final token in engine.create(messages)) {
  ///   print(token);
  /// }
  /// ```
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
  }) async* {
    _ensureReady();

    // Build messages with tool system prompt if tools provided
    // Skip tool injection if toolChoice is none
    final effectiveTools = toolChoice == ToolChoice.none ? null : tools;

    // Apply chat template with tools - returns grammar for constraining
    final result = await chatTemplate(messages, tools: effectiveTools);
    final stops = {...result.stopSequences, ...?params?.stopSequences}.toList();

    LlamaLogger.instance.debug('Chat template result:');
    LlamaLogger.instance.debug('  Format: ${result.format}');
    LlamaLogger.instance.debug('  Prompt: ${result.prompt}');
    LlamaLogger.instance.debug('  Stop sequences: $stops');
    LlamaLogger.instance.debug('  Grammar present: ${result.grammar != null}');
    LlamaLogger.instance.debug(
      '  Thinking forced open: ${result.thinkingForcedOpen}',
    );

    // Collect media parts from all messages
    final allParts = messages.expand((m) => m.parts).toList();

    // Use grammar from template only when tool use is REQUIRED.
    // For 'auto' mode, we let the model decide without grammar forcing tool output.
    // This prevents models without native tool support from always generating tool calls.
    final effectiveGrammar = toolChoice == ToolChoice.required
        ? (result.grammar ?? params?.grammar)
        : params?.grammar;

    // Generate raw tokens with grammar constraint
    final tokenStream = generate(
      result.prompt,
      params: (params ?? const GenerationParams()).copyWith(
        stopSequences: stops,
        grammar: effectiveGrammar,
      ),
      parts: allParts,
    );

    // Parse the tokens into structured chunks using the detected format
    final completionId = DateTime.now().millisecondsSinceEpoch.toString();
    final buffer = StringBuffer();

    var isThinking = result.thinkingForcedOpen;
    var pendingBuffer = '';
    const startTag = '<think>';
    const endTag = '</think>';

    await for (final token in tokenStream) {
      buffer.write(token);
      pendingBuffer += token;

      while (pendingBuffer.isNotEmpty) {
        if (!isThinking) {
          final startIdx = pendingBuffer.indexOf(startTag);
          final endIdx = pendingBuffer.indexOf(endTag);

          if (startIdx != -1 && (endIdx == -1 || startIdx < endIdx)) {
            // Found start tag (and it's first)
            final before = pendingBuffer.substring(0, startIdx);
            if (before.isNotEmpty) {
              yield LlamaCompletionChunk(
                id: 'chatcmpl-$completionId',
                object: 'chat.completion.chunk',
                created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                model: _modelPath ?? 'llama_model',
                choices: [
                  LlamaCompletionChunkChoice(
                    index: 0,
                    delta: LlamaCompletionChunkDelta(content: before),
                  ),
                ],
              );
            }
            isThinking = true;
            pendingBuffer = pendingBuffer.substring(startIdx + startTag.length);
            continue;
          } else if (endIdx != -1) {
            // Found end tag unexpectedly (missed start tag)
            final reasoning = pendingBuffer.substring(0, endIdx);
            if (reasoning.isNotEmpty) {
              yield LlamaCompletionChunk(
                id: 'chatcmpl-$completionId',
                object: 'chat.completion.chunk',
                created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                model: _modelPath ?? 'llama_model',
                choices: [
                  LlamaCompletionChunkChoice(
                    index: 0,
                    delta: LlamaCompletionChunkDelta(thinking: reasoning),
                  ),
                ],
              );
            }
            isThinking = false;
            pendingBuffer = pendingBuffer.substring(endIdx + endTag.length);
            continue;
          }
          // Check if buffer ends with a partial start tag
          var potentialMatch = false;
          for (var i = startTag.length - 1; i >= 1; i--) {
            if (pendingBuffer.endsWith(startTag.substring(0, i))) {
              final emitIdx = pendingBuffer.length - i;
              if (emitIdx > 0) {
                yield LlamaCompletionChunk(
                  id: 'chatcmpl-$completionId',
                  object: 'chat.completion.chunk',
                  created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  model: _modelPath ?? 'llama_model',
                  choices: [
                    LlamaCompletionChunkChoice(
                      index: 0,
                      delta: LlamaCompletionChunkDelta(
                        content: pendingBuffer.substring(0, emitIdx),
                      ),
                    ),
                  ],
                );
                pendingBuffer = pendingBuffer.substring(emitIdx);
              }
              potentialMatch = true;
              break;
            }
          }
          if (!potentialMatch) {
            yield LlamaCompletionChunk(
              id: 'chatcmpl-$completionId',
              object: 'chat.completion.chunk',
              created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              model: _modelPath ?? 'llama_model',
              choices: [
                LlamaCompletionChunkChoice(
                  index: 0,
                  delta: LlamaCompletionChunkDelta(content: pendingBuffer),
                ),
              ],
            );
            pendingBuffer = '';
          }
          break;
        } else {
          final endIdx = pendingBuffer.indexOf(endTag);
          if (endIdx != -1) {
            // Found end tag
            final reasoning = pendingBuffer.substring(0, endIdx);
            if (reasoning.isNotEmpty) {
              yield LlamaCompletionChunk(
                id: 'chatcmpl-$completionId',
                object: 'chat.completion.chunk',
                created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                model: _modelPath ?? 'llama_model',
                choices: [
                  LlamaCompletionChunkChoice(
                    index: 0,
                    delta: LlamaCompletionChunkDelta(thinking: reasoning),
                  ),
                ],
              );
            }
            isThinking = false;
            pendingBuffer = pendingBuffer.substring(endIdx + endTag.length);
            continue;
          }
          // Check if buffer ends with a partial end tag
          var potentialMatch = false;
          for (var i = endTag.length - 1; i >= 1; i--) {
            if (pendingBuffer.endsWith(endTag.substring(0, i))) {
              final emitIdx = pendingBuffer.length - i;
              if (emitIdx > 0) {
                yield LlamaCompletionChunk(
                  id: 'chatcmpl-$completionId',
                  object: 'chat.completion.chunk',
                  created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  model: _modelPath ?? 'llama_model',
                  choices: [
                    LlamaCompletionChunkChoice(
                      index: 0,
                      delta: LlamaCompletionChunkDelta(
                        thinking: pendingBuffer.substring(0, emitIdx),
                      ),
                    ),
                  ],
                );
                pendingBuffer = pendingBuffer.substring(emitIdx);
              }
              potentialMatch = true;
              break;
            }
          }
          if (!potentialMatch) {
            yield LlamaCompletionChunk(
              id: 'chatcmpl-$completionId',
              object: 'chat.completion.chunk',
              created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              model: _modelPath ?? 'llama_model',
              choices: [
                LlamaCompletionChunkChoice(
                  index: 0,
                  delta: LlamaCompletionChunkDelta(thinking: pendingBuffer),
                ),
              ],
            );
            pendingBuffer = '';
          }
          break;
        }
      }
    }

    // Final flush of any pending buffer
    if (pendingBuffer.isNotEmpty) {
      yield LlamaCompletionChunk(
        id: 'chatcmpl-$completionId',
        object: 'chat.completion.chunk',
        created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        model: _modelPath ?? 'llama_model',
        choices: [
          LlamaCompletionChunkChoice(
            index: 0,
            delta: isThinking
                ? LlamaCompletionChunkDelta(thinking: pendingBuffer)
                : LlamaCompletionChunkDelta(content: pendingBuffer),
          ),
        ],
      );
    }

    // After generation completes, parse the full output for tool calls
    final fullOutput = buffer.toString();
    final parsed = ChatTemplateEngine.parse(result.format, fullOutput);

    LlamaLogger.instance.debug('Parsed result: $parsed');
    if (parsed.hasToolCalls) {
      for (final tc in parsed.toolCalls) {
        LlamaLogger.instance.debug(
          '  Tool call: ${tc.function?.name}(${tc.function?.arguments})',
        );
      }
    }
    if (parsed.hasReasoning) {
      LlamaLogger.instance.debug(
        '  Reasoning: ${parsed.reasoningContent?.length ?? 0} chars',
      );
    }

    if (parsed.hasToolCalls) {
      // Emit a final chunk with tool calls
      yield LlamaCompletionChunk(
        id: 'chatcmpl-$completionId',
        object: 'chat.completion.chunk',
        created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        model: _modelPath ?? 'llama_model',
        choices: [
          LlamaCompletionChunkChoice(
            index: 0,
            delta: LlamaCompletionChunkDelta(toolCalls: parsed.toolCalls),
            finishReason: 'tool_calls',
          ),
        ],
      );
    } else {
      // Emit the stop chunk
      yield LlamaCompletionChunk(
        id: 'chatcmpl-$completionId',
        object: 'chat.completion.chunk',
        created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        model: _modelPath ?? 'llama_model',
        choices: [
          LlamaCompletionChunkChoice(
            index: 0,
            delta: LlamaCompletionChunkDelta(),
            finishReason: 'stop',
          ),
        ],
      );
    }
  }

  /// Formats a list of [messages] into a prompt string using the model's template.
  ///
  /// This is useful for preparing messages before calling [generate] directly,
  /// or for inspecting the formatted prompt for debugging purposes.
  Future<LlamaChatTemplateResult> chatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
    Map<String, dynamic>? jsonSchema,
    List<ToolDefinition>? tools,
  }) async {
    _ensureReady(requireContext: false);

    String? templateSource;

    // Get metadata for template source and token info
    Map<String, String> metadata = {};
    try {
      metadata = (await getMetadata()).map(
        (key, value) => MapEntry(key, value.toString()),
      );
      templateSource = metadata['tokenizer.chat_template'];
    } catch (e) {
      LlamaLogger.instance.warning('Failed to read metadata: $e');
    }

    // Use ChatTemplateEngine for format detection, rendering, and grammar
    try {
      final result = ChatTemplateEngine.render(
        templateSource: templateSource,
        messages: messages,
        metadata: metadata,
        addAssistant: addAssistant,
        tools: tools,
      );

      final tokens = await tokenize(result.prompt);
      return LlamaChatTemplateResult(
        prompt: result.prompt,
        format: result.format,
        grammar: result.grammar,
        grammarLazy: result.grammarLazy,
        additionalStops: result.additionalStops,
        grammarTriggers: result.grammarTriggers,
        thinkingForcedOpen: result.thinkingForcedOpen,
        preservedTokens: result.preservedTokens,
        tokenCount: tokens.length,
      );
    } catch (e) {
      LlamaLogger.instance.warning('ChatTemplateEngine.render failed: $e');

      // Ultimate fallback: simple concatenation
      var prompt = messages.map((m) => m.content).join('\n');
      if (addAssistant) {
        prompt += '\nAssistant:';
      }
      final tokens = await tokenize(prompt);
      return LlamaChatTemplateResult(prompt: prompt, tokenCount: tokens.length);
    }
  }

  // ============================================================
  // LOW-LEVEL GENERATION
  // ============================================================

  /// Generates a stream of text tokens based on the provided raw [prompt].
  ///
  /// This is the low-level generation API. For chat-style interactions with
  /// proper template formatting, use [create] instead.
  ///
  /// Use [GenerationParams] to tune the sampling process.
  ///
  /// If [parts] contains media content, markers will be automatically injected
  /// into the prompt if missing.
  Stream<String> generate(
    String prompt, {
    GenerationParams params = const GenerationParams(),
    List<LlamaContentPart>? parts,
  }) async* {
    _ensureReady();

    final stream = backend.generate(
      _contextHandle!,
      prompt,
      params,
      parts: parts,
    );

    yield* stream.transform(const Utf8Decoder(allowMalformed: true));
  }

  /// Immediately cancels any ongoing generation process.
  void cancelGeneration() {
    backend.cancelGeneration();
  }

  // ============================================================
  // TOKENIZATION
  // ============================================================

  /// Encodes the given [text] into a list of token IDs.
  Future<List<int>> tokenize(String text, {bool addSpecial = true}) {
    _ensureReady(requireContext: false);
    return backend.tokenize(_modelHandle!, text, addSpecial: addSpecial);
  }

  /// Decodes a list of [tokens] back into a human-readable string.
  Future<String> detokenize(List<int> tokens, {bool special = false}) {
    _ensureReady(requireContext: false);
    return backend.detokenize(_modelHandle!, tokens, special: special);
  }

  /// Utility to count the number of tokens in [text] without running inference.
  Future<int> getTokenCount(String text) async {
    final tokens = await tokenize(text);
    return tokens.length;
  }

  // ============================================================
  // MODEL INTROSPECTION
  // ============================================================

  /// Retrieves all available metadata from the loaded model.
  Future<Map<String, String>> getMetadata() {
    if (!_isReady || _modelHandle == null) {
      return Future.value({});
    }
    return backend.modelMetadata(_modelHandle!);
  }

  /// Returns the actual context size being used by the current session.
  Future<int> getContextSize() async {
    if (_isReady && _contextHandle != null) {
      final size = await backend.getContextSize(_contextHandle!);
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

  /// Whether the loaded model supports vision.
  Future<bool> get supportsVision async =>
      _mmContextHandle != null &&
      await backend.supportsVision(_mmContextHandle!);

  /// Whether the loaded model supports audio.
  Future<bool> get supportsAudio async =>
      _mmContextHandle != null &&
      await backend.supportsAudio(_mmContextHandle!);

  // ============================================================
  // LORA MANAGEMENT
  // ============================================================

  /// Dynamically loads or updates a LoRA adapter's scale.
  Future<void> setLora(String path, {double scale = 1.0}) {
    _ensureReady();
    return backend.setLoraAdapter(_contextHandle!, path, scale);
  }

  /// Removes a specific LoRA adapter from the active session.
  Future<void> removeLora(String path) {
    _ensureReady();
    return backend.removeLoraAdapter(_contextHandle!, path);
  }

  /// Removes all active LoRA adapters from the current context.
  Future<void> clearLoras() {
    _ensureReady();
    return backend.clearLoraAdapters(_contextHandle!);
  }

  // ============================================================
  // BACKEND UTILITIES
  // ============================================================

  /// Internal model handle.
  int? get modelHandle => _modelHandle;

  /// Internal context handle.
  int? get contextHandle => _contextHandle;

  /// Returns the name of the active GPU backend.
  Future<String> getBackendName() => backend.getBackendName();

  /// Returns true if the current hardware and backend support GPU acceleration.
  Future<bool> isGpuSupported() => backend.isGpuSupported();

  /// Returns total and free VRAM in bytes.
  Future<({int total, int free})> getVramInfo() => backend.getVramInfo();

  // ============================================================
  // INTERNAL HELPERS
  // ============================================================

  /// Validates engine is ready for inference.
  void _ensureReady({bool requireContext = true}) {
    if (!_isReady) {
      throw LlamaContextException("Engine not ready. Call loadModel first.");
    }
    if (requireContext && _contextHandle == null) {
      throw LlamaContextException("Context not initialized.");
    }
  }

  /// Ensures the engine is NOT currently loaded.
  void _ensureNotReady() {
    if (_isReady) {
      throw LlamaStateException(
        'Model is already loaded. Call unloadModel() first.',
      );
    }
  }
}
