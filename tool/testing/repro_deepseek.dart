import 'package:dinja/dinja.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:test/test.dart';

void main() {
  test('DeepSeek R1 Template Reproduction', () {
    final templateSource =
        "{% if not add_generation_prompt is defined %}{% set add_generation_prompt = false %}{% endif %}"
        "{% if not bos_token is defined %}{% set bos_token = '<｜begin▁of▁sentence｜>' %}{% endif %}"
        "{% if not eos_token is defined %}{% set eos_token = '<｜end▁of▁sentence｜>' %}{% endif %}"
        "{{ bos_token }}"
        "{% for message in messages %}"
        "{% if message['role'] == 'user' %}"
        "{{ '<｜User｜>' + message['content'] }}"
        "{% elif message['role'] == 'assistant' and message['content'] is not none %}"
        "{% set content = message['content'] %}"
        "{% if '</think>' in content %}"
        "{% set content = content.split('</think>')[-1] %}"
        "{% endif %}"
        "{{ '<｜Assistant｜>' + content + eos_token }}"
        "{% endif %}"
        "{% endfor %}"
        "{% if add_generation_prompt %}"
        "{{ '<｜Assistant｜>' }}"
        "{% endif %}";

    final template = Template(templateSource);

    final messages = [
      LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: 'You are a helpful assistant.',
      ),
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello!'),
      LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [
          LlamaTextContent('I am thinking... '),
          LlamaTextContent('<think>Reasoning here</think> Answer.'),
        ],
      ),
    ];

    final messagesJson = messages.map((m) => m.toJson()).toList();
    print('Messages JSON: $messagesJson');

    try {
      final result = template.render({
        'messages': messagesJson,
        'add_generation_prompt': true,
      });
      print('Result: $result');

      // Verification:
      expect(result, contains('<｜User｜>Hello!'));
      expect(result, contains('<｜Assistant｜> Answer.'));
      expect(result, endsWith('<｜Assistant｜>'));
    } catch (e, stack) {
      print('Error: $e');
      print('Stack: $stack');
      fail('Should not crash');
    }
  });
}
