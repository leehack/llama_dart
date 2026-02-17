import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/template/handlers/generic_handler.dart';
import 'package:test/test.dart';

void main() {
  group('GenericHandler', () {
    const metadata = <String, String>{
      'tokenizer.ggml.bos_token': '<s>',
      'tokenizer.ggml.eos_token': '</s>',
    };

    const messages = [LlamaChatMessage(role: 'user', content: 'hello')];

    test('uses ChatML stop when template includes <|im_end|>', () {
      const template =
          '<|im_start|>user\n{{ messages[0]["content"] }}<|im_end|>';
      final handler = GenericHandler();

      final result = handler.render(
        templateSource: template,
        messages: messages,
        metadata: metadata,
      );

      expect(result.additionalStops, contains('<|im_end|>'));
      expect(result.additionalStops, isNot(contains('<|end|>')));
    });

    test('uses Phi stop when template includes <|end|>', () {
      const template =
          '<|user|>{{ messages[0]["content"] }}<|end|><|assistant|>';
      final handler = GenericHandler();

      final result = handler.render(
        templateSource: template,
        messages: messages,
        metadata: metadata,
      );

      expect(result.additionalStops, contains('<|end|>'));
      expect(result.additionalStops, isNot(contains('<|im_end|>')));
    });

    test('parses generic tool_call envelope JSON', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_call":{"name":"get_weather","arguments":{"city":"Seoul"}}}',
      );
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    });

    test('keeps non-native tool_call shape as plain content', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_call":{"function":{"name":"get_weather","arguments":{"city":"Seoul"}}}}',
      );
      expect(parsed.toolCalls, isEmpty);
      expect(
        parsed.content,
        '{"tool_call":{"function":{"name":"get_weather","arguments":{"city":"Seoul"}}}}',
      );
    });

    test('parses generic response envelope JSON', () {
      final handler = GenericHandler();

      final parsed = handler.parse('{"response":"hello"}');
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals('hello'));
    });

    test('keeps invalid JSON as plain content', () {
      final handler = GenericHandler();

      final parsed = handler.parse('weatherlookup');
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals('weatherlookup'));
    });
  });
}
