import 'package:llamadart/llamadart.dart';
import '../models.dart';

/// Service for interacting with the Llama engine in a CLI environment.
class LlamaCliService {
  final LlamaEngine _engine = LlamaEngine(NativeLlamaBackend());
  final List<CliMessage> _history = [];

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
    _history.add(CliMessage(text: text, role: CliRole.user));

    final messages = _getChatHistory();
    String response = "";

    await for (final token in _engine.chat(messages)) {
      response += token;
    }

    final cleanResponse = response.trim();
    _history.add(CliMessage(text: cleanResponse, role: CliRole.assistant));
    return cleanResponse;
  }

  /// Sends a message and returns a stream of tokens.
  Stream<String> chatStream(String text) async* {
    _history.add(CliMessage(text: text, role: CliRole.user));

    final messages = _getChatHistory();

    await for (final token in _engine.chat(messages)) {
      yield token;
    }

    // Note: In a real app we'd need to collect and save the full response to history here too.
  }

  List<LlamaChatMessage> _getChatHistory() {
    return _history
        .map((m) => LlamaChatMessage(
              role: m.role == CliRole.user ? 'user' : 'assistant',
              content: m.text,
            ))
        .toList();
  }

  /// Disposes the underlying engine resources.
  Future<void> dispose() async {
    await _engine.dispose();
  }
}
