import 'dart:async';
import 'dart:convert';
import 'llama_engine.dart';
import '../models/llama_chat_message.dart';
import '../models/llama_chat_role.dart';
import '../models/llama_content_part.dart';
import '../models/generation_params.dart';
import '../tools/tool_registry.dart';
import '../common/json_schema_to_gbnf.dart';

/// High-level chat interface with history management and tool support.
///
/// [ChatSession] provides a stateful interface over [LlamaEngine], handling
/// conversation history and automatically ensuring that the total token count
/// stays within the model's context window limits by truncating older messages.
///
/// For stateless single-turn chat, use the static [singleTurn] method.
///
/// Example:
/// ```dart
/// final engine = LlamaEngine(LlamaBackend());
/// await engine.loadModel('model.gguf');
///
/// final session = ChatSession(engine);
/// session.systemPrompt = 'You are a helpful assistant.';
///
/// await for (final token in session.chat('Hello!')) {
///   print(token);
/// }
/// ```
class ChatSession {
  final LlamaEngine _engine;
  final List<LlamaChatMessage> _history = [];

  /// The maximum number of tokens allowed in the context window.
  ///
  /// If null, this value will be automatically retrieved from the engine's
  /// model metadata (e.g., `llama.context_length` or `n_ctx`).
  int? maxContextTokens;

  /// Creates a new [ChatSession] wrapping the given [engine].
  ///
  /// Optionally sets [maxContextTokens] to override the model's default limit,
  /// [systemPrompt] to define the initial persona or instructions, and
  /// [toolRegistry] to enable tool calling for this session.
  ChatSession(
    this._engine, {
    this.maxContextTokens,
    this.systemPrompt,
    this.toolRegistry,
    this.forceToolCall = false,
    this.toolsEnabled = true,
  });

  /// The underlying engine instance.
  LlamaEngine get engine => _engine;

  /// The current message history, excluding the [systemPrompt].
  ///
  /// Returns an unmodifiable list of [LlamaChatMessage].
  List<LlamaChatMessage> get history => List.unmodifiable(_history);

  /// The system prompt for this session.
  ///
  /// If set, this prompt is automatically prepended to the message list
  /// during every [chat] request. It persists until manually changed or
  /// cleared via [reset].
  String? systemPrompt;

  /// The tool registry for this session.
  ///
  /// If set, the model will have access to these tools for function calling.
  /// See [forceToolCall] to control whether tools are mandatory.
  ToolRegistry? toolRegistry;

  /// Whether to force the model to make a tool call.
  ///
  /// - `false` (default): Model decides when to use tools based on context.
  /// - `true`: Grammar constraints force the model to output a tool call.
  ///
  /// Set to `true` for weaker models that don't reliably call tools on their own.
  bool forceToolCall = false;

  /// Whether tools are currently enabled for this session.
  ///
  /// Defaults to `true`. If `false`, tools will not be used even if [toolRegistry] is set.
  bool toolsEnabled = true;

  /// Adds a custom [message] directly to the history.
  ///
  /// Useful for pre-seeding a conversation or restoring a previous state.
  void addMessage(LlamaChatMessage message) {
    _history.add(message);
  }

  /// Clears all messages from the conversation history.
  ///
  /// Note: This does not affect the [systemPrompt]. Use [reset] for a full cleanup.
  void clearHistory() {
    _history.clear();
  }

  /// Resets the session state.
  ///
  /// By default, [keepSystemPrompt] is true, meaning only the message history
  /// is cleared. Set [keepSystemPrompt] to false to also clear the [systemPrompt].
  /// Set [keepToolRegistry] to false to also clear the [toolRegistry].
  void reset({bool keepSystemPrompt = true, bool keepToolRegistry = true}) {
    _history.clear();
    if (!keepSystemPrompt) {
      systemPrompt = null;
    }
    if (!keepToolRegistry) {
      toolRegistry = null;
    }
  }

