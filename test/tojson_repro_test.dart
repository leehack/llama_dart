import 'package:jinja/jinja.dart';
import 'package:test/test.dart';

void main() {
  test('Verify tojson indent=4 fix', () {
    final env = Environment();
    // Llama 3.2 style: named indent
    final template = env.fromString('{{ data | tojson(indent=4) }}');

    final data = {
      'key': 'value',
      'list': [1, 2, 3],
    };

    final result = template.render({'data': data});
    print('Rendered Output:\n$result');
    expect(result, contains('"key": "value"'));
    // Indent 4 means nested items are at 8 spaces
    expect(result, contains('        1,'));
    expect(result, contains('    "list": ['));
  });

  test('Verify tojson with integer indent (named)', () {
    final env = Environment();
    final template = env.fromString('{{ data | tojson(indent=2) }}');

    final data = {'key': 'value'};

    final result = template.render({'data': data});
    print('Rendered Output (2 spaces):\n$result');
    expect(result, contains('  "key": "value"'));
  });
}
