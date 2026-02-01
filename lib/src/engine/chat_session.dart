import 'dart:async';
import 'llama_engine.dart';
import '../models/llama_chat_message.dart';
import '../models/generation_params.dart';

/// Manages a chat session, including history and context window management.
class ChatSession {
  final LlamaEngine _engine;
  final List<LlamaChatMessage> _history = [];
  String? _systemPrompt;

  /// The maximum number of tokens allowed in the context window.
  /// If null, it will be fetched from the engine's metadata.
  int? maxContextTokens;

  /// Creates a new [ChatSession] wrapping the given [engine].
  ChatSession(this._engine, {this.maxContextTokens, String? systemPrompt}) {
    _systemPrompt = systemPrompt;
  }

  /// The current message history.
  List<LlamaChatMessage> get history => List.unmodifiable(_history);

  /// Sets or updates the system prompt.
  /// This will persist across the session and be included in every request.
  set systemPrompt(String? prompt) => _systemPrompt = prompt;

  /// Gets the current system prompt.
  String? get systemPrompt => _systemPrompt;

  /// Adds a message to the history.
  void addMessage(LlamaChatMessage message) {
    _history.add(message);
  }

  /// Clears the chat history, optionally keeping the system prompt.
  void clearHistory() {
    _history.clear();
  }

  /// Sends a message and returns a stream of tokens.
  /// Automatically manages history and context window.
  Stream<String> chat(String text, {GenerationParams? params}) async* {
    _history.add(LlamaChatMessage(role: 'user', content: text));

    // Ensure we are within context limits before sending
    await _enforceContextLimit();

    final messages = _getMessagesForEngine();
    String fullResponse = "";

    await for (final token in _engine.chat(messages, params: params)) {
      fullResponse += token;
      yield token;
    }

    _history.add(
      LlamaChatMessage(role: 'assistant', content: fullResponse.trim()),
    );
  }

  /// Sends a message and returns the full response string.
  Future<String> chatText(String text, {GenerationParams? params}) async {
    final buffer = StringBuffer();
    await for (final token in chat(text, params: params)) {
      buffer.write(token);
    }
    return buffer.toString().trim();
  }

  List<LlamaChatMessage> _getMessagesForEngine() {
    final messages = <LlamaChatMessage>[];
    if (_systemPrompt != null && _systemPrompt!.isNotEmpty) {
      messages.add(LlamaChatMessage(role: 'system', content: _systemPrompt!));
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
        if (_history.isNotEmpty && _history[0].role == 'assistant') {
          _history.removeAt(0);
        }
      } else {
        // Can't truncate more without losing the current message
        break;
      }
    }
  }
}
