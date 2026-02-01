import 'dart:async';
import 'dart:isolate';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../llama_backend_interface.dart';
import '../../models/llama_content_part.dart';
import '../../models/llama_log_level.dart';
import '../../models/model_params.dart';
import '../../models/generation_params.dart';
import '../../models/llama_chat_message.dart';
import '../../models/llama_chat_template_result.dart';
import 'worker.dart';

/// Creates a [NativeLlamaBackend].
LlamaBackend createBackend() => NativeLlamaBackend();

/// Native implementation of [LlamaBackend] using isolates and FFI.
class NativeLlamaBackend implements LlamaBackend {
  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _responsesPort = ReceivePort();
  final ReceivePort _logPort = ReceivePort();
  final StreamController<LogResponse> _logController =
      StreamController.broadcast();
  Pointer<Int8>? _cancelToken;

  bool _isReady = false;
  LlamaLogLevel _currentLogLevel = LlamaLogLevel.warn;

  /// Creates a new [NativeLlamaBackend] and initializes its ports.
  NativeLlamaBackend() {
    _responsesPort.listen(_handleResponse);
    _logPort.listen(_handleLog);
  }

  @override
  bool get isReady => _isReady;

  void _handleLog(dynamic message) {
    // Note: Native logs go to stderr, not through this port.
    // This handler exists for future use or if we implement a different
    // logging mechanism. The logStream still works for web backend.
    if (message is LogResponse) {
      _logController.add(message);
    }
  }

