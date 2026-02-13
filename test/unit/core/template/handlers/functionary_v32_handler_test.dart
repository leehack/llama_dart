import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/functionary_v32_handler.dart';
import 'package:test/test.dart';

void main() {
  test('FunctionaryV32Handler exposes chat format', () {
    final handler = FunctionaryV32Handler();
    expect(handler.format, isA<ChatFormat>());
  });
}
