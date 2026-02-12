import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/template_workarounds.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateWorkarounds', () {
    test('normalizeToolCallArgs converts string arguments to object', () {
      final messages = [
        <String, dynamic>{
          'role': 'assistant',
          'tool_calls': [
            {
              'type': 'function',
              'function': {'name': 'weather', 'arguments': '{"city":"Seoul"}'},
            },
          ],
        },
      ];

      TemplateWorkarounds.normalizeToolCallArgs(messages);

      final args =
          (messages.first['tool_calls'] as List).first['function']['arguments'];
      expect(args, equals({'city': 'Seoul'}));
    });

    test('useGenericSchema converts OpenAI tool call shape', () {
      final messages = [
        <String, dynamic>{
          'role': 'assistant',
          'tool_calls': [
            {
              'type': 'function',
              'id': 'call_1',
              'function': {
                'name': 'weather',
                'arguments': {'city': 'Seoul'},
              },
            },
          ],
        },
      ];

      TemplateWorkarounds.useGenericSchema(messages);

      final call = (messages.first['tool_calls'] as List).first;
      expect(
        call,
        equals({
          'name': 'weather',
          'arguments': {'city': 'Seoul'},
          'id': 'call_1',
        }),
      );
    });

    test('moveToolCallsToContent appends JSON and removes tool_calls', () {
      final messages = [
        <String, dynamic>{
          'role': 'assistant',
          'content': 'prefix:',
          'tool_calls': [
            {
              'name': 'weather',
              'arguments': {'city': 'Seoul'},
            },
          ],
        },
      ];

      TemplateWorkarounds.moveToolCallsToContent(messages);

      final message = messages.first;
      expect(message.containsKey('tool_calls'), isFalse);
      expect(message['content'], contains('prefix:'));
      expect(message['content'], contains('"tool_calls"'));
      expect(message['content'], contains('"weather"'));
    });

    test('applyFormatWorkarounds applies Granite chain', () {
      final input = [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            const LlamaToolCallContent(
              name: 'weather',
              arguments: {'city': 'Seoul'},
              rawJson: '{"city":"Seoul"}',
            ),
          ],
        ),
      ];

      final output = TemplateWorkarounds.applyFormatWorkarounds(
        input,
        ChatFormat.granite,
      );

      final json = output.first.toJson();
      expect(json.containsKey('tool_calls'), isFalse);
      expect(json['content'], isA<String>());
      expect(json['content'], contains('"tool_calls"'));
      expect(json['content'], contains('"weather"'));
    });
  });
}