  /// Sends a user [text] message and returns a stream of generated response tokens.
  ///
  /// This method performs the following steps:
  /// 1. Adds the user message to the internal history.
  /// 2. Enforces the context limit by truncating older messages if necessary.
  /// 3. Formats the full message list (including [systemPrompt]) using the model's template.
  /// 4. Streams the response from the [LlamaEngine].
  /// 5. Appends the full assistant response back into the history.
  ///
  /// Uses the session's [toolRegistry] for tool calling. Pass a different
  /// registry via the parameter to override for this call only.
  Stream<String> chat(
    String text, {
    GenerationParams? params,
    ToolRegistry? toolRegistryOverride,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) async* {
    final userMsg = LlamaChatMessage.text(
      role: LlamaChatRole.user,
      content: text,
    );
    _history.add(userMsg);
    onMessageAdded?.call(userMsg);

    // Ensure we are within context limits before sending
    await _enforceContextLimit();

    final messages = _getMessagesForEngine();
    String fullResponse = "";

    await for (final token in _generateWithMessages(
      messages,
      params: params,
      toolRegistry: toolRegistryOverride ?? toolRegistry,
      forceToolCall: forceToolCall,
      toolsEnabled: toolsEnabled,
      onMessageAdded: onMessageAdded,
    )) {
      fullResponse += token;
      yield token;
    }

    final assistantMsg = LlamaChatMessage.text(
      role: LlamaChatRole.assistant,
      content: fullResponse.trim(),
    );
    _history.add(assistantMsg);
    onMessageAdded?.call(assistantMsg);
  }

  /// Sends a user [text] message and returns the full response string.
  ///
  /// Wraps [chat] but waits for the entire generation to complete and
  /// returns the concatenated tokens as a single trimmed string.
  Future<String> chatText(
    String text, {
    GenerationParams? params,
    ToolRegistry? toolRegistryOverride,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) async {
    final buffer = StringBuffer();
    await for (final token in chat(
      text,
      params: params,
      toolRegistryOverride: toolRegistryOverride,
      onMessageAdded: onMessageAdded,
    )) {
      buffer.write(token);
    }
    return buffer.toString().trim();
  }

  /// Stateless single-turn chat. Does not track history.
  ///
  /// Useful for one-off requests where you don't need conversation context.
  ///
  /// Example:
  /// ```dart
  /// final response = await ChatSession.singleTurn(
  ///   engine,
  ///   [LlamaChatMessage.text(role: LlamaChatRole.user, content: 'Hello!')],
  /// );
  /// print(response);
  /// ```
  static Future<String> singleTurn(
    LlamaEngine engine,
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    ToolRegistry? toolRegistry,
    bool forceToolCall = false,
    bool toolsEnabled = true,
  }) async {
    final buffer = StringBuffer();
    await for (final token in singleTurnStream(
      engine,
      messages,
      params: params,
      toolRegistry: toolRegistry,
      forceToolCall: forceToolCall,
      toolsEnabled: toolsEnabled,
    )) {
      buffer.write(token);
    }
    return buffer.toString().trim();
  }

  /// Stateless single-turn chat as a stream. Does not track history.
  ///
  /// Useful for one-off requests where you don't need conversation context
  /// but want streaming output.
  static Stream<String> singleTurnStream(
    LlamaEngine engine,
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    ToolRegistry? toolRegistry,
    bool forceToolCall = false,
    bool toolsEnabled = true,
  }) {
    // Create a temporary session just for processing
    final tempSession = ChatSession(engine);
    return tempSession._generateWithMessages(
      messages,
      params: params,
      toolRegistry: toolRegistry,
      forceToolCall: forceToolCall,
      toolsEnabled: toolsEnabled,
    );
  }

  /// Internal: generates a response from a list of messages.
  ///
  /// This handles both regular chat and tool-augmented chat.
  Stream<String> _generateWithMessages(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    ToolRegistry? toolRegistry,
    int maxToolCalls = 5,
    bool forceToolCall = false,
    bool toolsEnabled = true,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) async* {
    // Process multimodal content - ensure media markers are present
    final processedMessages = _processMultimodalMessages(messages);

    // If tools are provided and not empty, use tool-augmented generation
    if (toolsEnabled && toolRegistry != null && toolRegistry.isNotEmpty) {
      yield* _generateWithTools(
        processedMessages,
        toolRegistry,
        params: params,
        maxToolCalls: maxToolCalls,
        forceToolCall: forceToolCall,
        onMessageAdded: onMessageAdded,
      );
      return;
    }

    // Standard generation without tools
    final result = await _engine.chatTemplate(processedMessages);
    final stops = {...result.stopSequences, ...?params?.stopSequences}.toList();

    // Collect all parts from all messages
    final allParts = processedMessages.expand((m) => m.parts).toList();

    yield* _engine.generate(
      result.prompt,
      params: (params ?? const GenerationParams()).copyWith(
        stopSequences: stops,
      ),
      parts: allParts,
    );
  }

