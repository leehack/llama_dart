import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

import '../../core/models/chat/content_part.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/model_params.dart';
import '../backend.dart';
import 'interop.dart';

@JS('Object.keys')
external JSArray _objectKeys(JSObject obj);

/// Web backend backed by the llama.cpp bridge runtime.
class WebGpuLlamaBackend implements LlamaBackend {
  static const Duration _bridgeReadyTimeout = Duration(seconds: 12);
  static const Duration _bridgePollInterval = Duration(milliseconds: 100);

  final String? _bridgeScriptUrl;
  final String? _bridgeWasmUrl;
  final String? _bridgeWorkerUrl;
  final LlamaWebGpuBridge Function([WebGpuBridgeConfig? config])?
  _bridgeFactory;

  LlamaWebGpuBridge? _bridge;
  bool _usingBridge = false;
  bool _isReady = false;
  LlamaLogLevel _logLevel = LlamaLogLevel.info;
  AbortController? _abortController;
  int? _lastNCtx;
  bool _mmContextActive = false;

  /// Creates a bridge-backed web backend.
  WebGpuLlamaBackend({
    String? bridgeScriptUrl,
    String? wasmUrl,
    String? workerUrl,
    LlamaWebGpuBridge Function([WebGpuBridgeConfig? config])? bridgeFactory,
  }) : _bridgeScriptUrl = bridgeScriptUrl,
       _bridgeWasmUrl = wasmUrl,
       _bridgeWorkerUrl = workerUrl,
       _bridgeFactory = bridgeFactory;

  @override
  bool get isReady => _isReady;

  Future<void> _loadBridgeScript() async {
    final scriptUrl = _bridgeScriptUrl;
    if (scriptUrl == null || scriptUrl.isEmpty) {
      return;
    }

    if (globalContext.has('LlamaWebGpuBridge')) {
      return;
    }

    final completer = Completer<void>();
    const callbackName = '__llamadart_webgpu_init';

    globalContext.setProperty(
      callbackName.toJS,
      (JSAny? err) {
        if (err != null) {
          if (!completer.isCompleted) {
            completer.completeError(
              Exception('WebGPU bridge init failed: $err'),
            );
          }
          return;
        }

        if (!completer.isCompleted) {
          completer.complete();
        }
      }.toJS,
    );

    final script = HTMLScriptElement();
    script.type = 'module';
    script.text =
        '''
      import("$scriptUrl").then(mod => {
        if (mod?.LlamaWebGpuBridge) {
          window.LlamaWebGpuBridge = mod.LlamaWebGpuBridge;
        }
        if (window.$callbackName) {
          window.$callbackName();
        }
      }).catch(e => {
        if (window.$callbackName) {
          window.$callbackName(e);
        }
      });
    ''';

    script.addEventListener(
      'error',
      ((Event _) {
        if (!completer.isCompleted) {
          completer.completeError(
            Exception('Failed to load WebGPU bridge script'),
          );
        }
      }).toJS,
    );

    document.head?.append(script);

    try {
      await completer.future.timeout(const Duration(seconds: 12));
    } finally {
      globalContext.delete(callbackName.toJS);
    }
  }

  WebGpuBridgeConfig _createBridgeConfig() {
    final logger = JSObject();
    logger.setProperty(
      'debug'.toJS,
      (JSAny? msg) {
        if (_logLevel.index <= LlamaLogLevel.debug.index) {
          console.debug(msg);
        }
      }.toJS,
    );
    logger.setProperty(
      'log'.toJS,
      (JSAny? msg) {
        if (_logLevel.index <= LlamaLogLevel.info.index) {
          console.log(msg);
        }
      }.toJS,
    );
    logger.setProperty(
      'warn'.toJS,
      (JSAny? msg) {
        if (_logLevel.index <= LlamaLogLevel.warn.index) {
          console.warn(msg);
        }
      }.toJS,
    );
    logger.setProperty(
      'error'.toJS,
      (JSAny? msg) {
        if (_logLevel.index <= LlamaLogLevel.error.index) {
          console.error(msg);
        }
      }.toJS,
    );

    final coreModuleUrl = _getGlobalString('__llamadartBridgeCoreModuleUrl');

    return WebGpuBridgeConfig(
      wasmUrl: _bridgeWasmUrl?.toJS,
      workerUrl: _bridgeWorkerUrl?.toJS,
      coreModuleUrl: coreModuleUrl?.toJS,
      logLevel: _logLevel.index,
      logger: logger,
    );
  }

