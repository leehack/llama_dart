import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/xiaomi_mimo_handler.dart';
import 'package:test/test.dart';

void main() {
  test('XiaomiMimoHandler exposes chat format', () {
    final handler = XiaomiMimoHandler();
    expect(handler.format, isA<ChatFormat>());
  });
}
