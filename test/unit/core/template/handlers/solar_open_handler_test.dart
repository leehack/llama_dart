import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/solar_open_handler.dart';
import 'package:test/test.dart';

void main() {
  test('SolarOpenHandler exposes chat format', () {
    final handler = SolarOpenHandler();
    expect(handler.format, isA<ChatFormat>());
  });
}