  Future<void> _waitForPreloadedBridge() async {
    if (globalContext.has('LlamaWebGpuBridge')) {
      return;
    }

    final deadline = DateTime.now().add(_bridgeReadyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (globalContext.has('LlamaWebGpuBridge')) {
        return;
      }

      if (_getBridgeLoadError() != null) {
        return;
      }

      await Future<void>.delayed(_bridgePollInterval);
    }
  }

  Future<bool> _ensureBridge() async {
    if (_bridge != null) {
      return true;
    }

    if (_bridgeFactory != null) {
      _bridge = _bridgeFactory(_createBridgeConfig());
      return true;
    }

    if (!globalContext.has('LlamaWebGpuBridge')) {
      final scriptUrl = _bridgeScriptUrl;
      if (scriptUrl != null && scriptUrl.isNotEmpty) {
        await _loadBridgeScript();
      } else {
        await _waitForPreloadedBridge();
      }
    }

    if (!globalContext.has('LlamaWebGpuBridge')) {
      return false;
    }

    _bridge = LlamaWebGpuBridge(_createBridgeConfig());
    return true;
  }

  Future<void> _safeDisposeBridge() async {
    final bridge = _bridge;
    _bridge = null;
    if (bridge == null) {
      return;
    }

    final disposePromise = bridge.dispose();
    if (disposePromise != null) {
      await disposePromise.toDart;
    }
    _usingBridge = false;
    _isReady = false;
    _mmContextActive = false;
  }

  Future<void> _activateBridge() async {
    if (_usingBridge && _bridge != null) {
      return;
    }

    final ready = await _ensureBridge();
    if (!ready || _bridge == null) {
      final loadError = _getBridgeLoadError();
      final message = _buildBridgeUnavailableMessage(loadError);
      throw UnsupportedError(message);
    }

    _usingBridge = true;
    _syncBridgeLogLevel();
  }

  void _syncBridgeLogLevel() {
    final bridge = _bridge;
    if (bridge == null) {
      return;
    }

    try {
      bridge.setLogLevel(_logLevel.index);
    } catch (_) {
      // Older bridge bundles may not expose runtime log-level updates.
    }
  }

  String _buildBridgeUnavailableMessage(String? loadError) {
    final source = _getGlobalString('__llamadartBridgeAssetSource');
    final moduleUrl = _getGlobalString('__llamadartBridgeModuleUrl');

    final locationParts = <String>[];
    if (source != null) {
      locationParts.add('source=$source');
    }
    if (moduleUrl != null) {
      locationParts.add('module=$moduleUrl');
    }

    final locationSuffix = locationParts.isEmpty
        ? ''
        : ' [${locationParts.join(', ')}]';

    final safariHint =
        loadError != null &&
            loadError.contains('compiled without support for Safari browser')
        ? ' Use bridge assets built with Safari support '
              '(MIN_SAFARI_VERSION universal build).'
        : '';

    final base = loadError == null
        ? 'Web bridge is unavailable. Ensure LlamaWebGpuBridge assets are loaded and reachable.'
        : 'Web bridge is unavailable: $loadError';

    return '$base$safariHint$locationSuffix';
  }

  String? _getGlobalString(String propertyName) {
    final raw = globalContext.getProperty(propertyName.toJS);
    if (raw.isA<JSString>()) {
      final value = (raw as JSString).toDart.trim();
      return value.isEmpty ? null : value;
    }

    final asText = raw.toString();
    if (asText == 'undefined' || asText == 'null' || asText.isEmpty) {
      return null;
    }

    return asText;
  }

