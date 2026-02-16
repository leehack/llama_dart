/// Parsed tool-call payload emitted by one completion turn.
class OpenAiToolCallRecord {
  /// Tool call index in emitted order.
  final int index;

  /// Tool call id.
  final String id;

  /// Tool call type (usually `function`).
  final String type;

  /// Tool function name.
  final String name;

  /// Raw JSON arguments string.
  final String argumentsRaw;

  /// Parsed argument object when valid JSON object, else empty map.
  final Map<String, dynamic> arguments;

  /// Creates an immutable tool-call record.
  const OpenAiToolCallRecord({
    required this.index,
    required this.id,
    required this.type,
    required this.name,
    required this.argumentsRaw,
    required this.arguments,
  });

  /// Converts this record into OpenAI-compatible `tool_calls` JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'function': {'name': name, 'arguments': argumentsRaw},
    };
  }
}
