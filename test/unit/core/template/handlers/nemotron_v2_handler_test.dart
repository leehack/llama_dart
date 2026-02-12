import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/nemotron_v2_handler.dart';
import 'package:test/test.dart';

void main() {
  test('NemotronV2Handler exposes chat format', () {
    final handler = NemotronV2Handler();
    expect(handler.format, isA<ChatFormat>());
  });
}
