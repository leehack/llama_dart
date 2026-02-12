import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/exaone_moe_handler.dart';
import 'package:test/test.dart';

void main() {
  test('ExaoneMoeHandler exposes chat format', () {
    final handler = ExaoneMoeHandler();
    expect(handler.format, isA<ChatFormat>());
  });
}
