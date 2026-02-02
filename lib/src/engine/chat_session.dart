import 'dart:async';
import 'llama_engine.dart';
import '../models/llama_chat_message.dart';
import '../models/llama_chat_role.dart';
import '../models/generation_params.dart';
import '../models/llama_tool.dart';
import '../common/json_schema_to_gbnf.dart';

/// Manages a chat session, including history and context window management.
///
/// [ChatSession] provides a stateful interface over [LlamaEngine], handling
/// conversation history and automatically ensuring that the total token count
/// stays within the model's context window limits by truncating older messages.
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
  /// and [systemPrompt] to define the initial persona or instructions.
  ChatSession(this._engine, {this.maxContextTokens, this.systemPrompt});

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

  /// Adds a custom [message] directly to the history.
  ///
  /// Useful for pre-seeding a conversation or restoring a previous state.
  void addMessage(LlamaChatMessage message) {
    _history.add(message);
  }

  /// Adds a multimodal message to the history.
  void addMultimodalMessage(LlamaChatMessage message) {
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
  /// is cleared. Set it to false to also clear the [systemPrompt].
  void reset({bool keepSystemPrompt = true}) {
    _history.clear();
    if (!keepSystemPrompt) {
      systemPrompt = null;
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
  /// If [tools] are provided, a GBNF grammar will be generated to force the
  /// model to output a tool call matching one of the tools.
  Stream<String> chat(
    String text, {
    GenerationParams? params,
    List<LlamaTool>? tools,
  }) async* {
    _history.add(
      LlamaChatMessage.text(role: LlamaChatRole.user, content: text),
    );

    // Ensure we are within context limits before sending
    await _enforceContextLimit();

    final messages = _getMessagesForEngine();

    // If tools are provided, generate grammar and attach to params
    GenerationParams? effectiveParams = params;
    List<LlamaChatMessage>? toolMessages;
    if (tools != null && tools.isNotEmpty) {
      final toolGrammar = JsonSchemaToGbnf.generateToolGrammar(tools);
      effectiveParams = (params ?? const GenerationParams()).copyWith(
        grammar: toolGrammar,
      );

      // Build a tool prompt to guide the model to use proper JSON format
      final toolDescriptions = tools
          .map((t) {
            final paramNames =
                (t.parameters['properties'] as Map<String, dynamic>?)?.keys
                    .toList() ??
                [];
            final requiredParams =
                (t.parameters['required'] as List?)?.cast<String>() ?? [];
            final paramInfo = paramNames
                .map((p) {
                  final isRequired = requiredParams.contains(p);
                  return '    - $p${isRequired ? " (required)" : " (optional)"}';
                })
                .join('\n');
            return '''${t.name}: ${t.description}
  Parameters:
$paramInfo''';
          })
          .join('\n\n');

      final toolSystemPrompt =
          '''You are a helpful assistant that uses tools to answer questions.

Available tools:
$toolDescriptions

IMPORTANT: You must respond ONLY with a JSON tool call. Use the exact parameter names shown above.
Format: {"type": "function", "function": {"name": "<tool_name>", "parameters": {"<param_name>": "<value>", ...}}}

Do not include any explanatory text. Output only the JSON.''';

      // Create messages with tool prompt prepended
      toolMessages = [
        LlamaChatMessage.text(
          role: LlamaChatRole.system,
          content: toolSystemPrompt,
        ),
        ..._getMessagesForEngine(),
      ];
    }

    String fullResponse = "";

    // Use tool messages if tools were provided, otherwise use regular messages
    final chatMessages = toolMessages ?? messages;

    await for (final token in _engine.chat(
      chatMessages,
      params: effectiveParams,
    )) {
      fullResponse += token;
      yield token;
    }

    _history.add(
      LlamaChatMessage.text(
        role: LlamaChatRole.assistant,
        content: fullResponse.trim(),
      ),
    );
  }

  /// Sends a user [text] message and returns the full response string.
  ///
  /// Wraps [chat] but waits for the entire generation to complete and
  /// returns the concatenated tokens as a single trimmed string.
  Future<String> chatText(
    String text, {
    GenerationParams? params,
    List<LlamaTool>? tools,
  }) async {
    final buffer = StringBuffer();
    await for (final token in chat(text, params: params, tools: tools)) {
      buffer.write(token);
    }
    return buffer.toString().trim();
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
