import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import '../../common/loader.dart';
import '../../models/llama_log_level.dart';
import 'native_helpers.dart';
import 'worker_messages.dart';

// Re-export messages so native_backend.dart can see them via worker.dart if needed
export 'worker_messages.dart';

// --- Internal State ---

class _LlamaWorkerState {
  int _nextHandle = 1;
  final Map<int, _LlamaModelWrapper> models = {};
  final Map<int, _LlamaContextWrapper> contexts = {};
  final Map<int, int> contextToModel = {};
  final Map<int, Pointer<llama_sampler>> samplers = {};
  final Map<int, llama_batch> batches = {};
  final Map<int, llama_context_params> contextParams = {};
  final Map<int, Map<String, _LlamaLoraWrapper>> loraAdapters = {};
  final Map<int, Map<String, double>> activeLoras = {};

  int _getHandle() => _nextHandle++;
}

// --- Native Wrappers ---
// NOTE: We intentionally do NOT use NativeFinalizers here.
// llama.cpp logs during cleanup (llama_free, etc.), and invoking a Dart callback
// from a NativeFinalizer causes "Cannot invoke native callback from a leaf call"
// crash. Cleanup is done explicitly via dispose().

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

// --- Global for Logging ---
NativeCallable<ggml_log_callbackFunction>? _noOpLogCallback;

// No-op callback that does nothing - used to suppress all logging
void _noOpCallback(int level, Pointer<Char> text, Pointer<Void> userData) {
  // Intentionally empty - suppresses all llama.cpp logging
}

/// Entry point for the llama worker isolate.
void llamaWorkerEntry(SendPort initialSendPort) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);

  final state = _LlamaWorkerState();

  // Metal Residency Hack
  if (Platform.isMacOS) {
    try {
      final libc = DynamicLibrary.open('libc.dylib');
      final setenv = libc
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
            int Function(Pointer<Utf8>, Pointer<Utf8>, int)
          >('setenv');
      final name = "GGML_METAL_RESIDENCY_DISABLE".toNativeUtf8();
      final value = "1".toNativeUtf8();
      setenv(name, value, 1);
      malloc.free(name);
      malloc.free(value);
    } catch (_) {}
  }

  // CRITICAL: Perform "leafy" initialization BEFORE setting the log callback.
  // This avoids the "Cannot invoke native callback from a leaf call" crash.
  ggml_backend_load_all();
  llama_backend_init();

  // Initialize no-op callback for log suppression
  _noOpLogCallback ??= NativeCallable<ggml_log_callbackFunction>.listener(
    _noOpCallback,
  );

  receivePort.listen((message) {
    if (message is WorkerHandshake) {
      // Default: logging enabled (use llama.cpp's default stderr logging)
    } else if (message is ModelLoadRequest) {
      _handleModelLoad(message, state);
    } else if (message is LogLevelRequest) {
      // Toggle logging on/off based on level
      if (message.logLevel == LlamaLogLevel.none) {
        // Disable logging: set a no-op callback that suppresses all output
        llama_log_set(_noOpLogCallback!.nativeFunction, nullptr);
        ggml_log_set(_noOpLogCallback!.nativeFunction, nullptr);
      } else {
        // Enable logging: reset to default (nullptr means use default logging)
        llama_log_set(nullptr, nullptr);
        ggml_log_set(nullptr, nullptr);
      }

      message.sendPort.send(DoneResponse());
    } else if (message is ModelFreeRequest) {
      _handleModelFree(message, state);
    } else if (message is ContextCreateRequest) {
      _handleContextCreate(message, state);
    } else if (message is ContextFreeRequest) {
      _handleContextFree(message, state);
    } else if (message is GenerateRequest) {
      _handleGenerate(message, state);
    } else if (message is TokenizeRequest) {
      _handleTokenize(message, state);
    } else if (message is DetokenizeRequest) {
      _handleDetokenize(message, state);
    } else if (message is MetadataRequest) {
      _handleMetadata(message, state);
    } else if (message is ApplyTemplateRequest) {
      _handleApplyTemplate(message, state);
    } else if (message is LoraRequest) {
      _handleLora(message, state);
    } else if (message is BackendInfoRequest) {
      _handleBackendInfo(message);
    } else if (message is GpuSupportRequest) {
      _handleGpuSupport(message);
    } else if (message is DisposeRequest) {
      _handleDispose(message, state, receivePort);
    }
  });
}

// --- Handlers ---

