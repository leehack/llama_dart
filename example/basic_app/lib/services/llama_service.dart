import 'package:llamadart/llamadart.dart';

/// Service for interacting with the Llama engine in a CLI environment.
class LlamaCliService {
  final LlamaEngine _engine = LlamaEngine(LlamaBackend());
  late ChatSession _session;
  List<ToolDefinition>? _tools;

  /// Creates a new [LlamaCliService].
  LlamaCliService() {
    _session = ChatSession(_engine);
  }

  /// Initializes the engine with the given [modelPath].
  ///
  /// Optionally provide [tools] to enable tool calling for this session.
  Future<void> init(
    String modelPath, {
    List<LoraAdapterConfig> loras = const [],
    LlamaLogLevel logLevel = LlamaLogLevel.none,
    List<ToolDefinition>? tools,
  }) async {
    await _engine.loadModel(
      modelPath,
      modelParams: ModelParams(
        gpuLayers: 99,
      ),
    );

    // Load LoRAs if any
    for (final lora in loras) {
      await _engine.setLora(lora.path, scale: lora.scale);
    }

    // Store tools for later use
    _tools = tools;
    _session = ChatSession(_engine);
  }

  /// Sets or updates the tools for this session.
  set tools(List<ToolDefinition>? tools) {
    _tools = tools;
  }

  /// Sends a message and returns the full response.
  Future<String> chat(
    String text, {
    GenerationParams? params,
  }) async {
    return _session
        .create(
          [LlamaTextContent(text)],
          params: params,
          tools: _tools,
        )
        .map((chunk) => chunk.choices.first.delta.content ?? '')
        .join();
  }

  /// Sends a message and returns a stream of tokens.
  Stream<String> chatStream(
    String text, {
    GenerationParams? params,
  }) {
    return _session.create(
      [LlamaTextContent(text)],
      params: params,
      tools: _tools,
    ).map((chunk) => chunk.choices.first.delta.content ?? '');
  }

  /// Disposes the underlying engine resources.
  Future<void> dispose() async {
    await _engine.dispose();
  }
}