  String? _getBridgeLoadError() {
    return _getGlobalString('__llamadartBridgeLoadError');
  }

  bool _getGlobalBool(String propertyName) {
    final raw = globalContext.getProperty(propertyName.toJS);
    if (raw.isA<JSBoolean>()) {
      return (raw as JSBoolean).toDart;
    }

    final text = raw.toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes' || text == 'on';
  }

  String? _getBridgeUserAgent() {
    final override = _getGlobalString('__llamadartBridgeUserAgent');
    if (override != null) {
      return override;
    }

    final navigator = globalContext.getProperty('navigator'.toJS);
    if (!navigator.isA<JSObject>()) {
      return null;
    }

    final userAgent = (navigator as JSObject).getProperty('userAgent'.toJS);
    if (userAgent.isA<JSString>()) {
      final value = (userAgent as JSString).toDart.trim();
      return value.isEmpty ? null : value;
    }

    final text = userAgent.toString();
    if (text == 'undefined' || text == 'null' || text.isEmpty) {
      return null;
    }

    return text;
  }

  bool _isSafariBrowser() {
    final userAgent = _getBridgeUserAgent();
    if (userAgent == null || userAgent.isEmpty) {
      return false;
    }

    final hasSafariToken = userAgent.contains('Safari/');
    final hasOtherBrowserToken =
        userAgent.contains('Chrome/') ||
        userAgent.contains('Chromium/') ||
        userAgent.contains('CriOS/') ||
        userAgent.contains('Edg/') ||
        userAgent.contains('OPR/') ||
        userAgent.contains('Firefox/') ||
        userAgent.contains('FxiOS/');

    return hasSafariToken && !hasOtherBrowserToken;
  }

  bool _allowSafariWebGpu() {
    return _getGlobalBool('__llamadartAllowSafariWebGpu');
  }

  bool _bridgeSupportsAdaptiveSafariGpu() {
    return _getGlobalBool('__llamadartBridgeAdaptiveSafariGpu');
  }

  String _errorText(Object error) {
    final values = <String>{error.toString()};

    JSObject? jsError;
    try {
      jsError = error as JSObject;
    } catch (_) {
      jsError = null;
    }

    if (jsError != null) {
      final nestedError = jsError.getProperty('error'.toJS);
      final nestedMessage = jsError.getProperty('message'.toJS);
      final nestedStack = jsError.getProperty('stack'.toJS);

      for (final candidate in <JSAny?>[
        nestedError,
        nestedMessage,
        nestedStack,
      ]) {
        if (candidate == null) {
          continue;
        }

        final text = candidate.toString();
        if (text == 'undefined' || text == 'null' || text.isEmpty) {
          continue;
        }

        values.add(text);
      }
    }

    return values.join(' | ');
  }

  UnsupportedError? _normalizeBridgeRuntimeError(Object error) {
    final text = _errorText(error);
    if (text.contains('JSPI not supported by current environment')) {
      final source = _getGlobalString('__llamadartBridgeAssetSource');
      final moduleUrl = _getGlobalString('__llamadartBridgeModuleUrl');

      final location = <String>[];
      if (source != null) {
        location.add('source=$source');
      }
      if (moduleUrl != null) {
        location.add('module=$moduleUrl');
      }

      final suffix = location.isEmpty ? '' : ' [${location.join(', ')}]';

      return UnsupportedError(
        'Bridge runtime requires JSPI, which is unavailable in this browser. '
        'Use browser-compatible bridge assets built without JSPI '
        '(Asyncify/wasm32), or enable JSPI experimental browser flags.$suffix',
      );
    }

    return null;
  }

