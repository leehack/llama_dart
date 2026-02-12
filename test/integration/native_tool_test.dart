import 'dart:io';
import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import '../test_helper.dart';

// Model Matrix
const models = [
  (
    url:
        'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true',
    file: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
    expectTools: false, // Native template doesn't support tools yet
  ),
];

void main() {
  group('Native Tool Integration Tests', () {
    late LlamaEngine engine;

    setUp(() {
      engine = LlamaEngine(LlamaBackend());
    });

    tearDown(() async {
      await engine.dispose();
    });

    for (final model in models) {
      test(
        'applyChatTemplate with tools for ${model.file}',
        () async {
          if (Platform.environment['CI'] != null) {
            print('Skipping large model download in CI');
            return;
          }

          print('Testing ${model.file}...');
          final modelFile = await TestHelper.ensureModel(model.url, model.file);

          // Reload engine with real path
          await engine.loadModel(modelFile.path, modelParams: ModelParams());

          final tools = [
            ToolDefinition(
              name: 'get_weather',
              description: 'Get the current weather in a given location',
              parameters: [
                ToolParam.string(
                  'location',
                  description: 'The city and state, e.g. San Francisco, CA',
                ),
                ToolParam.string(
                  'unit',
                  description:
                      'The unit of temperature, e.g. celsius or fahrenheit',
                ),
              ],
              handler: (params) async => "22 degrees",
            ),
          ];

          final messages = [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: "What's the weather in Paris?",
            ),
          ];

          final result = await engine.chatTemplate(
            messages,
            tools: tools,
            addAssistant: true,
          );

          print('Prompt for ${model.file}:\n${result.prompt}');

          // Basic verification: check if tool definition appears in prompt
          // Use loose check because different models format differently
          if (model.expectTools) {
            expect(result.prompt, contains('get_weather'));
            expect(result.prompt, contains('location'));
          }
        },
        timeout: Timeout(Duration(minutes: 10)),
        tags: ['no-ci'],
      );
    }
  });
}
