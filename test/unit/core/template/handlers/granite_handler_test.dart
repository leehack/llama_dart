import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/granite_handler.dart';
import 'package:test/test.dart';

void main() {
  test('GraniteHandler exposes chat format', () {
    final handler = GraniteHandler();
    expect(handler.format, isA<ChatFormat>());
  });
}
