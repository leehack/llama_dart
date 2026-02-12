import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/magistral_handler.dart';
import 'package:test/test.dart';

void main() {
  test('MagistralHandler exposes chat format', () {
    final handler = MagistralHandler();
    expect(handler.format, isA<ChatFormat>());
  });
}
