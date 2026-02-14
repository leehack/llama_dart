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

  /// Maximum number of consecutive tool-call rounds to prevent infinite loops.
  static const int _maxToolRounds = 10;

  /// Sends a message and returns a stream of tokens.
  ///
  /// This method handles tool calls automatically:
  /// 1. Streams tokens while collecting tool calls in parallel
  /// 2. Executes any tool calls and feeds results back
  /// 3. Repeats until no more tool calls or [_maxToolRounds] is reached
  Stream<String> chatStream(
    String text, {
    GenerationParams? params,
    ToolChoice? toolChoice,
  }) async* {
    // First turn: send the user message
    var parts = <LlamaContentPart>[LlamaTextContent(text)];
    var isFirstTurn = true;

    for (var round = 0; round < _maxToolRounds; round++) {
      // Stream tokens and collect tool calls in parallel
      final toolCalls = <LlamaCompletionChunkToolCall>[];
      await for (final chunk in _session.create(
        isFirstTurn ? parts : [],
        params: params,
        tools: _tools,
        toolChoice: isFirstTurn ? toolChoice : null,
      )) {
        final content = chunk.choices.first.delta.content ?? '';
        if (content.isNotEmpty) yield content;
        toolCalls.addAll(chunk.choices.first.delta.toolCalls ?? []);
      }
      isFirstTurn = false;

      // No tool calls means generation is complete
      if (toolCalls.isEmpty || _tools == null || _tools!.isEmpty) {
        return;
      }

      // Execute each tool call and add results to the session
      for (final call in toolCalls) {
        final functionName = call.function?.name;
        if (functionName == null) continue;

        final tool = _tools!.firstWhere(
          (t) => t.name == functionName,
          orElse: () => throw Exception('Tool not found: $functionName'),
        );

        final argsJson = call.function?.arguments ?? '{}';
        final args = jsonDecode(argsJson) as Map<String, dynamic>;

        yield '\n[tool] $functionName(${args.entries.map((e) => '${e.key}: ${e.value}').join(', ')})\n';
        final result = await tool.invoke(args);
        yield '[result] $result\n';

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
    }
  }

  /// Disposes the underlying engine resources.
  Future<void> dispose() async {
    await _engine.dispose();
  }
}
