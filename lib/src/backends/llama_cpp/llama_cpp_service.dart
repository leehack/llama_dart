import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../core/models/chat/content_part.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/model_params.dart';
import 'bindings.dart';

/// Service responsible for managing Llama.cpp models and contexts.
///
/// This service handles the direct interaction with the native Llama.cpp library,
/// including loading models, creating contexts, managing memory, and running inference.
class LlamaCppService {
  int _nextHandle = 1;

  // --- Internal State ---
  final Map<int, _LlamaModelWrapper> _models = {};
  final Map<int, _LlamaContextWrapper> _contexts = {};
  final Map<int, int> _contextToModel = {};
  final Map<int, Pointer<llama_sampler>> _samplers = {};
  final Map<int, llama_batch> _batches = {};
  final Map<int, llama_context_params> _contextParams = {};
  final Map<int, Map<String, _LlamaLoraWrapper>> _loraAdapters = {};
  final Map<int, Map<String, double>> _activeLoras = {};

  // Mapping: modelHandle -> mtmdContextHandle
  final Map<int, int> _modelToMtmd = {};
  final Map<int, Pointer<mtmd_context>> _mtmdContexts = {};

  int _getHandle() => _nextHandle++;

  // --- Core Methods ---

  /// Sets the log level for the Llama.cpp library.
  void setLogLevel(LlamaLogLevel level) {
    llama_dart_set_log_level(level.index);
  }

  /// Initializes the Llama.cpp backend.
  ///
  /// This must be called before loading any models.
  void initializeBackend() {
    ggml_backend_load_all();
    llama_backend_init();
  }

  /// Loads a model from the specified [modelPath].
  ///
  /// Returns a handle to the loaded model.
  /// Throws an [Exception] if the file does not exist or fails to load.
  int loadModel(String modelPath, ModelParams modelParams) {
    if (!File(modelPath).existsSync()) {
      throw Exception("File not found: $modelPath");
    }
    final modelPathPtr = modelPath.toNativeUtf8();
    final mparams = llama_model_default_params();
    mparams.n_gpu_layers = modelParams.gpuLayers;
    mparams.use_mmap = true;

    final modelPtr = llama_model_load_from_file(modelPathPtr.cast(), mparams);
    malloc.free(modelPathPtr);

    if (modelPtr == nullptr) {
      throw Exception("Failed to load model");
    }

    final handle = _getHandle();
    _models[handle] = _LlamaModelWrapper(modelPtr);
    _loraAdapters[handle] = {};

    return handle;
  }

  /// Frees the model associated with [modelHandle].
  ///
  /// This also frees all contexts and LoRA adapters associated with the model.
  void freeModel(int modelHandle) {
    final model = _models.remove(modelHandle);
    if (model != null) {
      final contextsToRemove = _contextToModel.entries
          .where((e) => e.value == modelHandle)
          .map((e) => e.key)
          .toList();
      for (final ctxHandle in contextsToRemove) {
        _freeContext(ctxHandle);
      }
      final adapters = _loraAdapters.remove(modelHandle);
      adapters?.values.forEach((a) => a.dispose());

      // Free associated multimodal context
      final mmHandle = _modelToMtmd.remove(modelHandle);
      if (mmHandle != null) {
        final mmCtx = _mtmdContexts.remove(mmHandle);
        if (mmCtx != null) mtmd_free(mmCtx);
      }

      model.dispose();
    }
  }

