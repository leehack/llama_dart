import 'dart:convert';

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
    // Set log level
    await _engine.setLogLevel(logLevel);

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

    // Create session with system prompt for tool calling if tools are provided
    _session = ChatSession(
      _engine,
      systemPrompt: tools != null && tools.isNotEmpty
          ? 'You are a helpful assistant. When you need to use a tool, output it in the correct format as specified by the model template.'
          : null,
    );
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
  ///
  /// This method handles tool calls automatically:
  /// 1. Generates response with potential tool calls
  /// 2. Executes any tool calls
  /// 3. Continues generation with tool results
  Stream<String> chatStream(
    String text, {
    GenerationParams? params,
    ToolChoice? toolChoice,
  }) async* {
    // Generate initial response
    final chunks = await _session.create(
      [LlamaTextContent(text)],
      params: params,
      tools: _tools,
      toolChoice: toolChoice,
    ).toList();

    // Extract content and tool calls from chunks
    final content =
        chunks.map((chunk) => chunk.choices.first.delta.content ?? '').join();

    final toolCalls = chunks
        .expand((chunk) => chunk.choices.first.delta.toolCalls ?? [])
        .toList();

    // Yield initial content
    if (content.isNotEmpty) {
      yield content;
    }

    // If no tool calls, we're done
    if (toolCalls.isEmpty || _tools == null || _tools!.isEmpty) {
      return;
    }

    // Execute tool calls
    for (final call in toolCalls) {
      final functionName = call.function?.name;
      if (functionName == null) continue;

      // Find the tool
      final tool = _tools!.firstWhere(
        (t) => t.name == functionName,
        orElse: () => throw Exception('Tool not found: $functionName'),
      );

      // Parse arguments
      final argsJson = call.function?.arguments ?? '{}';
      final args = jsonDecode(argsJson) as Map<String, dynamic>;

      // Execute tool
      yield '\n🔧 Executing: $functionName(${args.entries.map((e) => '${e.key}: ${e.value}').join(', ')})\n';
      final result = await tool.invoke(args);
      yield '📋 Result: $result\n';

      // Add tool result to session
      _session.addMessage(
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [
            LlamaToolResultContent(
              id: call.id,
              name: functionName,
              result: result,
            ),
          ],
        ),
      );
    }

    // Continue generation with tool results
    yield '\n💬 Final response:\n';
    final finalChunks = _session.create(
      [], // Empty parts - continue from current context
      params: params,
    ).map((chunk) => chunk.choices.first.delta.content ?? '');

    await for (final token in finalChunks) {
      yield token;
    }
  }

  /// Disposes the underlying engine resources.
  Future<void> dispose() async {
    await _engine.dispose();
  }
}