  /// Internal: handles tool-augmented generation.
  ///
  /// When [forceToolCall] is true, uses grammar constraints to ensure tool output.
  /// When false (default), model decides whether to call tools or respond directly.
  Stream<String> _generateWithTools(
    List<LlamaChatMessage> messages,
    ToolRegistry registry, {
    GenerationParams? params,
    int maxToolCalls = 5,
    bool forceToolCall = false,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) async* {
    var currentMessages = List<LlamaChatMessage>.from(messages);
    var toolCallCount = 0;

    // Add system prompt with tool descriptions
    final toolSystemPrompt = registry.generateSystemPrompt();
    currentMessages.insert(
      0,
      LlamaChatMessage.text(
        role: LlamaChatRole.system,
        content: toolSystemPrompt,
      ),
    );

    // Prepare grammar for forced mode
    String? grammar;
    if (forceToolCall) {
      grammar = JsonSchemaToGbnf.generateToolGrammar(
        registry.toJsonSchemaList(),
      );
    }

    while (toolCallCount < maxToolCalls) {
      final buffer = StringBuffer();
      final result = await _engine.chatTemplate(currentMessages);

      // Use grammar only if forcing tool calls AND we haven't called any tools yet
      final useGrammar = forceToolCall && toolCallCount == 0;
      final genParams = (params ?? const GenerationParams()).copyWith(
        grammar: useGrammar ? grammar : null,
        stopSequences: result.stopSequences,
      );

      final allParts = currentMessages.expand((m) => m.parts).toList();

      await for (final token in _engine.generate(
        result.prompt,
        params: genParams,
        parts: allParts,
      )) {
        buffer.write(token);
      }

      final response = buffer.toString().trim();

      // Try to parse as tool call
      if (_isToolCall(response)) {
        try {
          final json = jsonDecode(response) as Map<String, dynamic>;
          final function = json['function'] as Map<String, dynamic>;
          final name = function['name'] as String;
          final args =
              (function['parameters'] as Map?)?.cast<String, dynamic>() ?? {};

          // Invoke the tool
          final toolResult = await registry.invoke(name, args);
          toolCallCount++;

          // Create assistant message with tool call part
          final toolCallMsg = LlamaChatMessage.multimodal(
            role: LlamaChatRole.assistant,
            parts: [
              LlamaToolCallContent(
                name: name,
                arguments: args,
                rawJson: response,
              ),
            ],
          );
          currentMessages.add(toolCallMsg);
          _history.add(toolCallMsg);
          onMessageAdded?.call(toolCallMsg);

          // Create tool message with result part
          final toolResultMsg = LlamaChatMessage.multimodal(
            role: LlamaChatRole.tool,
            parts: [LlamaToolResultContent(name: name, result: toolResult)],
          );
          currentMessages.add(toolResultMsg);
          _history.add(toolResultMsg);
          onMessageAdded?.call(toolResultMsg);

          // Generate final response WITHOUT grammar (let model respond naturally)
          final finalResult = await _engine.chatTemplate(currentMessages);
          final finalParams = (params ?? const GenerationParams()).copyWith(
            stopSequences: finalResult.stopSequences,
          );

          final finalParts = currentMessages.expand((m) => m.parts).toList();
          yield* _engine.generate(
            finalResult.prompt,
            params: finalParams,
            parts: finalParts,
          );
          return;
        } catch (e) {
          // Parse failed - treat as normal response
        }
      }

      // Not a tool call, yield as final response
      yield response;
      return;
    }

    // Max tool calls reached, do one final generation without tools
    final finalResult = await _engine.chatTemplate(currentMessages);
    final finalParams = params ?? const GenerationParams();
    yield* _engine.generate(
      finalResult.prompt,
      params: finalParams.copyWith(stopSequences: finalResult.stopSequences),
    );
  }

  /// Check if a response looks like a tool call.
  bool _isToolCall(String response) {
    final trimmed = response.trim();
    if (!trimmed.startsWith('{')) return false;

    try {
      final json = jsonDecode(trimmed);
      if (json is Map<String, dynamic>) {
        // Standard OpenAI-like format (our grammar)
        if (json['type'] == 'function' && json['function'] != null) return true;
        // Simplified format common in some models
        if (json.containsKey('function') &&
            json['function'] is Map &&
            json['function'].containsKey('name')) {
          return true;
        }
        // Direct format: {"name": "...", "parameters": {...}}
        if (json.containsKey('name') && json.containsKey('parameters')) {
          return true;
        }
      } else if (json is List && json.isNotEmpty) {
        // Array of tool calls
        final first = json.first;
        if (first is Map &&
            (first['type'] == 'function' || first.containsKey('function'))) {
          return true;
        }
      }
      return false;
    } catch (_) {
      // If it starts with { but fails to parse, it might be a partial or malformed tool call.
      // We'll return false to let it be treated as normal text for now.
      return false;
    }
  }

  /// Process multimodal messages to ensure media markers are present.
  List<LlamaChatMessage> _processMultimodalMessages(
    List<LlamaChatMessage> messages,
  ) {
    return messages.map((m) {
      final mediaParts = m.parts.where(
        (p) => p is LlamaImageContent || p is LlamaAudioContent,
      );
      if (mediaParts.isEmpty) return m;

      // Count existing markers across all text parts of this message
      final markerCount = m.parts.whereType<LlamaTextContent>().fold(
        0,
        (count, p) => count + '<__media__>'.allMatches(p.text).length,
      );

      if (markerCount < mediaParts.length) {
        final missingMarkers = mediaParts.length - markerCount;
        final injection = ('<__media__>\n' * missingMarkers);

        final newParts = List<LlamaContentPart>.from(m.parts);
        int textIndex = newParts.indexWhere((p) => p is LlamaTextContent);
        if (textIndex != -1) {
          final oldText = (newParts[textIndex] as LlamaTextContent).text;
          newParts[textIndex] = LlamaTextContent('$injection$oldText');
        } else {
          newParts.insert(0, LlamaTextContent(injection.trim()));
        }
        return LlamaChatMessage.multimodal(role: m.role, parts: newParts);
      }
      return m;
    }).toList();
  }

  List<LlamaChatMessage> _getMessagesForEngine() {
    final messages = <LlamaChatMessage>[];
    if (systemPrompt != null && systemPrompt!.isNotEmpty) {
      messages.add(
        LlamaChatMessage.text(
          role: LlamaChatRole.system,
          content: systemPrompt!,
        ),
      );
    }
    messages.addAll(_history);
    return messages;
  }

  /// Truncates history if it exceeds the context limit.
  Future<void> _enforceContextLimit() async {
    final limit = maxContextTokens ?? await _engine.getContextSize();
    if (limit <= 0) return;

    while (_history.isNotEmpty) {
      final messages = _getMessagesForEngine();
      final template = await _engine.chatTemplate(messages);
      final tokenCount = await _engine.getTokenCount(template.prompt);

      // We need some buffer for the response.
      // Using a conservative 10% buffer or at least 256 tokens.
      final reserve = (limit * 0.1).clamp(128, 512).toInt();

      if (tokenCount < (limit - reserve)) {
        break;
      }

      // Remove the oldest non-system message (which is the first one in history)
      if (_history.length > 1) {
        _history.removeAt(0);
        // If it was a user message, we might want to remove the corresponding assistant message too
        if (_history.isNotEmpty &&
            _history[0].role == LlamaChatRole.assistant) {
          _history.removeAt(0);
        }
      } else {
        // Can't truncate more without losing the current message
        break;
      }
    }
  }
}