  /// Creates an inference context for the specified [modelHandle].
  ///
  /// Returns a handle to the created context.
  /// Throws an [Exception] if the model handle is invalid or context creation fails.
  int createContext(int modelHandle, ModelParams params) {
    final model = _models[modelHandle];
    if (model == null) {
      throw Exception("Invalid model handle");
    }

    final ctxParams = llama_context_default_params();
    int nCtx = params.contextSize;
    if (nCtx <= 0) {
      nCtx = llama_model_n_ctx_train(model.pointer);
    }
    ctxParams.n_ctx = nCtx;
    ctxParams.n_batch = nCtx; // logic from original code
    ctxParams.n_ubatch = nCtx; // logic from original code

    final ctxPtr = llama_init_from_model(model.pointer, ctxParams);
    if (ctxPtr == nullptr) {
      throw Exception("Failed to create context");
    }

    final handle = _getHandle();
    _contexts[handle] = _LlamaContextWrapper(ctxPtr, model);
    _contextToModel[handle] = modelHandle;
    _activeLoras[handle] = {};
    _contextParams[handle] = ctxParams;
    _samplers[handle] = llama_sampler_chain_init(
      llama_sampler_chain_default_params(),
    );
    _batches[handle] = llama_batch_init(nCtx, 0, 1);

    return handle;
  }

  /// Frees the context associated with [contextHandle].
  void freeContext(int contextHandle) {
    _freeContext(contextHandle);
  }

  void _freeContext(int handle) {
    _contextToModel.remove(handle);
    _activeLoras.remove(handle);
    _contextParams.remove(handle);
    final sampler = _samplers.remove(handle);
    if (sampler != null && sampler != nullptr) llama_sampler_free(sampler);
    final batch = _batches.remove(handle);
    if (batch != null) llama_batch_free(batch);
    _contexts.remove(handle)?.dispose();
  }

