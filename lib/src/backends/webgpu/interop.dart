@JS()
library;

import 'dart:js_interop';

/// JS bridge constructor for llama.cpp WebGPU runtime.
@JS('LlamaWebGpuBridge')
extension type LlamaWebGpuBridge._(JSObject _) implements JSObject {
  /// Creates a bridge instance.
  external factory LlamaWebGpuBridge([WebGpuBridgeConfig? config]);

  /// Loads a GGUF model from a URL.
  external JSPromise<JSAny?>? loadModelFromUrl(
    String url, [
    WebGpuLoadModelOptions? options,
  ]);

  /// Generates completion output for a prompt.
  external JSPromise<JSAny?>? createCompletion(
    String prompt, [
    WebGpuCompletionOptions? options,
  ]);

  /// Loads multimodal projector from URL/path.
  external JSPromise<JSAny?>? loadMultimodalProjector(String url);

  /// Unloads multimodal projector if loaded.
  external JSPromise<JSAny?>? unloadMultimodalProjector();

  /// Returns whether loaded projector supports vision.
  external bool? supportsVision();

  /// Returns whether loaded projector supports audio.
  external bool? supportsAudio();

  /// Tokenizes text.
  external JSPromise<JSAny>? tokenize(String text, [bool? addSpecial]);

  /// Detokenizes token ids.
  external JSPromise<JSString>? detokenize(JSArray tokens, [bool? special]);

  /// Returns model metadata as a plain JS object.
  external JSObject? getModelMetadata();

  /// Returns current context size if available.
  external int? getContextSize();

  /// Returns true when GPU compute is active.
  external bool? isGpuActive();

  /// Returns a backend display name.
  external JSString? getBackendName();

  /// Updates runtime log level in the underlying core.
  external JSAny? setLogLevel(int level);

  /// Cancels active generation.
  external JSAny? cancel();

  /// Disposes runtime resources.
  external JSPromise<JSAny?>? dispose();

  /// Applies chat template.
  external JSPromise<JSString>? applyChatTemplate(
    JSArray messages,
    bool addAssistant, [
    String? customTemplate,
  ]);
}

/// Bridge construction config.
@JS()
@anonymous
extension type WebGpuBridgeConfig._(JSObject _) implements JSObject {
  /// Creates a config object for the JS bridge.
  external factory WebGpuBridgeConfig({
    JSString? wasmUrl,
    JSString? workerUrl,
    @JS('coreModuleUrl') JSString? coreModuleUrl,
    int? logLevel,
    JSObject? logger,
  });
}

/// Model loading options.
@JS()
@anonymous
extension type WebGpuLoadModelOptions._(JSObject _) implements JSObject {
  /// Creates model loading options.
  external factory WebGpuLoadModelOptions({
    @JS('nCtx') int? nCtx,
    @JS('nThreads') int? nThreads,
    @JS('nGpuLayers') int? nGpuLayers,
    @JS('useCache') bool? useCache,
    @JS('progressCallback') JSFunction? progressCallback,
  });
}

/// Completion options.
@JS()
@anonymous
extension type WebGpuCompletionOptions._(JSObject _) implements JSObject {
  /// Creates completion options.
  external factory WebGpuCompletionOptions({
    @JS('nPredict') int? nPredict,
    double? temp,
    @JS('topK') int? topK,
    @JS('topP') double? topP,
    double? penalty,
    int? seed,
    String? grammar,
    @JS('onToken') JSFunction? onToken,
    JSArray? parts,
    JSAny? signal,
  });
}
