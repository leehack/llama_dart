import 'package:llamadart/llamadart.dart';

/// Service for interacting with the Llama engine in a CLI environment.
class LlamaCliService {
  final LlamaEngine _engine = LlamaEngine(LlamaBackend());
  late ChatSession _session;

  /// Creates a new [LlamaCliService].
  LlamaCliService() {
    _session = ChatSession(_engine);
  }

  /// Initializes the engine with the given [modelPath].
  ///
  /// Optionally provide [toolRegistry] to enable tool calling for this session.
  Future<void> init(
    String modelPath, {
    List<LoraAdapterConfig> loras = const [],
    LlamaLogLevel logLevel = LlamaLogLevel.none,
    ToolRegistry? toolRegistry,
  }) async {
    await _engine.loadModel(
      modelPath,
      modelParams: ModelParams(
        gpuLayers: 99,
        logLevel: logLevel,
      ),
    );

    // Load LoRAs if any
    for (final lora in loras) {
      await _engine.setLora(lora.path, scale: lora.scale);
    }

    // Set up session with tool registry if provided
    _session = ChatSession(_engine, toolRegistry: toolRegistry);
  }

  /// Sets or updates the tool registry for this session.
  set toolRegistry(ToolRegistry? registry) {
    _session.toolRegistry = registry;
  }

  /// Sends a message and returns the full response.
  Future<String> chat(
    String text, {
    GenerationParams? params,
  }) async {
    return _session.chatText(text, params: params);
  }

  /// Sends a message and returns a stream of tokens.
  Stream<String> chatStream(
    String text, {
    GenerationParams? params,
  }) {
    return _session.chat(text, params: params);
  }

  /// Disposes the underlying engine resources.
  Future<void> dispose() async {
    await _engine.dispose();
  }
}