  /// Generates text based on the given [prompt] and [params].
  ///
  /// Returns a [Stream] of token bytes.
  /// Supports multimodal input via [parts].
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    List<LlamaContentPart>? parts,
  }) async* {
    var ctx = _contexts[contextHandle];
    if (ctx == null) throw Exception("Invalid context handle");

    final modelHandle = _contextToModel[contextHandle]!;
    final model = _models[modelHandle]!;
    final modelParams = _contextParams[contextHandle]!;
    final vocab = llama_model_get_vocab(model.pointer);

    // 1. Reset Context
    ctx = _resetContext(contextHandle, ctx, model, modelParams);

    // 2. Prepare Resources
    final nCtx = llama_n_ctx(ctx.pointer);
    final batch = _batches[contextHandle]!;
    final tokensPtr = malloc<Int32>(nCtx);
    final pieceBuf = malloc<Uint8>(256);
    Pointer<Utf8> grammarPtr = nullptr;
    Pointer<Utf8> rootPtr = nullptr;

    if (params.grammar != null) {
      grammarPtr = params.grammar!.toNativeUtf8();
      rootPtr = params.grammarRoot.toNativeUtf8();
    }

    try {
      // 3. Ingest Prompt (Text or Multimodal)
      final initialTokens = _ingestPrompt(
        contextHandle,
        modelHandle,
        ctx,
        batch,
        vocab,
        prompt,
        parts,
        tokensPtr,
        nCtx,
        modelParams,
      );

      // 4. Initialize and Run Sampler Loop
      final sampler = _initializeSampler(
        params,
        vocab,
        grammarPtr,
        rootPtr,
        initialTokens,
        tokensPtr,
      );

      yield* _runInferenceLoop(
        ctx,
        batch,
        vocab,
        sampler,
        params,
        initialTokens,
        nCtx,
        cancelTokenAddress,
        pieceBuf,
        grammarPtr,
      );

      llama_sampler_free(sampler);
    } finally {
      malloc.free(tokensPtr);
      malloc.free(pieceBuf);
      if (grammarPtr != nullptr) malloc.free(grammarPtr);
      if (rootPtr != nullptr) malloc.free(rootPtr);
    }
  }

  /// Helper: Resets the context state to be ready for new generation.
  _LlamaContextWrapper _resetContext(
    int contextHandle,
    _LlamaContextWrapper ctx,
    _LlamaModelWrapper model,
    llama_context_params modelParams,
  ) {
    llama_synchronize(ctx.pointer);
    final newPtr = llama_init_from_model(model.pointer, modelParams);
    if (newPtr == nullptr) throw Exception("Failed to reset context");

    ctx.dispose();
    final newCtx = _LlamaContextWrapper(newPtr, model);
    _contexts[contextHandle] = newCtx;
    return newCtx;
  }

  /// Helper: Ingests the prompt (text or multimodal) and returns initial token count.
  int _ingestPrompt(
    int contextHandle,
    int modelHandle,
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    String prompt,
    List<LlamaContentPart>? parts,
    Pointer<Int32> tokensPtr,
    int nCtx,
    llama_context_params modelParams,
  ) {
    final mediaParts =
        parts
            ?.where((p) => p is LlamaImageContent || p is LlamaAudioContent)
            .toList() ??
        [];
    final mmHandle = _modelToMtmd[modelHandle];
    final mmCtx = mmHandle != null ? _mtmdContexts[mmHandle] : null;

    if (mediaParts.isNotEmpty && mmCtx != null) {
      return _ingestMultimodalPrompt(
        mmCtx,
        ctx,
        vocab,
        prompt,
        mediaParts,
        modelParams,
      );
    } else {
      return _ingestTextPrompt(batch, vocab, prompt, tokensPtr, nCtx, ctx);
    }
  }

  int _ingestMultimodalPrompt(
    Pointer<mtmd_context> mmCtx,
    _LlamaContextWrapper ctx,
    Pointer<llama_vocab> vocab,
    String prompt,
    List<LlamaContentPart> mediaParts,
    llama_context_params modelParams,
  ) {
    int initialTokens = 0;
    final bitmaps = malloc<Pointer<mtmd_bitmap>>(mediaParts.length);
    final chunks = mtmd_input_chunks_init();

    try {
      for (int i = 0; i < mediaParts.length; i++) {
        final p = mediaParts[i];
        bitmaps[i] = nullptr;
        if (p is LlamaImageContent) {
          if (p.path != null) {
            final pathPtr = p.path!.toNativeUtf8();
            bitmaps[i] = mtmd_helper_bitmap_init_from_file(
              mmCtx,
              pathPtr.cast(),
            );
            malloc.free(pathPtr);
          } else if (p.bytes != null) {
            final dataPtr = malloc<Uint8>(p.bytes!.length);
            dataPtr.asTypedList(p.bytes!.length).setAll(0, p.bytes!);
            bitmaps[i] = mtmd_helper_bitmap_init_from_buf(
              mmCtx,
              dataPtr.cast(),
              p.bytes!.length,
            );
            malloc.free(dataPtr);
          }
        } else if (p is LlamaAudioContent) {
          if (p.path != null) {
            final pathPtr = p.path!.toNativeUtf8();
            bitmaps[i] = mtmd_helper_bitmap_init_from_file(
              mmCtx,
              pathPtr.cast(),
            );
            malloc.free(pathPtr);
          } else if (p.samples != null) {
            final dataPtr = malloc<Float>(p.samples!.length);
            dataPtr.asTypedList(p.samples!.length).setAll(0, p.samples!);
            bitmaps[i] = mtmd_bitmap_init_from_audio(
              p.samples!.length,
              dataPtr.cast(),
            );
            malloc.free(dataPtr);
          }
        }

        if (bitmaps[i] == nullptr) {
          throw Exception("Failed to load media part $i");
        }
      }

      final inputText = malloc<mtmd_input_text>();
      final promptPtr = prompt.toNativeUtf8();
      inputText.ref.text = promptPtr.cast();

      final bos = llama_vocab_bos(vocab);
      final eos = llama_vocab_eos(vocab);
      inputText.ref.add_special = (bos != eos && bos != -1);
      inputText.ref.parse_special = true;

      final res = mtmd_tokenize(
        mmCtx,
        chunks,
        inputText,
        bitmaps.cast(),
        mediaParts.length,
      );

      if (res == 0) {
        final newPast = malloc<llama_pos>();
        if (mtmd_helper_eval_chunks(
              mmCtx,
              ctx.pointer,
              chunks,
              0,
              0,
              modelParams.n_batch,
              true,
              newPast,
            ) ==
            0) {
          initialTokens = newPast.value;
        }
        malloc.free(newPast);
      } else {
        throw Exception("mtmd_tokenize failed: $res");
      }

      malloc.free(promptPtr);
      malloc.free(inputText);
    } finally {
      for (int i = 0; i < mediaParts.length; i++) {
        if (bitmaps[i] != nullptr) mtmd_bitmap_free(bitmaps[i]);
      }
      malloc.free(bitmaps);
      mtmd_input_chunks_free(chunks);
    }
    return initialTokens;
  }

  int _ingestTextPrompt(
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    String prompt,
    Pointer<Int32> tokensPtr,
    int nCtx,
    _LlamaContextWrapper ctx,
  ) {
    final promptPtr = prompt.toNativeUtf8();
    final nTokens = llama_tokenize(
      vocab,
      promptPtr.cast(),
      promptPtr.length,
      tokensPtr,
      nCtx,
      true,
      true,
    );
    malloc.free(promptPtr);

    if (nTokens < 0 || nTokens > nCtx) {
      throw Exception("Tokenization failed or prompt too long");
    }

    batch.n_tokens = nTokens;
    for (int i = 0; i < nTokens; i++) {
      batch.token[i] = tokensPtr[i];
      batch.pos[i] = i;
      batch.n_seq_id[i] = 1;
      batch.seq_id[i][0] = 0;
      batch.logits[i] = (i == nTokens - 1) ? 1 : 0;
    }

    if (llama_decode(ctx.pointer, batch) != 0) {
      throw Exception("Initial decode failed");
    }

    return nTokens;
  }

  /// Helper: Initializes the sampler chain.
  Pointer<llama_sampler> _initializeSampler(
    GenerationParams params,
    Pointer<llama_vocab> vocab,
    Pointer<Utf8> grammarPtr,
    Pointer<Utf8> rootPtr,
    int initialTokens,
    Pointer<Int32> tokensPtr,
  ) {
    final sampler = llama_sampler_chain_init(
      llama_sampler_chain_default_params(),
    );

    llama_sampler_chain_add(
      sampler,
      llama_sampler_init_penalties(64, params.penalty, 0.0, 0.0),
    );

    if (grammarPtr != nullptr) {
      llama_sampler_chain_add(
        sampler,
        llama_sampler_init_grammar(vocab, grammarPtr.cast(), rootPtr.cast()),
      );
    }

    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(params.topK));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(params.topP, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(params.temp));

    if (params.temp <= 0) {
      llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    } else {
      final seed = params.seed ?? DateTime.now().millisecondsSinceEpoch;
      llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));
    }

    if (grammarPtr == nullptr && tokensPtr != nullptr && initialTokens > 0) {
      for (int i = 0; i < initialTokens; i++) {
        llama_sampler_accept(sampler, tokensPtr[i]);
      }
    }

    return sampler;
  }

  /// Helper: Runs the main inference loop and yields tokens.
  Stream<List<int>> _runInferenceLoop(
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    Pointer<llama_sampler> sampler,
    GenerationParams params,
    int startPos,
    int nCtx,
    int cancelTokenAddress,
    Pointer<Uint8> pieceBuf,
    Pointer<Utf8> grammarPtr,
  ) async* {
    final cancelToken = Pointer<Int8>.fromAddress(cancelTokenAddress);
    int currentPos = startPos;
    final accumulatedBytes = <int>[];

    for (int i = 0; i < params.maxTokens; i++) {
      await Future.delayed(Duration.zero);
      if (cancelToken.value == 1) break;
      if (currentPos >= nCtx) break;

      final selectedToken = llama_sampler_sample(sampler, ctx.pointer, -1);
      if (llama_vocab_is_eog(vocab, selectedToken)) break;

      final n = llama_token_to_piece(
        vocab,
        selectedToken,
        pieceBuf.cast(),
        256,
        0,
        false,
      );

      if (n > 0) {
        final bytes = pieceBuf.asTypedList(n).toList();
        yield bytes;

        if (params.stopSequences.isNotEmpty) {
          accumulatedBytes.addAll(bytes);
          if (accumulatedBytes.length > 64) {
            accumulatedBytes.removeRange(0, accumulatedBytes.length - 64);
          }
          final text = utf8.decode(accumulatedBytes, allowMalformed: true);
          if (params.stopSequences.any((s) => text.endsWith(s))) break;
        }
      }

      if (grammarPtr == nullptr) {
        llama_sampler_accept(sampler, selectedToken);
      }

      batch.n_tokens = 1;
      batch.token[0] = selectedToken;
      batch.pos[0] = currentPos++;
      batch.n_seq_id[0] = 1;
      batch.seq_id[0][0] = 0;
      batch.logits[0] = 1;

      if (llama_decode(ctx.pointer, batch) != 0) break;
    }
  }

  /// Tokenizes the given [text].
  List<int> tokenize(int modelHandle, String text, bool addSpecial) {
    final model = _models[modelHandle];
    if (model == null) return [];
    final vocab = llama_model_get_vocab(model.pointer);
    final textPtr = text.toNativeUtf8();
    final n = -llama_tokenize(
      vocab,
      textPtr.cast(),
      textPtr.length,
      nullptr,
      0,
      addSpecial,
      true,
    );
    final tokensPtr = malloc<Int32>(n);
    final actual = llama_tokenize(
      vocab,
      textPtr.cast(),
      textPtr.length,
      tokensPtr,
      n,
      addSpecial,
      true,
    );
    final result = List.generate(actual, (i) => tokensPtr[i]);
    malloc.free(textPtr);
    malloc.free(tokensPtr);
    return result;
  }

  /// Detokenizes the given [tokens].
  String detokenize(int modelHandle, List<int> tokens, bool special) {
    final model = _models[modelHandle];
    if (model == null) return "";
    final vocab = llama_model_get_vocab(model.pointer);
    final buffer = malloc<Int8>(256);
    final bytes = <int>[];
    for (final t in tokens) {
      final n = llama_token_to_piece(vocab, t, buffer.cast(), 256, 0, special);
      if (n > 0) bytes.addAll(buffer.asTypedList(n));
    }
    malloc.free(buffer);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Returns metadata for the specified [modelHandle].
  Map<String, String> getMetadata(int modelHandle) {
    final model = _models[modelHandle];
    if (model == null) return {};
    final metadata = <String, String>{};
    final keyBuf = malloc<Int8>(1024);
    final valBuf = malloc<Int8>(1024 * 64);
    final n = llama_model_meta_count(model.pointer);
    for (int i = 0; i < n; i++) {
      llama_model_meta_key_by_index(model.pointer, i, keyBuf.cast(), 1024);
      llama_model_meta_val_str_by_index(
        model.pointer,
        i,
        valBuf.cast(),
        1024 * 64,
      );
      metadata[keyBuf.cast<Utf8>().toDartString()] = valBuf
          .cast<Utf8>()
          .toDartString();
    }
    malloc.free(keyBuf);
    malloc.free(valBuf);
    return metadata;
  }

  /// Handles LoRA adapter operations.
  void handleLora(int contextHandle, String? path, double? scale, String op) {
    final ctx = _contexts[contextHandle];
    final modelHandle = _contextToModel[contextHandle];
    if (ctx == null || modelHandle == null) return;
    try {
      if (op == 'set') {
        var adapter = _loraAdapters[modelHandle]![path!];
        if (adapter == null) {
          final pathPtr = path.toNativeUtf8();
          final adapterPtr = llama_adapter_lora_init(
            _models[modelHandle]!.pointer,
            pathPtr.cast(),
          );
          malloc.free(pathPtr);
          if (adapterPtr == nullptr) {
            throw Exception("Failed to load LoRA at $path");
          }
          adapter = _LlamaLoraWrapper(adapterPtr);
          _loraAdapters[modelHandle]![path] = adapter;
        }
        llama_set_adapter_lora(ctx.pointer, adapter.pointer, scale!);
        _activeLoras[contextHandle]![path] = scale;
      } else if (op == 'remove') {
        final adapter = _loraAdapters[modelHandle]![path!];
        if (adapter != null) {
          llama_rm_adapter_lora(ctx.pointer, adapter.pointer);
        }
        _activeLoras[contextHandle]!.remove(path);
      } else if (op == 'clear') {
        llama_clear_adapter_lora(ctx.pointer);
        _activeLoras[contextHandle]!.clear();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Returns information about available backend devices.
  List<String> getBackendInfo() {
    final count = ggml_backend_dev_count();
    final devices = <String>[];
    for (var i = 0; i < count; i++) {
      final dev = ggml_backend_dev_get(i);
      if (dev == nullptr) continue;
      final ptr = ggml_backend_dev_name(dev);
      if (ptr == nullptr) continue;
      devices.add(ptr.cast<Utf8>().toDartString());
    }
    return devices;
  }

  /// Returns whether GPU offloading is supported.
  bool getGpuSupport() {
    return llama_supports_gpu_offload();
  }

  /// Disposes of all resources managed by the service.
  void dispose() {
    for (final c in _contexts.values) {
      c.dispose();
    }
    _contexts.clear();
    for (final m in _models.values) {
      m.dispose();
    }
    _models.clear();
    for (final m in _mtmdContexts.values) {
      mtmd_free(m);
    }
    _mtmdContexts.clear();
    // llama_backend_free(); // DISABLED: Prevents race conditions with other isolates
  }

  /// Creates a multimodal context (projector) for the model.
  int createMultimodalContext(int modelHandle, String mmProjPath) {
    final model = _models[modelHandle];
    if (model == null) {
      throw Exception("Invalid model handle");
    }

    final mmProjPathPtr = mmProjPath.toNativeUtf8();
    final ctxParams = mtmd_context_params_default();

    final mmCtx = mtmd_init_from_file(
      mmProjPathPtr.cast(),
      model.pointer,
      ctxParams,
    );

    malloc.free(mmProjPathPtr);

    if (mmCtx == nullptr) {
      throw Exception("Failed to load multimodal projector");
    }

    final handle = _getHandle();
    _mtmdContexts[handle] = mmCtx;
    _modelToMtmd[modelHandle] = handle;
    return handle;
  }

  /// Frees the multimodal context (projector).
  void freeMultimodalContext(int mmContextHandle) {
    final mmCtx = _mtmdContexts.remove(mmContextHandle);
    if (mmCtx != null) {
      mtmd_free(mmCtx);
      _modelToMtmd.removeWhere((k, v) => v == mmContextHandle);
    }
  }

  // --- Helper Getters ---

  /// Returns the context size for the given [contextHandle].
  int getContextSize(int contextHandle) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) return 0;
    return llama_n_ctx(ctx.pointer);
  }

  /// Checks if a multimodal context exists.
  bool hasMultimodalContext(int mmContextHandle) {
    return _mtmdContexts.containsKey(mmContextHandle);
  }
}

// --- Native Wrappers ---

class _LlamaLoraWrapper {
  final Pointer<llama_adapter_lora> pointer;
  _LlamaLoraWrapper(this.pointer);
  void dispose() {
    llama_adapter_lora_free(pointer);
  }
}

class _LlamaModelWrapper {
  final Pointer<llama_model> pointer;
  _LlamaModelWrapper(this.pointer);
  void dispose() {
    llama_model_free(pointer);
  }
}

class _LlamaContextWrapper {
  final Pointer<llama_context> pointer;
  final _LlamaModelWrapper? _modelKeepAlive;
  _LlamaContextWrapper(this.pointer, this._modelKeepAlive);
  void dispose() {
    // ignore: unused_local_variable
    final _ = _modelKeepAlive;
    llama_free(pointer);
  }
}
