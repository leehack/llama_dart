import 'dart:convert';

import '../models/tools/tool_definition.dart';
import 'json_schema_converter.dart';

/// Result of tool grammar generation.
class ToolGrammarResult {
  /// The GBNF grammar string.
  final String grammar;

  /// Whether grammar should be lazily applied.
  final bool grammarLazy;

  /// Trigger words/patterns that activate grammar constraints.
  final List<String> grammarTriggers;

  /// Creates a [ToolGrammarResult] with the given [grammar] and options.
  const ToolGrammarResult({
    required this.grammar,
    this.grammarLazy = false,
    this.grammarTriggers = const [],
  });
}

/// Controls how tool usage is enforced.
enum ToolChoice {
  /// Model decides whether to use tools (default).
  auto,

  /// Model MUST call a tool.
  required,

  /// Model MUST NOT use tools (grammar not applied).
  none,
}

/// Generates GBNF grammars for tool calling.
///
/// Given a list of [ToolDefinition]s, produces a grammar that constrains
/// the model to output valid tool calls matching the provided schemas.
class ToolGrammarGenerator {
  const ToolGrammarGenerator._();

  /// Generate a grammar that constrains output to valid tool calls.
  ///
  /// When [toolChoice] is [ToolChoice.none], returns `null` (no constraint).
  /// When [ToolChoice.required], forces the model to call exactly one tool.
  /// When [ToolChoice.auto], allows either a tool call or free text.
  static ToolGrammarResult? generate(
    List<ToolDefinition> tools, {
    ToolChoice toolChoice = ToolChoice.auto,
  }) {
    if (tools.isEmpty || toolChoice == ToolChoice.none) return null;

    if (tools.length == 1) {
      return _generateSingleTool(tools.first, toolChoice);
    }

    return _generateMultiTool(tools, toolChoice);
  }

  /// Generate a grammar for a single JSON schema (e.g. `response_format`).
  static String generateForSchema(Map<String, dynamic> schema) {
    return JsonSchemaConverter.convert(schema);
  }

  // ---------------------------------------------------------------------------
  // Single tool
  // ---------------------------------------------------------------------------

  static ToolGrammarResult _generateSingleTool(
    ToolDefinition tool,
    ToolChoice choice,
  ) {
    // Build the parameter schema grammar
    final paramSchema = tool.toJsonSchema();
    final paramGrammar = JsonSchemaConverter.convert(paramSchema);

    // Wrap in a tool call object: {"name": "tool_name", "arguments": {...}}
    final grammar = _wrapToolCall(tool.name, paramGrammar);

    return ToolGrammarResult(
      grammar: grammar,
      grammarLazy: choice == ToolChoice.auto,
      grammarTriggers: choice == ToolChoice.auto
          ? ['{', '<tool_call>']
          : const [],
    );
  }

  // ---------------------------------------------------------------------------
  // Multi-tool
  // ---------------------------------------------------------------------------

  static ToolGrammarResult _generateMultiTool(
    List<ToolDefinition> tools,
    ToolChoice choice,
  ) {
    // Build individual tool call grammars and combine with union
    final toolRules = <String>[];
    final allRules = <String, String>{};

    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i];
      final paramSchema = tool.toJsonSchema();
      final converter = JsonSchemaConverter();
      converter.resolveRefs(paramSchema, paramSchema);
      final paramRuleName = converter.visit(paramSchema, 'tool-$i-params');

      // Add all rules from this converter
      for (final entry in converter.rules.entries) {
        allRules[entry.key] = entry.value;
      }

      // Build the tool call rule for this specific tool
      final nameStr = jsonEncode(tool.name);
      final toolRule =
          '"{" space "\\"name\\"" space ":" space $nameStr space "," space "\\"arguments\\"" space ":" space $paramRuleName "}" space';
      final toolRuleName = 'tool-$i';
      allRules[toolRuleName] = toolRule;
      toolRules.add(toolRuleName);
    }

    // Root rule is union of all tool calls
    allRules['root'] = toolRules.join(' | ');

    // Format grammar
    final buf = StringBuffer();
    final sortedEntries = allRules.entries.toList()
      ..sort((a, b) {
        if (a.key == 'root') return -1;
        if (b.key == 'root') return 1;
        return a.key.compareTo(b.key);
      });
    for (final entry in sortedEntries) {
      buf.writeln('${entry.key} ::= ${entry.value}');
    }

    return ToolGrammarResult(
      grammar: buf.toString(),
      grammarLazy: choice == ToolChoice.auto,
      grammarTriggers: choice == ToolChoice.auto
          ? ['{', '<tool_call>']
          : const [],
    );
  }

  // ---------------------------------------------------------------------------
  // Helper: wrap parameter grammar in a tool call object
  // ---------------------------------------------------------------------------

  static String _wrapToolCall(String toolName, String paramGrammar) {
    // Parse the param grammar to extract the root rule content
    // and re-embed it in a tool call wrapper
    final lines = paramGrammar.split('\n').where((l) => l.trim().isNotEmpty);
    final rules = <String, String>{};
    for (final line in lines) {
      final idx = line.indexOf(' ::= ');
      if (idx == -1) continue;
      rules[line.substring(0, idx).trim()] = line.substring(idx + 5).trim();
    }

    // Get the root rule content (this is the parameter object grammar)
    final rootContent = rules.remove('root');
    if (rootContent == null) {
      return paramGrammar; // Fallback
    }

    // Create a new root that wraps name + arguments
    final nameStr = jsonEncode(toolName);
    rules['root'] =
        '"{" space "\\"name\\"" space ":" space $nameStr space "," space "\\"arguments\\"" space ":" space params "}" space';
    rules['params'] = rootContent;

    // Format
    final buf = StringBuffer();
    final sortedEntries = rules.entries.toList()
      ..sort((a, b) {
        if (a.key == 'root') return -1;
        if (b.key == 'root') return 1;
        return a.key.compareTo(b.key);
      });
    for (final entry in sortedEntries) {
      buf.writeln('${entry.key} ::= ${entry.value}');
    }
    return buf.toString();
  }
}
