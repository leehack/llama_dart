import 'package:test/test.dart';
import 'package:llamadart/src/core/template/jinja/jinja_analyzer.dart';

void main() {
  group('JinjaAnalyzer', () {
    test('detects capabilities in valid Jinja template', () {
      final template = '''
        {% for message in messages %}
          {% if message.role == 'system' %}
            {{ message.content }}
          {% endif %}
          {% if message.tool_calls %}
            {% for tool_call in message.tool_calls %}
               {{ tool_call.function.name }}
            {% endfor %}
          {% endif %}
          {% if message.role == 'user' %}
             {% for item in message.content %}
               {% if item.type == 'text' %}
                 {{ item.text }}
               {% endif %}
             {% endfor %}
          {% endif %}
        {% endfor %}
      ''';

      final caps = JinjaAnalyzer.analyze(template);

      expect(
        caps.supportsSystemRole,
        isTrue,
        reason: 'Should detect message.role == system',
      );
      expect(
        caps.supportsToolCalls,
        isTrue,
        reason: 'Should detect message.tool_calls iteration',
      );
      expect(
        caps.supportsTypedContent,
        isTrue,
        reason: 'Should detect item.type == text check',
      );
      expect(caps.supportsThinking, isFalse);
    });

    test('detects thinking tags', () {
      final template = '{{ "<think>" + message.content + "</think>" }}';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsThinking, isTrue);
    });

    test('detects thinking tags in raw data', () {
      final template = 'Raw text with <think> tag inside.';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsThinking, isTrue);
    });

    test('falls back to regex for invalid Jinja', () {
      // Invalid syntax: missing end tag
      final template = '''
        {% if message.role == 'system' %}
          {{ message.content }}
        {# Missing endif #}
      ''';

      // This should throw error in parser, caught by analyzer, falling back to regex.
      // Regex should still find 'system'.

      final caps = JinjaAnalyzer.analyze(template);
      expect(
        caps.supportsSystemRole,
        isTrue,
        reason: 'Fallback regex should detect system',
      );
    });

    test('detects tools variable iteration', () {
      final template = '{% for tool in tools %}{{ tool.name }}{% endfor %}';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsToolCalls, isTrue);
      // Current logic maps tools iteration to supportsToolCalls AND supportsTools
      expect(caps.supportsTools, isTrue);
    });

    test('detects message["role"] syntax', () {
      final template = '''
        {% if message['role'] == 'system' %}
          System: {{ message['content'] }}
        {% endif %}
      ''';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsSystemRole, isTrue);
    });

    test('detects content["type"] syntax', () {
      final template = '''
        {% for part in message['content'] %}
          {% if part['type'] == 'image' %}
             Image...
          {% endif %}
        {% endfor %}
      ''';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsTypedContent, isTrue);
    });
  });
}
