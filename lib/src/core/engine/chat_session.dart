import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'engine.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/completion_chunk.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/content_part.dart';
import '../models/inference/generation_params.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';

/// Convenience wrapper for multi-turn chat with automatic history management.
///
/// [ChatSession] wraps [LlamaEngine] and automatically manages conversation
/// history and context window limits. For stateless usage (like OpenAI's
/// Chat Completions API), use [LlamaEngine.create] directly.
///
/// Example:
/// ```dart
/// final engine = LlamaEngine(LlamaBackend());
/// await engine.loadModel('model.gguf');
///
/// final session = ChatSession(engine);
/// session.systemPrompt = 'You are a helpful assistant.';
///
/// await for (final token in session.create([LlamaTextContent('Hello!')])) {
///   print(token);
/// }
/// ```
class ChatSession {
  final LlamaEngine _engine;
  final List<LlamaChatMessage> _history = [];

  /// The maximum number of tokens allowed in the context window.
  ///
  /// If null, this value will be automatically retrieved from the engine's
  /// model metadata.
  int? maxContextTokens;

  /// Creates a new [ChatSession] wrapping the given [engine].
  ChatSession(this._engine, {this.maxContextTokens, this.systemPrompt});

  /// The underlying engine instance.
  LlamaEngine get engine => _engine;

  /// The current message history, excluding the [systemPrompt].
  ///
  /// Returns an unmodifiable list of [LlamaChatMessage].
  List<LlamaChatMessage> get history => List.unmodifiable(_history);

  /// The system prompt for this session.
  ///
  /// If set, this prompt is automatically prepended to the message list
  /// during every [create] request.
  String? systemPrompt;

  /// Adds a custom [message] directly to the history.
  ///
  /// Useful for:
  /// - Pre-seeding a conversation
  /// - Adding tool results after parsing tool calls
  /// - Restoring a previous session state
  void addMessage(LlamaChatMessage message) {
    _history.add(message);
  }

  /// Resets the session state.
  ///
  /// By default, [keepSystemPrompt] is true, meaning only the message history
  /// is cleared.
  void reset({bool keepSystemPrompt = true}) {
    _history.clear();
    if (!keepSystemPrompt) {
      systemPrompt = null;
    }
  }

