/// Converts a JSON Schema to a GBNF grammar string for Llama models.
class JsonSchemaToGbnf {
  /// Sanitizes a name for use as a GBNF rule name.
  /// GBNF requires dashed-lowercase-words, so underscores are converted to dashes.
  static String _sanitizeRuleName(String name) {
    return name.replaceAll('_', '-').toLowerCase();
  }

  /// Converts a JSON schema Map to a GBNF grammar string.
  ///
  /// The [schema] should be a valid JSON schema Map.
  /// Currently supports:
  /// - Types: object, array, string, number, integer, boolean, null
  /// - Keywords: properties, required, items, enum
  static String convert(Map<String, dynamic> schema) {
    final buffer = StringBuffer();
    // CRITICAL: Define the whitespace rule used throughout the grammar.
    buffer.writeln(whitespaceRule);
    buffer.writeln('root ::= ${visit(schema, "root", buffer)}');
    return buffer.toString();
  }

  /// Visits a schema node and returns the rule name.
  static String visit(
    Map<String, dynamic> schema,
    String name,
    StringBuffer buffer,
  ) {
    final type = schema['type'];

    if (schema.containsKey('enum')) {
      // For enum values in JSON, we need to match the quoted string
      // e.g., enum: ["celsius"] should match the literal: "celsius" (with quotes)
      // In GBNF, this is: "\"celsius\""
      final options = (schema['enum'] as List)
          .map((e) {
            final escaped = e
                .toString()
                .replaceAll('\\', '\\\\')
                .replaceAll('"', '\\"');
            return r'"\"' + escaped + r'\""';
          })
          .join(' | ');
      final ruleName = '$name-enum';
      buffer.writeln('$ruleName ::= $options');
      return ruleName;
    }

    switch (type) {
      case 'object':
        return _visitObject(schema, name, buffer);
      case 'array':
        return _visitArray(schema, name, buffer);
      case 'string':
        return _visitString(schema, name, buffer);
      case 'number':
      case 'integer':
        return _visitNumber(name, buffer);
      case 'boolean':
        return _visitBoolean(name, buffer);
      case 'null':
        return '"null"';
      default:
        // If type is missing but properties exist, treat as object
        if (schema.containsKey('properties')) {
          return _visitObject(schema, name, buffer);
        }
        // Fallback to allowing anything (simplified string)
        return _visitString(schema, name, buffer);
    }
  }

  static String _visitObject(
    Map<String, dynamic> schema,
    String name,
    StringBuffer buffer,
  ) {
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    final required = (schema['required'] as List?)?.cast<String>() ?? [];

    final ruleName = '$name-obj';

    if (properties.isEmpty) {
      buffer.writeln('$ruleName ::= "{" ws "}"');
      return ruleName;
    }

    // Separate required and optional properties
    final requiredProps = <String, Map<String, dynamic>>{};
    final optionalProps = <String, Map<String, dynamic>>{};

    properties.forEach((key, value) {
      if (required.contains(key)) {
        requiredProps[key] = value as Map<String, dynamic>;
      } else {
        optionalProps[key] = value as Map<String, dynamic>;
      }
    });

    final sb = StringBuffer();
    sb.write('"{" ws ');

    var isFirst = true;

    // Add required properties first
    for (final entry in requiredProps.entries) {
      final propRule = visit(entry.value, '$name-${entry.key}', buffer);
      final keyPart = r'"\"' + entry.key + r'\""';
      if (!isFirst) {
        sb.write(' "," ws ');
      }
      sb.write('$keyPart ":" ws $propRule');
      isFirst = false;
    }

    // Add optional properties with ? modifier
    for (final entry in optionalProps.entries) {
      final propRule = visit(entry.value, '$name-${entry.key}', buffer);
      final keyPart = r'"\"' + entry.key + r'\""';
      // Optional: comma + property pair, wrapped in ()?
      if (isFirst) {
        // First property is optional - no leading comma
        sb.write('($keyPart ":" ws $propRule)?');
      } else {
        // Subsequent optional properties need comma before
        sb.write(' ("," ws $keyPart ":" ws $propRule)?');
      }
      isFirst = false;
    }

    sb.write(' "}"');

    buffer.writeln('$ruleName ::= ${sb.toString()}');
    return ruleName;
  }

  static String _visitArray(
    Map<String, dynamic> schema,
    String name,
    StringBuffer buffer,
  ) {
    final items = schema['items'] as Map<String, dynamic>?;
    if (items == null) {
      return '"[]"';
    }

    final itemRule = visit(items, '$name-item', buffer);
    final ruleName = '$name-arr';

    // grammar: "[" ws (item ("," ws item)*)? "]"
    buffer.writeln('$ruleName ::= "[" ws ($itemRule ("," ws $itemRule)*)? "]"');
    return ruleName;
  }

  static String _visitString(
    Map<String, dynamic> schema,
    String name,
    StringBuffer buffer,
  ) {
    final ruleName = '$name-str';
    // Basic string grammar escaping quotes
    // GBNF: rule ::= "\"" ([^"\\] | "\\\\")* "\""
    // We need 4 backslashes in the character class to ensure GBNF sees 2,
    // which prevents the backslash from escaping the closing bracket ']'.
    buffer.writeln(
      '$ruleName ::= '
      r'"\"" ([^"\\] | "\\\\")* "\""',
    );
    return ruleName;
  }

  static String _visitNumber(String name, StringBuffer buffer) {
    final ruleName = '$name-num';
    buffer.writeln(
      '$ruleName ::= ("-"? ([0-9] | [1-9] [0-9]*)) ("." [0-9]+)? ([eE] [-+]? [0-9]+)?',
    );
    return ruleName;
  }

  static String _visitBoolean(String name, StringBuffer buffer) {
    final ruleName = '$name-bool';
    buffer.writeln('$ruleName ::= "true" | "false"');
    return ruleName;
  }

  /// Helper to get the common whitespace rule
  // Use escaped characters for whitespace class to avoid multiline string issues in GBNF parser
  static String get whitespaceRule => r'ws ::= [ \t\n]*';

  /// Generates a GBNF grammar for a list of tools.
  static String generateToolGrammar(List<dynamic> tools) {
    final buffer = StringBuffer();
    // CRITICAL: Include whitespace rule
    buffer.writeln(whitespaceRule);

    final toolRules = <String>[];

    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i];
      final name = tool is Map ? tool['name'] : (tool as dynamic).name;
      final safeName = _sanitizeRuleName(name as String);
      final params = tool is Map
          ? tool['parameters']
          : (tool as dynamic).parameters;

      final paramRule = visit(params, '$safeName-params', buffer);
      final toolRuleName = '$safeName-tool';

      // Define tool call structure:
      // { "type": "function", "function": { "name": "...", "parameters": ... } }
      // Using raw strings for rigorous GBNF quoting of keys.
      final typeKey = r'"\"type\""';
      final functionVal = r'"\"function\""';
      final functionKey = r'"\"function\""';
      final nameKey = r'"\"name\""';
      final nameVal = r'"\"' + name + r'\""';
      final paramsKey = r'"\"parameters\""';

      buffer.writeln(
        '$toolRuleName ::= "{" ws $typeKey ":" ws $functionVal "," ws $functionKey ":" ws "{" ws $nameKey ":" ws $nameVal "," ws $paramsKey ":" ws $paramRule "}" ws "}"',
      );
      toolRules.add(toolRuleName);
    }

    final joinedRules = toolRules.join(" | ");
    buffer.writeln('root ::= $joinedRules');
    return buffer.toString();
  }
}
