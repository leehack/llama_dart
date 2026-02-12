import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/hermes_handler.dart';
import 'package:test/test.dart';

void main() {
  test('HermesHandler exposes chat format', () {
    final handler = HermesHandler();
    expect(handler.format, isA<ChatFormat>());
  });
}
