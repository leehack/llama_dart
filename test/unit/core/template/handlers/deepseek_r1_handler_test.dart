import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/deepseek_r1_handler.dart';
import 'package:test/test.dart';

void main() {
  test('DeepseekR1Handler exposes chat format', () {
    final handler = DeepseekR1Handler();
    expect(handler.format, isA<ChatFormat>());
  });
}
