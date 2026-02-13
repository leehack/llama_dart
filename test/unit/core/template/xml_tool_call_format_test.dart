import 'dart:convert';

import 'package:llamadart/src/core/template/xml_tool_call_format.dart';
import 'package:test/test.dart';

void main() {
  test('parseXmlToolCalls parses a simple XML-like tool call', () {
    const output =
        '<function=weather><parameter=city>"Seoul"</parameter></function>';
    final parsed = parseXmlToolCalls(output, XmlToolCallFormat.qwen3Coder);

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, 'weather');
    expect(jsonDecode(parsed.toolCalls.first.function!.arguments!), {
      'city': 'Seoul',
    });
  });
}