void _handleModelLoad(ModelLoadRequest request, _LlamaWorkerState state) {
  try {
    // Toggle logging on/off based on model params
    if (request.modelParams.logLevel == LlamaLogLevel.none) {
      llama_log_set(_noOpLogCallback!.nativeFunction, nullptr);
      ggml_log_set(_noOpLogCallback!.nativeFunction, nullptr);
    } else {
      llama_log_set(nullptr, nullptr);
      ggml_log_set(nullptr, nullptr);
    }

    if (!File(request.modelPath).existsSync()) {
      request.sendPort.send(
        ErrorResponse("File not found: ${request.modelPath}"),
      );
      return;
    }
    final modelPathPtr = request.modelPath.toNativeUtf8();
    final mparams = llama_model_default_params();
    mparams.n_gpu_layers = request.modelParams.gpuLayers;
    mparams.use_mmap = true;

    final modelPtr = llama_model_load_from_file(modelPathPtr.cast(), mparams);
    malloc.free(modelPathPtr);

    if (modelPtr == nullptr) {
      request.sendPort.send(ErrorResponse("Failed to load model"));
      return;
    }

    final handle = state._getHandle();
    state.models[handle] = _LlamaModelWrapper(modelPtr);
    state.loraAdapters[handle] = {};
    request.sendPort.send(HandleResponse(handle));
  } catch (e) {
    request.sendPort.send(ErrorResponse(e.toString()));
  }
}

void _handleModelFree(ModelFreeRequest request, _LlamaWorkerState state) {
  final model = state.models.remove(request.modelHandle);
  if (model != null) {
    final contextsToRemove = state.contextToModel.entries
        .where((e) => e.value == request.modelHandle)
        .map((e) => e.key)
        .toList();
    for (final ctxHandle in contextsToRemove) {
      _freeContext(ctxHandle, state);
    }
    final adapters = state.loraAdapters.remove(request.modelHandle);
    adapters?.values.forEach((a) => a.dispose());
    model.dispose();
  }
  request.sendPort.send(DoneResponse());
}

void _handleContextCreate(
  ContextCreateRequest request,
  _LlamaWorkerState state,
) {
  final model = state.models[request.modelHandle];
  if (model == null) {
    request.sendPort.send(ErrorResponse("Invalid model handle"));
    return;
  }
  try {
    final ctxParams = llama_context_default_params();
    int nCtx = request.params.contextSize;
    if (nCtx <= 0) {
      nCtx = llama_model_n_ctx_train(model.pointer);
      if (nCtx > 4096) nCtx = 4096;
    }
    ctxParams.n_ctx = nCtx;
    ctxParams.n_batch = nCtx;
    ctxParams.n_ubatch = nCtx;

    final ctxPtr = llama_init_from_model(model.pointer, ctxParams);
    if (ctxPtr == nullptr) {
      request.sendPort.send(ErrorResponse("Failed to create context"));
      return;
    }

    final handle = state._getHandle();
    state.contexts[handle] = _LlamaContextWrapper(ctxPtr, model);
    state.contextToModel[handle] = request.modelHandle;
    state.activeLoras[handle] = {};
    state.contextParams[handle] = ctxParams;
    state.samplers[handle] = llama_sampler_chain_init(
      llama_sampler_chain_default_params(),
    );
    state.batches[handle] = llama_batch_init(nCtx, 0, 1);

    request.sendPort.send(HandleResponse(handle));
  } catch (e) {
    request.sendPort.send(ErrorResponse(e.toString()));
  }
}

void _handleContextFree(ContextFreeRequest request, _LlamaWorkerState state) {
  _freeContext(request.contextHandle, state);
  request.sendPort.send(DoneResponse());
}

void _freeContext(int handle, _LlamaWorkerState state) {
  state.contextToModel.remove(handle);
  state.activeLoras.remove(handle);
  state.contextParams.remove(handle);
  final sampler = state.samplers.remove(handle);
  if (sampler != null) llama_sampler_free(sampler);
  final batch = state.batches.remove(handle);
  if (batch != null) llama_batch_free(batch);
  state.contexts.remove(handle)?.dispose();
}

