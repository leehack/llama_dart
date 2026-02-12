import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/functionary_v31_llama31_handler.dart';
import 'package:test/test.dart';

void main() {
  test('FunctionaryV31Llama31Handler exposes chat format', () {
    final handler = FunctionaryV31Llama31Handler();
    expect(handler.format, isA<ChatFormat>());
  });
}
