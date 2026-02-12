import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart';
import '../backend.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/generation_params.dart';
import 'interop.dart';

@JS('Object.keys')
external JSArray _objectKeys(JSObject obj);

/// Creates a [WebLlamaBackend].
LlamaBackend createBackend() => WebLlamaBackend();

/// Web implementation of [LlamaBackend] using wllama.
///
/// This backend uses WebAssembly to run llama.cpp in the browser.
class WebLlamaBackend implements LlamaBackend {
  final String _wllamaJsUrl;
  final String _wllamaWasmUrl;
  final Wllama Function(JSObject pathConfig, [WllamaConfig? config])?
  _wllamaFactory;

  Wllama? _wllama;
  bool _isReady = false;
  AbortController? _abortController;
  LlamaLogLevel _logLevel = LlamaLogLevel.info;
  int? _lastNCtx;

  /// Creates a new [WebLlamaBackend] with the given [wllamaPath] and [wasmPath].
  WebLlamaBackend({
    String? wllamaPath,
    String? wasmPath,
    Wllama Function(JSObject pathConfig, [WllamaConfig? config])? wllamaFactory,
  }) : _wllamaJsUrl =
           wllamaPath ??
           'https://cdn.jsdelivr.net/npm/@wllama/wllama@2.3.7/esm/index.js',
       _wllamaWasmUrl =
           wasmPath ??
           'https://cdn.jsdelivr.net/npm/@wllama/wllama@2.3.7/esm/single-thread/wllama.wasm',
       _wllamaFactory = wllamaFactory;

  @override
  bool get isReady => _isReady;

