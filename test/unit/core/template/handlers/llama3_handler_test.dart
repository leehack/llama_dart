import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/llama3_handler.dart';
import 'package:test/test.dart';

void main() {
  test('Llama3Handler exposes chat format', () {
    final handler = Llama3Handler();
    expect(handler.format, isA<ChatFormat>());
  });
}
