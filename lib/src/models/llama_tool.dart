/// Represents a tool (function) that the model can call.
class LlamaTool {
  /// The name of the tool (e.g., "get_weather").
  final String name;

  /// A description of what the tool does.
  final String description;

  /// The JSON schema for the tool's parameters.
  ///
  /// Should be a Map representing a valid JSON Schema object.
  final Map<String, dynamic> parameters;

  /// Creates a new [LlamaTool].
  const LlamaTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// Converts this tool definition to a map (for API compatibility/logging).
  Map<String, dynamic> toMap() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parameters,
      },
    };
  }
}
