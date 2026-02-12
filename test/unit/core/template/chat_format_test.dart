import 'dart:io';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:test/test.dart';

void main() {
  group('ChatFormat Detection', () {
    test('detects LFM 2.5 template from fixture', () {
      final file = File('test/fixtures/templates/LFM2_5-1_2B-Thinking.jinja');
      final source = file.readAsStringSync();
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.lfm2));
    });

    test('detects LFM 2.5 from keep_past_thinking marker', () {
      const source =
          '{%- set keep_past_thinking = true -%}<|im_start|>user\nhi<|im_end|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.lfm2));
    });

    test('falls back to generic for standard ChatML', () {
      const source = '<|im_start|>user\nhi<|im_end|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.generic));
    });
  });
}
