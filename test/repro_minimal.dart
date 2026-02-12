import 'package:dinja/dinja.dart';
import 'package:test/test.dart';

void main() {
  test('Minimal Namespace Reproduction', () {
    final templateSource = "{% set ns = namespace(val=1) %}{{ ns.val }}";
    final template = Template(templateSource);
    final result = template.render();
    print('Result 1: $result');
    expect(result, '1');
  });

  test('Minimal Namespace Assignment Reproduction', () {
    final templateSource =
        "{% set ns = namespace(val=1) %}{% set ns.val = 2 %}{{ ns.val }}";
    final template = Template(templateSource);
    final result = template.render();
    print('Result 3: $result');
    expect(result, '2');
  });

  test('List Attribute Access Reproduction', () {
    final templateSource = "{{ list.split }}";
    final template = Template(templateSource);
    // Should now THROW TypeError in strict mode
    expect(
      () => template.render({
        'list': [1, 2, 3],
      }),
      throwsA(anyOf(isA<TypeError>(), isA<NoSuchMethodError>())),
    );
  });

  test('In Null Reproduction', () {
    final templateSource =
        "{% if 'foo' in content %}yes{% else %}no{% endif %}";
    final template = Template(templateSource);
    // Should now THROW TypeError in strict mode
    expect(() => template.render({'content': null}), throwsA(isA<TypeError>()));
  });

  test('Is String Reproduction', () {
    final templateSource =
        "{% if content is string %}yes{% else %}no{% endif %}";
    final template = Template(templateSource);
    expect(template.render({'content': 'foo'}), 'yes');
    expect(template.render({'content': null}), 'no');
    expect(
      template.render({
        'content': [1, 2, 3],
      }),
      'no',
    );
    print('Result 5: all tests passed for is string');
  });

  test('Minimal Attribute Reproduction', () {
    final templateSource = "{{ messages[0].role }}";
    final template = Template(templateSource);
    final result = template.render({
      'messages': [
        {'role': 'user'},
      ],
    });
    print('Result 2: $result');
    expect(result, 'user');
  });

  test('String Slice Reproduction', () {
    final template = Template('{{ value[:3] }}');
    expect(template.render({'value': 'hello'}), equals('hel'));
  });
}
