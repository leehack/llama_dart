import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/apriel15_handler.dart';
import 'package:test/test.dart';

void main() {
  test('Apriel15Handler exposes chat format', () {
    final handler = Apriel15Handler();
    expect(handler.format, isA<ChatFormat>());
  });
}