  LlamaWebGpuBridge _requireBridge() {
    final bridge = _bridge;
    if (!_usingBridge || bridge == null) {
      throw StateError(
        'Web bridge is not active. Call loadModelFromUrl first.',
      );
    }
    return bridge;
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) {
    return modelLoadFromUrl(path, params);
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async {
    _lastNCtx = params.contextSize;

    final requestedThreads = params.numberOfThreads > 0
        ? params.numberOfThreads
        : null;
    var requestedGpuLayers = params.preferredBackend == GpuBackend.cpu
        ? 0
        : params.gpuLayers;

    if (requestedGpuLayers > 0 &&
        _isSafariBrowser() &&
        !_allowSafariWebGpu() &&
        !_bridgeSupportsAdaptiveSafariGpu()) {
      requestedGpuLayers = 0;
      console.warn(
        'WebGpuLlamaBackend: Safari WebGPU generation is unstable for legacy bridge assets; forcing CPU fallback. '
                'Use bridge assets with adaptive Safari GPU probe support, or set '
                'window.__llamadartAllowSafariWebGpu = true to bypass this safeguard.'
            .toJS,
      );
    }

    await _activateBridge();
    final bridge = _requireBridge();

    try {
      final loadPromise = bridge.loadModelFromUrl(
        url,
        WebGpuLoadModelOptions(
          nCtx: params.contextSize,
          nThreads: requestedThreads,
          nGpuLayers: requestedGpuLayers,
          useCache: true,
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
                        return;
                      }
                    }
                  }

                  if (p.isA<JSNumber>()) {
                    onProgress((p as JSNumber).toDartDouble);
                  }
                }.toJS,
        ),
      );

      if (loadPromise != null) {
        await loadPromise.toDart;
      }

      _isReady = true;
      _mmContextActive = false;
      return 1;
    } catch (e) {
      console.error('WebGpuLlamaBackend: Bridge model load failed: $e'.toJS);
      await _safeDisposeBridge();
      final normalized = _normalizeBridgeRuntimeError(e);
      if (normalized != null) {
        throw normalized;
      }
      rethrow;
    }
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    await _safeDisposeBridge();
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    _requireBridge();
    return 1;
  }

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<int> getContextSize(int contextHandle) async {
    final bridge = _requireBridge();
    try {
      final n = bridge.getContextSize();
      if (n != null && n > 0) {
        return n;
      }
    } catch (_) {
      // Fall through to requested context size.
    }
    return _lastNCtx ?? 0;
  }

  List<int> _pieceToBytes(JSAny? piece) {
    if (piece == null) {
      return const <int>[];
    }

    if (piece.isA<JSUint8Array>()) {
      return (piece as JSUint8Array).toDart;
    }

    if (piece.isA<JSArray>()) {
      final arr = piece as JSArray;
      final out = <int>[];
      for (int i = 0; i < arr.length; i++) {
        final item = arr.getProperty(i.toJS);
        if (item.isA<JSNumber>()) {
          out.add((item as JSNumber).toDartInt);
        }
      }
      return out;
    }

    return const <int>[];
  }

  JSArray? _buildMultimodalParts(List<LlamaContentPart>? parts) {
    if (parts == null || parts.isEmpty) {
      return null;
    }

    final jsParts = JSArray();
    var index = 0;

    for (final part in parts) {
      if (part is LlamaImageContent) {
        final jsPart = JSObject();
        jsPart.setProperty('type'.toJS, 'image'.toJS);

        if (part.bytes != null && part.bytes!.isNotEmpty) {
          jsPart.setProperty('bytes'.toJS, part.bytes!.toJS);
          if (part.width != null && part.width! > 0) {
            jsPart.setProperty('width'.toJS, part.width!.toJS);
          }
          if (part.height != null && part.height! > 0) {
            jsPart.setProperty('height'.toJS, part.height!.toJS);
          }
        } else {
          final url = part.url ?? part.path;
          if (url == null || url.isEmpty) {
            continue;
          }
          jsPart.setProperty('url'.toJS, url.toJS);
        }

        jsParts.setProperty(index.toJS, jsPart);
        index += 1;
        continue;
      }

      if (part is LlamaAudioContent) {
        final jsPart = JSObject();
        jsPart.setProperty('type'.toJS, 'audio'.toJS);

        if (part.samples != null && part.samples!.isNotEmpty) {
          jsPart.setProperty('samples'.toJS, part.samples!.toJS);
        } else if (part.bytes != null && part.bytes!.isNotEmpty) {
          jsPart.setProperty('bytes'.toJS, part.bytes!.toJS);
        } else {
          final url = part.path;
          if (url == null || url.isEmpty) {
            continue;
          }
          jsPart.setProperty('url'.toJS, url.toJS);
        }

        jsParts.setProperty(index.toJS, jsPart);
        index += 1;
      }
    }

    return index == 0 ? null : jsParts;
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    final mediaParts = _buildMultimodalParts(parts);
    if (mediaParts != null && !_mmContextActive) {
      throw StateError(
        'Multimodal input requires loadMultimodalProjector() before generate().',
      );
    }

    final bridge = _requireBridge();

    final controller = StreamController<List<int>>();
    _abortController = AbortController();
    var emittedLength = 0;

    final onToken = (JSAny? piece, JSAny? currentText) {
      if (currentText != null && currentText.isA<JSString>()) {
        final fullText = (currentText as JSString).toDart;
        if (fullText.length < emittedLength) {
          emittedLength = 0;
        }

        var stopIndex = -1;
        if (params.stopSequences.isNotEmpty) {
          for (final stop in params.stopSequences) {
            if (stop.isEmpty) {
              continue;
            }
            final idx = fullText.indexOf(stop);
            if (idx != -1 && (stopIndex == -1 || idx < stopIndex)) {
              stopIndex = idx;
            }
          }
        }

        if (stopIndex != -1) {
          if (stopIndex > emittedLength) {
            final delta = fullText.substring(emittedLength, stopIndex);
            if (delta.isNotEmpty) {
              controller.add(utf8.encode(delta));
            }
          }
          emittedLength = stopIndex;
          _abortController?.abort();
          return;
        }

        if (fullText.length > emittedLength) {
          final delta = fullText.substring(emittedLength);
          if (delta.isNotEmpty) {
            controller.add(utf8.encode(delta));
            emittedLength = fullText.length;
            return;
          }
        }
      }

      final bytes = _pieceToBytes(piece);
      if (bytes.isEmpty) {
        return;
      }

      controller.add(bytes);
    }.toJS;

    final options = WebGpuCompletionOptions(
      nPredict: params.maxTokens,
      temp: params.temp,
      topK: params.topK,
      topP: params.topP,
      penalty: params.penalty,
      seed: params.seed ?? DateTime.now().millisecondsSinceEpoch,
      grammar: params.grammar,
      onToken: onToken as JSFunction,
      parts: mediaParts,
      signal: _abortController?.signal,
    );

    final completion = bridge.createCompletion(prompt, options);
    _toFuture(completion).then(
      (_) => controller.close(),
      onError: (Object e, StackTrace st) {
        controller.addError(e, st);
      },
    );

    return controller.stream;
  }

  @override
  void cancelGeneration() {
    _abortController?.abort();
    _bridge?.cancel();
  }

  Future<JSAny?> _toFuture(JSAny? value) async {
    if (value == null) {
      return null;
    }

    if (value.isA<JSPromise>()) {
      return (value as JSPromise<JSAny?>).toDart;
    }

    return value;
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    final bridge = _requireBridge();
    final result = await _toFuture(bridge.tokenize(text, addSpecial));
    if (result == null) {
      return const <int>[];
    }

    if (result.isA<JSUint32Array>()) {
      return (result as JSUint32Array).toDart.cast<int>().toList();
    }

    if (result.isA<JSInt32Array>()) {
      return (result as JSInt32Array).toDart.cast<int>().toList();
    }

    if (result.isA<JSArray>()) {
      final arr = result as JSArray;
      final tokens = <int>[];
      for (int i = 0; i < arr.length; i++) {
        final value = arr.getProperty(i.toJS);
        if (value.isA<JSNumber>()) {
          tokens.add((value as JSNumber).toDartInt);
        }
      }
      return tokens;
    }

    return const <int>[];
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async {
    final bridge = _requireBridge();
    final jsTokens = tokens.map((t) => t.toJS).toList().toJS;
    final result = await _toFuture(bridge.detokenize(jsTokens, special));
    return (result as JSString?)?.toDart ?? '';
  }

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    final bridge = _requireBridge();
    final metadata = bridge.getModelMetadata();
    if (metadata == null) {
      return <String, String>{};
    }

    final out = <String, String>{};
    final keys = _objectKeys(metadata);
    for (int i = 0; i < keys.length; i++) {
      final key = (keys.getProperty(i.toJS) as JSString).toDart;
      final value = metadata.getProperty(key.toJS);
      if (value.isA<JSString>()) {
        out[key] = (value as JSString).toDart;
      } else if (value.isA<JSNumber>()) {
        out[key] = (value as JSNumber).toDartInt.toString();
      } else {
        out[key] = value.toString();
      }
    }
    return out;
  }

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async {}

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async {}

  @override
  Future<void> clearLoraAdapters(int contextHandle) async {}

  @override
  Future<String> getBackendName() async {
    if (_bridge != null) {
      final rawName = _bridge!.getBackendName();
      final name = rawName?.toDart;
      if (name != null && name.isNotEmpty) {
        return name;
      }
    }
    return _usingBridge ? 'WebGPU (Web)' : 'Web Bridge (not loaded)';
  }

  @override
  bool get supportsUrlLoading => true;

  @override
  Future<bool> isGpuSupported() async {
    if (_bridge == null) {
      return false;
    }
    final active = _bridge!.isGpuActive();
    if (active != null) {
      return active;
    }
    return false;
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) {
    _logLevel = level;
    _syncBridgeLogLevel();
    return Future<void>.value();
  }

  @override
  Future<void> dispose() async {
    await _safeDisposeBridge();
  }

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    final bridge = _requireBridge();
    final result = await _toFuture(bridge.loadMultimodalProjector(mmProjPath));
    if (result == null) {
      _mmContextActive = true;
      return 1;
    }

    if (result.isA<JSNumber>()) {
      _mmContextActive = true;
      return (result as JSNumber).toDartInt;
    }

    _mmContextActive = true;
    return 1;
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {
    final bridge = _bridge;
    if (bridge == null || !_mmContextActive) {
      return;
    }

    await _toFuture(bridge.unloadMultimodalProjector());
    _mmContextActive = false;
  }

  @override
  Future<bool> supportsVision(int mmContextHandle) async {
    if (!_mmContextActive) {
      return false;
    }

    final bridge = _bridge;
    if (bridge == null) {
      return false;
    }

    return bridge.supportsVision() ?? false;
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) async {
    if (!_mmContextActive) {
      return false;
    }

    final bridge = _bridge;
    if (bridge == null) {
      return false;
    }

    return bridge.supportsAudio() ?? false;
  }

  @override
  Future<({int total, int free})> getVramInfo() async => (total: 0, free: 0);

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async {
    if (!_usingBridge || _bridge == null) {
      final lines = messages
          .map(
            (msg) =>
                '${msg['role']?.toString() ?? 'user'}: ${msg['content']?.toString() ?? ''}',
          )
          .toList();
      if (addAssistant) {
        lines.add('assistant: ');
      }
      return lines.join('\n');
    }

    final bridge = _requireBridge();
    final jsMessages = JSArray();
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final jsMsg = JSObject();
      jsMsg.setProperty('role'.toJS, (msg['role']?.toString() ?? '').toJS);
      jsMsg.setProperty(
        'content'.toJS,
        (msg['content']?.toString() ?? '').toJS,
      );
      jsMessages.setProperty(i.toJS, jsMsg);
    }

    final result = bridge.applyChatTemplate(
      jsMessages,
      addAssistant,
      customTemplate,
    );
    if (result == null) {
      return '';
    }

    final jsValue = await result.toDart;
    return jsValue.toDart;
  }
}