  void _handleResponse(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      // Complete handshake
      _sendPort!.send(WorkerHandshake(_logPort.sendPort));
      // Sync log level
      _sendPort!.send(
        LogLevelRequest(_currentLogLevel, ReceivePort().sendPort),
      );
    }
  }

  Future<void> _ensureIsolate() async {
    if (_isolate != null && _sendPort != null) return;
    final completer = Completer<void>();
    final tempPort = ReceivePort();
    tempPort.listen((msg) {
      if (msg is SendPort) {
        _sendPort = msg;
        _sendPort!.send(WorkerHandshake(_logPort.sendPort));
        tempPort.close();
        completer.complete();
      }
    });
    _isolate = await Isolate.spawn(llamaWorkerEntry, tempPort.sendPort);
    await completer.future;
    _isReady = true;
  }

  @override
  void cancelGeneration() {
    _cancelToken?.value = 1;
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    _currentLogLevel = level;
    if (_sendPort != null) {
      final rp = ReceivePort();
      _sendPort!.send(LogLevelRequest(level, rp.sendPort));
      await rp.first;
      rp.close();
    }
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    _currentLogLevel = params.logLevel;
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(ModelLoadRequest(path, params, rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is HandleResponse) return res.handle;
    if (res is ErrorResponse) throw Exception(res.message);
    throw Exception("Unknown response during model load");
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async {
    throw UnimplementedError("Use modelLoad with a local path for now");
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    if (_sendPort == null) return;
    final rp = ReceivePort();
    _sendPort!.send(ModelFreeRequest(modelHandle, rp.sendPort));
    await rp.first;
    rp.close();
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    _currentLogLevel = params.logLevel;
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(ContextCreateRequest(modelHandle, params, rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is HandleResponse) return res.handle;
    if (res is ErrorResponse) throw Exception(res.message);
    throw Exception("Unknown response during context creation");
  }

  @override
  Future<void> contextFree(int contextHandle) async {
    if (_sendPort == null) return;
    final rp = ReceivePort();
    _sendPort!.send(ContextFreeRequest(contextHandle, rp.sendPort));
    await rp.first;
    rp.close();
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    final controller = StreamController<List<int>>();
    final rp = ReceivePort();

    _cancelToken?.value = 1;
    if (_cancelToken != null) malloc.free(_cancelToken!);
    _cancelToken = malloc<Int8>(1);
    _cancelToken!.value = 0;

    _sendPort!.send(
      GenerateRequest(
        contextHandle,
        prompt,
        params,
        _cancelToken!.address,
        rp.sendPort,
        parts: parts,
      ),
    );

    rp.listen((msg) {
      if (msg is TokenResponse) {
        controller.add(msg.bytes);
      } else if (msg is DoneResponse) {
        controller.close();
        rp.close();
      } else if (msg is ErrorResponse) {
        controller.addError(Exception(msg.message));
        controller.close();
        rp.close();
      }
    });

    return controller.stream;
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    final rp = ReceivePort();
    _sendPort!.send(
      TokenizeRequest(modelHandle, text, addSpecial, rp.sendPort),
    );
    final res = await rp.first;
    rp.close();
    if (res is TokenizeResponse) return res.tokens;
    throw Exception("Tokenization failed");
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async {
    final rp = ReceivePort();
    _sendPort!.send(
      DetokenizeRequest(modelHandle, tokens, special, rp.sendPort),
    );
    final res = await rp.first;
    rp.close();
    if (res is DetokenizeResponse) return res.text;
    throw Exception("Detokenization failed");
  }

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    final rp = ReceivePort();
    _sendPort!.send(MetadataRequest(modelHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is MetadataResponse) return res.metadata;
    return {};
  }

  @override
  Future<LlamaChatTemplateResult> applyChatTemplate(
    int modelHandle,
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
  }) async {
    final rp = ReceivePort();
    _sendPort!.send(
      ApplyTemplateRequest(modelHandle, messages, addAssistant, rp.sendPort),
    );
    final res = await rp.first;
    rp.close();
    if (res is ApplyTemplateResponse) {
      return LlamaChatTemplateResult(
        prompt: res.prompt,
        stopSequences: res.stopSequences,
      );
    }
    throw Exception("Failed to apply chat template");
  }

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async {
    final rp = ReceivePort();
    _sendPort!.send(
      LoraRequest(
        contextHandle,
        'set',
        path: path,
        scale: scale,
        sendPort: rp.sendPort,
      ),
    );
    final res = await rp.first;
    rp.close();
    if (res is ErrorResponse) throw Exception(res.message);
  }

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async {
    final rp = ReceivePort();
    _sendPort!.send(
      LoraRequest(contextHandle, 'remove', path: path, sendPort: rp.sendPort),
    );
    final res = await rp.first;
    rp.close();
    if (res is ErrorResponse) throw Exception(res.message);
  }

  @override
  Future<void> clearLoraAdapters(int contextHandle) async {
    final rp = ReceivePort();
    _sendPort!.send(LoraRequest(contextHandle, 'clear', sendPort: rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is ErrorResponse) throw Exception(res.message);
  }

  @override
  Future<String> getBackendName() async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(BackendInfoRequest(rp.sendPort));
    final res = await rp.first;
    rp.close();
    return (res as BackendInfoResponse).name;
  }

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<bool> isGpuSupported() async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(GpuSupportRequest(rp.sendPort));
    final res = await rp.first;
    rp.close();
    return (res as GpuSupportResponse).support;
  }

  @override
  Future<void> dispose() async {
    if (_sendPort != null) {
      final rp = ReceivePort();
      _sendPort!.send(DisposeRequest(rp.sendPort));
      await rp.first;
      rp.close();
    }
    _isolate?.kill();
    _responsesPort.close();
    _logPort.close();
    if (_cancelToken != null) {
      malloc.free(_cancelToken!);
      _cancelToken = null;
    }
    _isReady = false;
  }

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    final rp = ReceivePort();
    _sendPort!.send(
      MultimodalContextCreateRequest(modelHandle, mmProjPath, rp.sendPort),
    );
    final res = await rp.first;
    rp.close();
    if (res is HandleResponse) return res.handle;
    if (res is ErrorResponse) throw Exception(res.message);
    return null;
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {
    final rp = ReceivePort();
    _sendPort!.send(MultimodalContextFreeRequest(mmContextHandle, rp.sendPort));
    await rp.first;
    rp.close();
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) async {
    final rp = ReceivePort();
    _sendPort!.send(SupportsAudioRequest(mmContextHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    return res as bool;
  }

  @override
  Future<bool> supportsVision(int mmContextHandle) async {
    final rp = ReceivePort();
    _sendPort!.send(SupportsVisionRequest(mmContextHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    return res as bool;
  }
}