void _handleGenerate(GenerateRequest request, _LlamaWorkerState state) {
  var ctx = state.contexts[request.contextHandle];
  if (ctx == null) {
    request.sendPort.send(ErrorResponse("Invalid context handle"));
    return;
  }

  final modelHandle = state.contextToModel[request.contextHandle]!;
  final model = state.models[modelHandle]!;
  final modelParams = state.contextParams[request.contextHandle]!;

  llama_synchronize(ctx.pointer);
  final newPtr = llama_init_from_model(model.pointer, modelParams);
  if (newPtr == nullptr) {
    request.sendPort.send(ErrorResponse("Failed to reset context"));
    return;
  }
  ctx.dispose();
  final newCtx = _LlamaContextWrapper(newPtr, model);
  state.contexts[request.contextHandle] = newCtx;
  ctx = newCtx;

  final vocab = llama_model_get_vocab(model.pointer);
  final oldSampler = state.samplers[request.contextHandle]!;
  final b = state.batches[request.contextHandle]!;
  final nCtx = llama_n_ctx(ctx.pointer);

  llama_sampler_free(oldSampler);
  final sampler = llama_sampler_chain_init(
    llama_sampler_chain_default_params(),
  );
  state.samplers[request.contextHandle] = sampler;
  llama_sampler_chain_add(
    sampler,
    llama_sampler_init_penalties(64, request.params.penalty, 0.0, 0.0),
  );
  llama_sampler_chain_add(
    sampler,
    llama_sampler_init_top_k(request.params.topK),
  );
  llama_sampler_chain_add(
    sampler,
    llama_sampler_init_top_p(request.params.topP, 1),
  );
  llama_sampler_chain_add(
    sampler,
    llama_sampler_init_temp(request.params.temp),
  );
  llama_sampler_chain_add(
    sampler,
    llama_sampler_init_dist(
      request.params.seed ?? DateTime.now().millisecondsSinceEpoch,
    ),
  );

  final tokensPtr = malloc<Int32>(nCtx);
  final pieceBuf = malloc<Uint8>(256);
  final cancelToken = Pointer<Int8>.fromAddress(request.cancelTokenAddress);

  try {
    final promptPtr = request.prompt.toNativeUtf8();
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
      request.sendPort.send(
        ErrorResponse("Tokenization failed or prompt too long"),
      );
      return;
    }

    b.n_tokens = nTokens;
    for (int i = 0; i < nTokens; i++) {
      b.token[i] = tokensPtr[i];
      b.pos[i] = i;
      b.n_seq_id[i] = 1;
      b.seq_id[i][0] = 0;
      b.logits[i] = (i == nTokens - 1) ? 1 : 0;
    }

    if (llama_decode(ctx.pointer, b) != 0) {
      request.sendPort.send(ErrorResponse("Initial decode failed"));
      return;
    }

    int currentPos = nTokens;
    String fullText = "";
    for (int i = 0; i < request.params.maxTokens; i++) {
      if (cancelToken.value == 1) break;
      if (currentPos >= nCtx) break;
      final tokenId = llama_sampler_sample(
        sampler,
        ctx.pointer,
        b.n_tokens - 1,
      );
      if (llama_vocab_is_eog(vocab, tokenId)) break;
      final n = llama_token_to_piece(
        vocab,
        tokenId,
        pieceBuf.cast(),
        256,
        0,
        false,
      );
      if (n > 0) {
        final bytes = pieceBuf.asTypedList(n).toList();
        request.sendPort.send(TokenResponse(bytes));
        if (request.params.stopSequences.isNotEmpty) {
          fullText += utf8.decode(bytes, allowMalformed: true);
          if (request.params.stopSequences.any((s) => fullText.endsWith(s))) {
            break;
          }
        }
      }
      b.n_tokens = 1;
      b.token[0] = tokenId;
      b.pos[0] = currentPos++;
      b.n_seq_id[0] = 1;
      b.seq_id[0][0] = 0;
      b.logits[0] = 1;
      if (llama_decode(ctx.pointer, b) != 0) break;
    }
    request.sendPort.send(DoneResponse());
  } catch (e) {
    request.sendPort.send(ErrorResponse(e.toString()));
  } finally {
    malloc.free(tokensPtr);
    malloc.free(pieceBuf);
  }
}

void _handleTokenize(TokenizeRequest request, _LlamaWorkerState state) {
  final model = state.models[request.modelHandle];
  if (model == null) return;
  final vocab = llama_model_get_vocab(model.pointer);
  final textPtr = request.text.toNativeUtf8();
  final n = -llama_tokenize(
    vocab,
    textPtr.cast(),
    textPtr.length,
    nullptr,
    0,
    request.addSpecial,
    true,
  );
  final tokensPtr = malloc<Int32>(n);
  final actual = llama_tokenize(
    vocab,
    textPtr.cast(),
    textPtr.length,
    tokensPtr,
    n,
    request.addSpecial,
    true,
  );
  final result = List.generate(actual, (i) => tokensPtr[i]);
  malloc.free(textPtr);
  malloc.free(tokensPtr);
  request.sendPort.send(TokenizeResponse(result));
}

void _handleDetokenize(DetokenizeRequest request, _LlamaWorkerState state) {
  final model = state.models[request.modelHandle];
  if (model == null) return;
  final vocab = llama_model_get_vocab(model.pointer);
  final buffer = malloc<Int8>(256);
  final bytes = <int>[];
  for (final t in request.tokens) {
    final n = llama_token_to_piece(
      vocab,
      t,
      buffer.cast(),
      256,
      0,
      request.special,
    );
    if (n > 0) bytes.addAll(buffer.asTypedList(n));
  }
  malloc.free(buffer);
  request.sendPort.send(
    DetokenizeResponse(utf8.decode(bytes, allowMalformed: true)),
  );
}

