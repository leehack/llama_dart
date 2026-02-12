import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/seed_oss_handler.dart';
import 'package:test/test.dart';

void main() {
  test('SeedOssHandler exposes chat format', () {
    final handler = SeedOssHandler();
    expect(handler.format, isA<ChatFormat>());
  });
}
