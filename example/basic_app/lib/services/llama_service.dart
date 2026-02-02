import 'package:llamadart/llamadart.dart';

/// Service for interacting with the Llama engine in a CLI environment.
class LlamaCliService {
  final LlamaEngine _engine = LlamaEngine(LlamaBackend());
  late final ChatSession _session;

  /// Creates a new [LlamaCliService].
  LlamaCliService() {
    _session = ChatSession(_engine);
  }

  /// Initializes the engine with the given [modelPath].
  Future<void> init(
    String modelPath, {
    List<LoraAdapterConfig> loras = const [],
    LlamaLogLevel logLevel = LlamaLogLevel.none,
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
  }

  /// Sends a message and returns the full response.
  Future<String> chat(String text) async {
    return _session.chatText(text);
  }

  /// Sends a message and returns a stream of tokens.
  Stream<String> chatStream(String text) {
    return _session.chat(text);
  }

  /// Disposes the underlying engine resources.
  Future<void> dispose() async {
    await _engine.dispose();
  }
}