  Future<void> _ensureLibrary() async {
    if (_wllamaFactory != null) return; // Using factory, no need to load script
    if (globalContext.has('Wllama')) {
      console.log('WebLlamaBackend: Wllama global found'.toJS);
      return;
    }

    console.log('WebLlamaBackend: Injecting Wllama script'.toJS);
    final completer = Completer<void>();

    // Define a temporary global callback for the module to call when ready
    const callbackName = '__wllama_init_callback';
    globalContext.setProperty(
      callbackName.toJS,
      () {
        console.log('WebLlamaBackend: Script initialized via callback'.toJS);
        completer.complete();
      }.toJS,
    );

    final script = HTMLScriptElement();
    script.type = 'module';
    script.text =
        '''
      import("$_wllamaJsUrl").then(mod => {
        window.Wllama = mod.Wllama;
        if (window.$callbackName) window.$callbackName();
      }).catch(e => {
        console.error("WebLlamaBackend: Failed to import Wllama", e);
      });
    ''';

    script.addEventListener(
      'error',
      (Event e) {
        console.error('WebLlamaBackend: Script tag error'.toJS);
        if (!completer.isCompleted) {
          completer.completeError(
            Exception('Failed to load wllama script tag'),
          );
        }
      }.toJS,
    );

    document.head!.append(script);

    // Add a timeout just in case
    await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        if (!completer.isCompleted) {
          throw Exception('Timeout waiting for wllama to load');
        }
      },
    );

    // Cleanup global callback
    globalContext.delete(callbackName.toJS);
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    return modelLoadFromUrl(path, params);
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async {
    console.log('WebLlamaBackend: modelLoadFromUrl called for $url'.toJS);

    _lastNCtx = params.contextSize;
    await _ensureLibrary();
    console.log('WebLlamaBackend: Library ensured'.toJS);

    if (_wllama != null) {
      console.log('WebLlamaBackend: Exiting previous Wllama instance'.toJS);
      try {
        await _wllama!.exit()?.toDart;
      } catch (e) {
        console.warn(
          'WebLlamaBackend: Error exiting previous instance: $e'.toJS,
        );
      }
      _wllama = null;
    }

    final pathConfig = JSObject();
    pathConfig.setProperty(
      'single-thread/wllama.wasm'.toJS,
      _wllamaWasmUrl.toJS,
    );
    // Attempt to deduce multi-thread URL if we are using the default CDN
    if (_wllamaWasmUrl.contains('single-thread')) {
      final multiThreadUrl = _wllamaWasmUrl.replaceFirst(
        'single-thread',
        'multi-thread',
      );
      pathConfig.setProperty(
        'multi-thread/wllama.wasm'.toJS,
        multiThreadUrl.toJS,
      );
    }

    final config = WllamaConfig(
      suppressNativeLog: _logLevel == LlamaLogLevel.none,
      logger: WllamaLogger(
        debug: (JSAny? msg) {
          if (_logLevel.index <= LlamaLogLevel.debug.index) {
            console.debug(msg);
          }
        }.toJS,
        log: (JSAny? msg) {
          if (_logLevel.index <= LlamaLogLevel.info.index) {
            console.log(msg);
          }
        }.toJS,
        warn: (JSAny? msg) {
          if (_logLevel.index <= LlamaLogLevel.warn.index) {
            console.warn(msg);
          }
        }.toJS,
        error: (JSAny? msg) {
          if (_logLevel.index <= LlamaLogLevel.error.index) {
            console.error(msg);
          }
        }.toJS,
      ),
    );

    _wllama = _wllamaFactory != null
        ? _wllamaFactory(pathConfig, config)
        : Wllama(pathConfig, config);
    console.log('WebLlamaBackend: Wllama instance created'.toJS);

    final loadPromise = _wllama!.loadModelFromUrl(
      url,
      LoadModelOptions(
        useCache: true,
        nCtx: params.contextSize,
        progressCallback: onProgress == null
            ? null
            : (JSAny p) {
                if (p.isA<JSObject>()) {
                  final obj = p as JSObject;
                  final loaded = obj.getProperty('loaded'.toJS);
                  final total = obj.getProperty('total'.toJS);

                  if (loaded.isA<JSNumber>() && total.isA<JSNumber>()) {
                    final l = (loaded as JSNumber).toDartDouble;
                    final t = (total as JSNumber).toDartDouble;
                    if (t > 0) {
                      onProgress(l / t);
                    }
                  }
                } else if (p.isA<JSNumber>()) {
                  onProgress((p as JSNumber).toDartDouble);
                }
              }.toJS,
      ),
    );

    console.log('WebLlamaBackend: awaiting loadPromise'.toJS);
    try {
      if (loadPromise != null) await loadPromise.toDart;
      console.log('WebLlamaBackend: loadPromise complete'.toJS);
    } catch (e) {
      console.error('WebLlamaBackend: loadModelFromUrl failed: $e'.toJS);
      rethrow;
    }

    _isReady = true;
    return 1; // wllama usually manages one model at a time
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    await dispose();
  }

  @override
  Future<void> dispose() async {
    final result = _wllama?.exit();
    if (result != null) await _toFuture(result);
    _wllama = null;
    _isReady = false;
  }

  Future<JSAny?> _toFuture(JSAny? value) async {
    if (value == null) return null;
    if (value.isA<JSPromise>()) {
      return (value as JSPromise).toDart;
    }
    return value;
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    return 1; // wllama manages context internally with model
  }

  @override
  Future<void> contextFree(int contextHandle) async {
    // No-op for wllama
  }

  @override
  Future<int> getContextSize(int contextHandle) async {
    if (_wllama != null) {
      try {
        final info = _wllama!.getLoadedContextInfo();
        if (info.nCtx > 0) return info.nCtx;
      } catch (_) {}

      try {
        if (_wllama!.nCtx > 0) return _wllama!.nCtx;
      } catch (_) {}
    }
    return _lastNCtx ?? 0;
  }

  @override
  void cancelGeneration() {
    _abortController?.abort();
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    final controller = StreamController<List<int>>();
    _abortController = AbortController();

    final onNewToken =
        (
              JSAny? token,
              JSUint8Array? piece,
              JSString? currentText,
              JSAny? optionals,
            ) {
              if (piece == null) return;
              final bytes = piece.toDart;

              // Stop sequence check
              if (params.stopSequences.isNotEmpty && currentText != null) {
                final fullText = currentText.toDart;
                if (params.stopSequences.any((s) => fullText.endsWith(s))) {
                  _abortController?.abort();
                  return;
                }
              }
              controller.add(bytes);
            }
            .toJS;

    final opts = CompletionOptions(
      nPredict: params.maxTokens,
      sampling: WllamaSamplingConfig.create(
        temp: params.temp,
        topK: params.topK,
        topP: params.topP,
        repeatPenalty: params.penalty,
        grammar: params.grammar,
      ),
      seed: params.seed ?? DateTime.now().millisecondsSinceEpoch,
      onNewToken: onNewToken as JSFunction,
      signal: _abortController?.signal,
    );

    final result = _wllama!.createCompletion(prompt, opts);
    _toFuture(
      result,
    ).then((_) => controller.close(), onError: (e) => controller.addError(e));

    return controller.stream;
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    final result = _wllama?.tokenize(text, addSpecial);
    if (result == null) return [];
    final res = await _toFuture(result);
    if (res == null) return [];
    if (res.isA<JSUint32Array>()) {
      return (res as JSUint32Array).toDart.cast<int>().toList();
    }
    if (res.isA<JSInt32Array>()) {
      return (res as JSInt32Array).toDart.cast<int>().toList();
    }
    return [];
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async {
    final jsTokens = tokens.map((e) => e.toJS).toList().toJS;
    final result = _wllama?.detokenize(jsTokens);
    if (result == null) return "";
    final res = await _toFuture(result);
    return (res as JSString?)?.toDart ?? "";
  }

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    final metaJs = _wllama?.getModelMetadata();
    if (metaJs == null || !metaJs.isA<JSObject>()) return {};

    final result = <String, String>{};
    final jsMeta = metaJs;
    final keys = _objectKeys(jsMeta);

    for (int i = 0; i < keys.length; i++) {
      final key = (keys.getProperty(i.toJS) as JSString).toDart;
      final val = jsMeta.getProperty(key.toJS);
      if (val.isA<JSString>()) {
        result[key] = (val as JSString).toDart;
      } else if (val.isA<JSNumber>()) {
        result[key] = (val as JSNumber).toDartInt.toString();
      } else {
        result[key] = val.toString();
      }
    }
    return result;
  }

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async {
    // wllama v2 doesn't support LoRA yet
  }

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async {
    // wllama v2 doesn't support LoRA yet
  }

  @override
  Future<void> clearLoraAdapters(int contextHandle) async {
    // wllama v2 doesn't support LoRA yet
  }

  @override
  Future<String> getBackendName() async {
    if (_wllama != null) {
      final isMulti = _wllama!.isMultithread();
      return "WASM (Web, ${isMulti ? 'Multi-thread' : 'Single-thread'})";
    }
    return "WASM (Web)";
  }

  @override
  bool get supportsUrlLoading => true;

  @override
  Future<bool> isGpuSupported() async {
    return false; // WebGPU not supported yet in this binding
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    _logLevel = level;
    // Note: wllama doesn't support changing loggers after init,
    // but the next time a model is loaded it will use the new level.
  }

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    return null; // Not supported on web yet
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {
    // No-op
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) async {
    return false;
  }

  @override
  Future<bool> supportsVision(int mmContextHandle) async {
    return false;
  }

  @override
  Future<({int total, int free})> getVramInfo() async {
    return (total: 0, free: 0); // Not applicable for web yet
  }

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async {
    if (_wllama == null) return "";
    // Simple JS conversion
    final jsMessages = JSArray();
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final jsMsg = JSObject();
      jsMsg.setProperty('role'.toJS, (msg['role'] as String).toJS);
      jsMsg.setProperty('content'.toJS, (msg['content'] as String).toJS);
      jsMessages.setProperty(i.toJS, jsMsg);
    }

    final result = await _wllama!
        .formatChat(jsMessages, addAssistant, customTemplate)
        .toDart;
    return result.toDart;
  }
}
