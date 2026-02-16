import 'package:llamadart/llamadart.dart';

import '../domain/api_server_engine.dart';

/// Adapter that delegates to a real [LlamaEngine].
class LlamaApiServerEngine implements ApiServerEngine {
  /// Wrapped engine instance.
  final LlamaEngine engine;

  /// Creates an adapter around [engine].
  LlamaApiServerEngine(this.engine);

  @override
  bool get isReady => engine.isReady;

  @override
  Future<LlamaChatTemplateResult> chatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
  }) {
    return engine.chatTemplate(
      messages,
      addAssistant: addAssistant,
      tools: tools,
      toolChoice: toolChoice,
    );
  }

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams params = const GenerationParams(),
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
  }) {
    return engine.create(
      messages,
      params: params,
      tools: tools,
      toolChoice: toolChoice,
    );
  }

  @override
  Future<int> getTokenCount(String text) {
    return engine.getTokenCount(text);
  }

  @override
  void cancelGeneration() {
    engine.cancelGeneration();
  }
}
