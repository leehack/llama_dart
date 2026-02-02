import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import 'test_helper.dart';

void main() {
  group('ChatTemplateProcessor (Unit)', () {
    late ChatTemplateProcessor processor;
    late MockLlamaBackend backend;

    setUp(() {
      backend = MockLlamaBackend();
      processor = ChatTemplateProcessor(backend, 1);
    });

    tearDown(() async {
      await backend.dispose();
    });

    test('apply returns mock result', () async {
      final messages = [const LlamaChatMessage(role: 'user', content: 'hi')];
      final result = await processor.apply(messages);
      expect(result.prompt, 'mock prompt');
      expect(result.stopSequences, ['</s>']);
    });

    test('detectStopSequences', () async {
      final stops = await processor.detectStopSequences();
      expect(stops, ['</s>']);
    });
  });
}
