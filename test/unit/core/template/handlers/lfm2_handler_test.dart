import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/lfm2_handler.dart';
import 'package:test/test.dart';

void main() {
  test('Lfm2Handler exposes chat format', () {
    final handler = Lfm2Handler();
    expect(handler.format, isA<ChatFormat>());
  });
}