void _handleMetadata(MetadataRequest request, _LlamaWorkerState state) {
  final model = state.models[request.modelHandle];
  if (model == null) return;
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
  request.sendPort.send(MetadataResponse(metadata));
}

void _handleApplyTemplate(
  ApplyTemplateRequest request,
  _LlamaWorkerState state,
) {
  final model = state.models[request.modelHandle];
  if (model == null) return;
  final nMsgs = request.messages.length;
  final chatMsgs = malloc<llama_chat_message>(nMsgs);
  final allocated = <Pointer<Char>>[];
  try {
    for (int i = 0; i < nMsgs; i++) {
      final m = request.messages[i];
      allocated.add(chatMsgs[i].role = m.role.toNativeUtf8().cast());
      allocated.add(chatMsgs[i].content = m.content.toNativeUtf8().cast());
    }
    final tmplBuf = malloc<Char>(1024 * 64);
    final tmplRes = llama_model_meta_val_str(
      model.pointer,
      "tokenizer.chat_template".toNativeUtf8().cast(),
      tmplBuf,
      1024 * 64,
    );
    Pointer<Char> tmplPtr = tmplRes >= 0 ? tmplBuf : nullptr;
    final required = llama_chat_apply_template(
      tmplPtr,
      chatMsgs,
      nMsgs,
      request.addAssistant,
      nullptr,
      0,
    );
    final buf = malloc<Char>(required + 1);
    llama_chat_apply_template(
      tmplPtr,
      chatMsgs,
      nMsgs,
      request.addAssistant,
      buf,
      required + 1,
    );
    final prompt = buf.cast<Utf8>().toDartString();
    malloc.free(buf);
    malloc.free(tmplBuf);
    final stops = <String>{};
    final vocab = llama_model_get_vocab(model.pointer);
    final eos = llama_vocab_eos(vocab);
    if (eos != -1) {
      final textPtr = llama_vocab_get_text(vocab, eos);
      if (textPtr != nullptr) stops.add(textPtr.cast<Utf8>().toDartString());
    }
    request.sendPort.send(ApplyTemplateResponse(prompt, stops.toList()));
  } catch (e) {
    request.sendPort.send(ErrorResponse(e.toString()));
  } finally {
    for (var ptr in allocated) {
      malloc.free(ptr);
    }
    malloc.free(chatMsgs);
  }
}

void _handleLora(LoraRequest request, _LlamaWorkerState state) {
  final ctx = state.contexts[request.contextHandle];
  final modelHandle = state.contextToModel[request.contextHandle];
  if (ctx == null || modelHandle == null) return;
  try {
    if (request.op == 'set') {
      var adapter = state.loraAdapters[modelHandle]![request.path!];
      if (adapter == null) {
        final pathPtr = request.path!.toNativeUtf8();
        final adapterPtr = llama_adapter_lora_init(
          state.models[modelHandle]!.pointer,
          pathPtr.cast(),
        );
        malloc.free(pathPtr);
        if (adapterPtr == nullptr) {
          request.sendPort.send(
            ErrorResponse("Failed to load LoRA at ${request.path}"),
          );
          return;
        }
        adapter = _LlamaLoraWrapper(adapterPtr);
        state.loraAdapters[modelHandle]![request.path!] = adapter;
      }
      llama_set_adapter_lora(ctx.pointer, adapter.pointer, request.scale!);
      state.activeLoras[request.contextHandle]![request.path!] = request.scale!;
    } else if (request.op == 'remove') {
      final adapter = state.loraAdapters[modelHandle]![request.path!];
      if (adapter != null) llama_rm_adapter_lora(ctx.pointer, adapter.pointer);
      state.activeLoras[request.contextHandle]!.remove(request.path);
    } else if (request.op == 'clear') {
      llama_clear_adapter_lora(ctx.pointer);
      state.activeLoras[request.contextHandle]!.clear();
    }
    request.sendPort.send(DoneResponse());
  } catch (e) {
    request.sendPort.send(ErrorResponse(e.toString()));
  }
}

void _handleBackendInfo(WorkerRequest request) {
  request.sendPort.send(
    BackendInfoResponse(NativeHelpers.getAvailableDevices().join(", ")),
  );
}

void _handleGpuSupport(WorkerRequest request) {
  request.sendPort.send(GpuSupportResponse(llama_supports_gpu_offload()));
}

void _handleDispose(
  DisposeRequest request,
  _LlamaWorkerState state,
  ReceivePort rp,
) {
  for (final m in state.models.values) {
    m.dispose();
  }
  for (final c in state.contexts.values) {
    c.dispose();
  }
  llama_backend_free();
  request.sendPort.send(null);
  rp.close();
  Isolate.exit();
}
