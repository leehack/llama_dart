import 'package:llamadart/src/core/template/thinking_utils.dart';

void main() {
  print('--- Test 1: Standard thinking ---');
  final t1 = extractThinking('<think>\nI am thinking\n</think>\nHello!');
  print('Content: "${t1.content}"');
  print('Reasoning: "${t1.reasoning}"');

  print('\n--- Test 2: Pre-opened thinking (No <think> tag) ---');
  final t2 = extractThinking('\nI am thinking\n</think>\nHello!');
  print('Content: "${t2.content}"');
  print('Reasoning: "${t2.reasoning}"');

  print('\n--- Test 3: Multiple thinking blocks ---');
  final t3 = extractThinking(
    'Pre-opened\n</think>\nUser: hi\nAssistant: <think>\nThinking again\n</think>\nBye!',
  );
  print('Content: "${t3.content}"');
  print('Reasoning: "${t3.reasoning}"');

  print('\n--- Test 4: Open thinking (no </think>) ---');
  final t4 = extractThinking('<think>\nStill thinking');
  print('Content: "${t4.content}"');
  print('Reasoning: "${t4.reasoning}"');
}
