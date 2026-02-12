import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/apertus_handler.dart';
import 'package:test/test.dart';

void main() {
  test('ApertusHandler exposes chat format', () {
    final handler = ApertusHandler();
    expect(handler.format, isA<ChatFormat>());
  });
}