  /// Sends a user message and returns a stream of generated response tokens.
  ///
  /// The [parts] list contains the message content. For text-only messages,
  /// use `[LlamaTextContent('your message')]`. For multimodal content,
  /// include `LlamaImageContent` or `LlamaAudioContent` parts.
  ///
  /// Pass [tools] to enable function calling. Use [toolChoice] to control
  /// whether the model should use tools:
  /// - [ToolChoice.none]: Model won't call any tool
  /// - [ToolChoice.auto]: Model can choose (default when tools present)
  /// - [ToolChoice.required]: Model must call at least one tool
  ///
  /// Set [parallelToolCalls] to allow multiple tool calls in one response for
  /// templates that support it.
  ///
  /// Example with tools:
  /// ```dart
  /// final response = await session.create(
  ///   [LlamaTextContent('What time is it?')],
  ///   tools: [getTimeTool],
  /// ).join();
  ///
  /// if (isToolCall(response)) {
  ///   final result = await executeMyTool(parseToolCall(response));
  ///   session.addMessage(LlamaChatMessage.toolResult(name, result));
  ///   final finalResponse = await session.create([]).join();
  /// }
  /// ```
  Stream<LlamaCompletionChunk> create(
    List<LlamaContentPart> parts, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) async* {
    // Add user message if parts provided
    if (parts.isNotEmpty) {
      final userMsg = parts.length == 1 && parts.first is LlamaTextContent
          ? LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: (parts.first as LlamaTextContent).text,
            )
          : LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: parts,
            );
      _history.add(userMsg);
      onMessageAdded?.call(userMsg);
    }

    // Ensure we are within context limits
    await _enforceContextLimit();

    // Build messages for engine
    final messages = _buildMessages();

    // Generate response
    String fullContent = "";
    String fullThinking = "";
    final Map<int, _ToolCallBuilder> toolCallBuilders = {};

    await for (final chunk in _engine.create(
      messages,
      params: params,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
    )) {
      final delta = chunk.choices.first.delta;
      if (delta.content != null) fullContent += delta.content!;
      if (delta.thinking != null) fullThinking += delta.thinking!;

      if (delta.toolCalls != null) {
        for (final tc in delta.toolCalls!) {
          toolCallBuilders.putIfAbsent(tc.index, () => _ToolCallBuilder());
          final builder = toolCallBuilders[tc.index]!;
          if (tc.id != null) builder.id = tc.id;
          if (tc.type != null) builder.type = tc.type;
          if (tc.function?.name != null) builder.name = tc.function!.name;
          if (tc.function?.arguments != null) {
            builder.arguments += tc.function!.arguments!;
          }
        }
      }

      yield chunk;
    }

    // Reconstruct final message with all parts
    final contentParts = <LlamaContentPart>[];

    if (fullThinking.isNotEmpty) {
      contentParts.add(LlamaThinkingContent(fullThinking));
    }

    if (fullContent.isNotEmpty) {
      contentParts.add(LlamaTextContent(fullContent));
    }

    // Add tool calls
    final sortedIndices = toolCallBuilders.keys.toList()..sort();
    for (final index in sortedIndices) {
      final b = toolCallBuilders[index]!;
      Map<String, dynamic> args = {};
      try {
        if (b.arguments.isNotEmpty) {
          args = jsonDecode(b.arguments);
        }
      } catch (_) {
        // Keep empty if parse fails
      }

      contentParts.add(
        LlamaToolCallContent(
          id: b.id,
          name: b.name ?? "",
          arguments: args,
          rawJson: b.arguments,
        ),
      );
    }

    final assistantMsg = LlamaChatMessage.withContent(
      role: LlamaChatRole.assistant,
      content: contentParts,
    );
    _history.add(assistantMsg);
    onMessageAdded?.call(assistantMsg);
  }

  /// Builds the message list for the engine, including system prompt.
  List<LlamaChatMessage> _buildMessages() {
    final messages = <LlamaChatMessage>[];

    // Add system prompt if set
    if (systemPrompt != null && systemPrompt!.isNotEmpty) {
      messages.add(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: systemPrompt!,
        ),
      );
    }

    // Add history (excluding any existing system messages - we use our own)
    messages.addAll(_history.where((m) => m.role != LlamaChatRole.system));
    return messages;
  }

  /// Truncates history if it exceeds the context limit.
  Future<void> _enforceContextLimit() async {
    final limit = maxContextTokens ?? await _engine.getContextSize();
    if (limit <= 0) return;

    // Reserve 10% for response
    final reserve = (limit * 0.1).clamp(128, 512).toInt();
    final targetLimit = limit - reserve;

    while (_history.isNotEmpty) {
      final messages = _buildMessages();
      final template = await _engine.chatTemplate(messages);

      final tokenCount =
          template.tokenCount ?? await _engine.getTokenCount(template.prompt);

      if (tokenCount < targetLimit) {
        break;
      }

      // Remove oldest messages
      final overBy = tokenCount - targetLimit;
      if (overBy > 500 && _history.length > 4) {
        // Remove 2 turns at once if way over
        _history.removeRange(0, min(4, _history.length - 1));
      } else {
        _history.removeAt(0);
        // Remove corresponding assistant message if we removed a user message
        if (_history.isNotEmpty &&
            _history[0].role == LlamaChatRole.assistant) {
          _history.removeAt(0);
        }
      }
    }
  }
}

class _ToolCallBuilder {
  String? id;
  String? type;
  String? name;
  String arguments = "";
}
