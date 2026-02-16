/// Invokes one server-side tool by name and arguments.
typedef OpenAiToolInvoker =
    Future<Object?> Function(String toolName, Map<String, dynamic> arguments);
