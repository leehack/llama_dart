import 'package:llamadart/llamadart.dart';

/// Engine contract used by the OpenAI example server.
abstract class ApiServerEngine {
  /// Whether the engine is loaded and ready.
  bool get isReady;

  /// Applies the chat template and returns template metadata.
  Future<LlamaChatTemplateResult> chatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistant,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice,
  });

  /// Starts streaming generation.
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
  });

  /// Computes token count for a text payload.
  Future<int> getTokenCount(String text);

  /// Cancels active generation.
  void cancelGeneration();
}

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
