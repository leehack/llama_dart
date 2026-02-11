import 'package:jinja/jinja.dart';
// ignore: implementation_imports
import 'package:jinja/src/nodes.dart';

import '../template_caps.dart';

/// Analyzes a Jinja template AST to detect capabilities more robustly than regex.
class JinjaAnalyzer {
  /// Analyzes the [source] template and returns detected [TemplateCaps].
  static TemplateCaps analyze(String source) {
    try {
      final env = Environment();
      // Use parse instead of Parser constructor directly
      final templateNode = env.parse(source, path: 'template');

      // templateNode should be a Node, specifically TemplateNode usually, but Node is the return type.
      return _analyzeAST(templateNode, source);
    } catch (e) {
      // Fallback to regex if parsing fails (e.g. invalid syntax)
      return TemplateCaps.detectRegex(source);
    }
  }

  static TemplateCaps _analyzeAST(Node template, String source) {
    bool supportsSystemRole = false;
    bool supportsToolCalls = false;
    bool supportsTypedContent = false;
    bool supportsThinking = false;

    // Check nodes for specific patterns using findAll

    // 1. System Role: Look for 'role' == 'system' comparisons
    for (final node in template.findAll<Compare>()) {
      if (_isRoleSystemCheck(node)) {
        supportsSystemRole = true;
      }
    }

    // Check string literals for thinking tags and raw system
    for (final node in template.findAll<Data>()) {
      if (node.data.contains('<think>') ||
          node.data.contains('<｜thought｜>') ||
          node.data.contains('[THINK]')) {
        supportsThinking = true;
      }
    }

    // Check string constants
    for (final node in template.findAll<Constant>()) {
      final value = node.value;
      if (value is String &&
          (value.contains('<think>') ||
              value.contains('<｜thought｜>') ||
              value.contains('[THINK]'))) {
        supportsThinking = true;
      }
    }

    // 2. Tools: Look for iteration over 'tools' or 'tool_calls'
    for (final node in template.findAll<For>()) {
      final iter = node.iterable;
      if (iter is Name) {
        final name = iter.name;
        if (name == 'tools' || name == 'tool_calls') {
          supportsToolCalls = true;
        }
      } else if (iter is Item) {
        // e.g. message['tool_calls']
        // Item(value: message, key: 'tool_calls')
        if (_isMessageToolCalls(iter)) {
          supportsToolCalls = true;
        }
      } else if (iter is Attribute) {
        // e.g. message.tool_calls
        if (_isMessageToolCallsAttr(iter)) {
          supportsToolCalls = true;
        }
      }
    }

    // Also check If(tools)
    for (final node in template.findAll<If>()) {
      final test = node.test;
      if (test is Name) {
        final name = test.name;
        if (name == 'tools' || name == 'tool_calls') {
          supportsToolCalls = true;
        }
      }
    }

    // 3. Typed Content: Look for content['type'] or content.type
    for (final node in template.findAll<Item>()) {
      // content['type']
      if (_isContentTypeCheck(node)) {
        supportsTypedContent = true;
      }
    }
    for (final node in template.findAll<Attribute>()) {
      // content.type
      if (_isContentTypeCheckAttr(node)) {
        supportsTypedContent = true;
      }
    }

    // Check if iterating over content
    for (final node in template.findAll<For>()) {
      final iter = node.iterable;
      if (iter is Name && iter.name == 'content') {
        supportsTypedContent = true;
      }
      if (iter is Attribute && iter.attribute == 'content') {
        supportsTypedContent = true;
      }
      if (iter is Item &&
          iter.key is Constant &&
          (iter.key as Constant).value == 'content') {
        supportsTypedContent = true;
      }
    }

    return TemplateCaps(
      supportsSystemRole: supportsSystemRole,
      supportsToolCalls: supportsToolCalls,
      supportsTools: supportsToolCalls,
      supportsParallelToolCalls: supportsToolCalls,
      supportsStringContent: true,
      supportsTypedContent: supportsTypedContent,
      supportsThinking: supportsThinking,
    );
  }

  static bool _isRoleSystemCheck(Compare node) {
    bool isSystem(Expression e) {
      return e is Constant && e.value == 'system';
    }

    bool isRole(Expression e) {
      if (e is Name && e.name == 'role') return true;
      if (e is Attribute && e.attribute == 'role') return true;
      // Item(value: obj, key: index) -> obj['role']
      if (e is Item &&
          e.key is Constant &&
          (e.key as Constant).value == 'role') {
        return true;
      }
      return false;
    }

    if (isRole(node.value)) {
      for (final op in node.operands) {
        if (op.$1 == CompareOperator.equal && isSystem(op.$2)) return true;
      }
    }

    if (isSystem(node.value)) {
      for (final op in node.operands) {
        if (op.$1 == CompareOperator.equal && isRole(op.$2)) return true;
      }
    }

    return false;
  }

  static bool _isMessageToolCalls(Item node) {
    // Item(value: message, key: 'tool_calls')
    return node.key is Constant && (node.key as Constant).value == 'tool_calls';
  }

  static bool _isMessageToolCallsAttr(Attribute node) {
    return node.attribute == 'tool_calls';
  }

  static bool _isContentTypeCheck(Item node) {
    // content['type'] -> Item(value: content, key: 'type')
    if (node.key is Constant && (node.key as Constant).value == 'type') {
      final obj = node.value;
      // Direct: content['type']
      if (obj is Name && obj.name == 'content') return true;
      // Nested: message['content']['type'] -> Item(value: message['content'], key: 'type')
      if (obj is Item &&
          obj.key is Constant &&
          (obj.key as Constant).value == 'content') {
        return true;
      }
      // Don't match tool['type'] or other non-content accesses
      return false;
    }
    return false;
  }

  static bool _isContentTypeCheckAttr(Attribute node) {
    // content.type -> Attribute(value: content, attribute: 'type')
    if (node.attribute == 'type') {
      final obj = node.value;
      // Direct: content.type
      if (obj is Name && obj.name == 'content') return true;
      // Nested: message.content.type
      if (obj is Attribute && obj.attribute == 'content') return true;
      // Don't match tool.type or other non-content accesses
      return false;
    }
    return false;
  }
}
