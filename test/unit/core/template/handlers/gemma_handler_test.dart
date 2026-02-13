import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/gemma_handler.dart';
import 'package:test/test.dart';

void main() {
  test('GemmaHandler exposes chat format', () {
    final handler = GemmaHandler();
    expect(handler.format, isA<ChatFormat>());
  });
}
