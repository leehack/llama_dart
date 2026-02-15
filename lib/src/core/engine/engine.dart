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
  LlamaLogLevel _dartLogLevel = LlamaLogLevel.none;
  LlamaLogLevel _nativeLogLevel = LlamaLogLevel.none;

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

  /// Sets both Dart and native log levels to [level].
  ///
  /// For independent control, use [setDartLogLevel] and [setNativeLogLevel].
  Future<void> setLogLevel(LlamaLogLevel level) async {
    await setDartLogLevel(level);
    await setNativeLogLevel(level);
  }

  /// Sets only the Dart-side logger level.
  Future<void> setDartLogLevel(LlamaLogLevel level) async {
    _dartLogLevel = level;
    LlamaLogger.instance.setLevel(level);
  }

  /// Sets only the native backend logger level.
  Future<void> setNativeLogLevel(LlamaLogLevel level) async {
    _nativeLogLevel = level;
    await backend.setLogLevel(level);
  }

  /// Current Dart-side logger level.
  LlamaLogLevel get dartLogLevel => _dartLogLevel;

  /// Current native backend logger level.
  LlamaLogLevel get nativeLogLevel => _nativeLogLevel;

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

    if (backend.supportsUrlLoading) {
      LlamaLogger.instance.info(
        'Backend supports URL loading, attempting loadModelFromUrl.',
      );
      return loadModelFromUrl(path, modelParams: modelParams);
    }

    try {
      await backend.setLogLevel(_nativeLogLevel);
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

    if (!backend.supportsUrlLoading) {
      throw UnimplementedError(
        "loadModelFromUrl for Native should be handled by the caller or a helper.",
      );
    }

    try {
      await backend.setLogLevel(_nativeLogLevel);
      _ensureNotReady();
      _modelPath = url;

      _modelHandle = await backend.modelLoadFromUrl(
        url,
        modelParams,
        onProgress: onProgress,
      );
      _contextHandle = await backend.contextCreate(_modelHandle!, modelParams);
      _isReady = true;

      LlamaLogger.instance.info(
        'Model $modelName loaded successfully from $url',
      );
    } catch (e, stackTrace) {
      if (_contextHandle != null) {
        try {
          await backend.contextFree(_contextHandle!);
        } catch (_) {}
        _contextHandle = null;
      }
      if (_modelHandle != null) {
        try {
          await backend.modelFree(_modelHandle!);
        } catch (_) {}
        _modelHandle = null;
      }
      _modelPath = null;
      _isReady = false;

      LlamaLogger.instance.error(
        'Failed to load model $modelName from URL $url',
        e,
        stackTrace,
      );
      throw LlamaModelException("Failed to load model from $url", e);
    }
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
  /// For TranslateGemma-style templates, set [sourceLangCode] and
  /// [targetLangCode] to control language metadata injected into user
  /// content blocks.
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
    String? sourceLangCode,
    String? targetLangCode,
  }) async* {
    _ensureReady();

    // Build messages with tool system prompt if tools provided
    // Skip tool injection if toolChoice is none
    final effectiveTools = toolChoice == ToolChoice.none ? null : tools;

    // Apply chat template with tools - returns grammar for constraining
    final result = await chatTemplate(
      messages,
      tools: effectiveTools,
      toolChoice: toolChoice ?? ToolChoice.auto,
      sourceLangCode: sourceLangCode,
      targetLangCode: targetLangCode,
    );
    final stops = {...result.stopSequences, ...?params?.stopSequences}.toList();

    LlamaLogger.instance.debug('Chat template result:');
    LlamaLogger.instance.debug('  Format: ${result.format}');
    LlamaLogger.instance.debug('  Prompt: ${result.prompt}');
    LlamaLogger.instance.debug('  Stop sequences: $stops');
    LlamaLogger.instance.debug('  Grammar present: ${result.grammar != null}');
    LlamaLogger.instance.debug('  Grammar lazy: ${result.grammarLazy}');
    LlamaLogger.instance.debug(
      '  Grammar triggers: ${result.grammarTriggers.length}',
    );
    LlamaLogger.instance.debug(
      '  Thinking forced open: ${result.thinkingForcedOpen}',
    );
    LlamaLogger.instance.debug(
      '  Handler ID: ${result.handlerId ?? '(builtin)'}',
    );

    // Collect media parts from all messages
    final allParts = messages.expand((m) => m.parts).toList();

    final hasTemplateGrammar = result.grammar != null;
    final effectiveGrammar = hasTemplateGrammar
        ? result.grammar
        : params?.grammar;
    final effectiveGrammarLazy = hasTemplateGrammar
        ? result.grammarLazy
        : (params?.grammarLazy ?? false);
    final effectiveGrammarTriggers = hasTemplateGrammar
        ? result.grammarTriggers
              .map(
                (trigger) => GenerationGrammarTrigger(
                  type: trigger.type,
                  value: trigger.value,
                  token: trigger.token,
                ),
              )
              .toList(growable: false)
        : (params?.grammarTriggers ?? const <GenerationGrammarTrigger>[]);
    final effectivePreservedTokens = hasTemplateGrammar
        ? result.preservedTokens
        : (params?.preservedTokens ?? const <String>[]);

    // Generate raw tokens with grammar constraint
    final tokenStream = generate(
      result.prompt,
      params: (params ?? const GenerationParams()).copyWith(
        stopSequences: stops,
        grammar: effectiveGrammar,
        grammarLazy: effectiveGrammarLazy,
        grammarTriggers: effectiveGrammarTriggers,
        preservedTokens: effectivePreservedTokens,
      ),
      parts: allParts,
    );

    // Parse the tokens into structured chunks using the detected format
    final completionId = DateTime.now().millisecondsSinceEpoch.toString();
    final buffer = StringBuffer();

    final thinkingTags = ChatTemplateEngine.thinkingTagsFor(
      result.format,
      handlerId: result.handlerId,
    );
    final startTag = thinkingTags.startTag;
    final endTag = thinkingTags.endTag;

    var isThinking = result.thinkingForcedOpen;
    var pendingBuffer = '';

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
    final parsed = ChatTemplateEngine.parse(
      result.format,
      fullOutput,
      thinkingForcedOpen: result.thinkingForcedOpen,
      handlerId: result.handlerId,
    );

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
  ///
  /// Pass [customTemplate] or [customHandlerId] to override default routing.
  /// Pass [responseFormat] or legacy [jsonSchema] to request structured output
  /// grammar generation.
  ///
  /// For TranslateGemma-style templates, [sourceLangCode] and
  /// [targetLangCode] are forwarded to the template renderer.
  Future<LlamaChatTemplateResult> chatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
    Map<String, dynamic>? jsonSchema,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    Map<String, dynamic>? responseFormat,
    String? customTemplate,
    String? customHandlerId,
    String? sourceLangCode,
    String? targetLangCode,
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

    if (sourceLangCode != null && sourceLangCode.isNotEmpty) {
      metadata['source_lang_code'] = sourceLangCode;
    }
    if (targetLangCode != null && targetLangCode.isNotEmpty) {
      metadata['target_lang_code'] = targetLangCode;
    }

    // Use ChatTemplateEngine for format detection, rendering, and grammar
    try {
      final effectiveResponseFormat =
          responseFormat ??
          (jsonSchema == null
              ? null
              : {
                  'type': 'json_schema',
                  'json_schema': {'schema': jsonSchema},
                });

      final result = ChatTemplateEngine.render(
        templateSource: templateSource,
        messages: messages,
        metadata: metadata,
        addAssistant: addAssistant,
        tools: tools,
        toolChoice: toolChoice,
        responseFormat: effectiveResponseFormat,
        customTemplate: customTemplate,
        customHandlerId: customHandlerId,
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
        parser: result.parser,
        tokenCount: tokens.length,
        handlerId: result.handlerId,
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
