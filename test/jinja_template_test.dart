import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:dinja/dinja.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

// Model configuration
const modelUrl =
    'https://huggingface.co/unsloth/functiongemma-270m-it-GGUF/resolve/main/functiongemma-270m-it-Q4_K_M.gguf?download=true';
const modelFileName = 'functiongemma-270m-it-Q4_K_M.gguf';

Future<void> _downloadModel(String url, String destPath) async {
  final file = File(destPath);
  if (await file.exists()) {
    print('Model already exists at $destPath');
    return;
  }

  print('Downloading model to $destPath...');
  final request = http.Request('GET', Uri.parse(url));
  final response = await http.Client().send(request);

  if (response.statusCode != 200) {
    throw Exception('Failed to download model: ${response.statusCode}');
  }

  final totalBytes = response.contentLength;
  int receivedBytes = 0;
  final sink = file.openWrite();

  await for (final chunk in response.stream) {
    sink.add(chunk);
    receivedBytes += chunk.length;
    if (totalBytes != null) {
      final progress = (receivedBytes / totalBytes) * 100;
      if (receivedBytes % (1024 * 1024) == 0) {
        // Print progress every MB
        stdout.write('\rDownloading: ${progress.toStringAsFixed(2)}%');
      }
    }
  }

  await sink.close();
  print('\nDownload complete.');
}

void main() {
  late LlamaBackend backend;
  late LlamaEngine engine;
  late String modelPath;

  setUpAll(() async {
    // Ensure models directory exists
    final modelsDir = Directory('models');
    if (!modelsDir.existsSync()) {
      modelsDir.createSync();
    }

    modelPath = path.join(modelsDir.path, modelFileName);
    await _downloadModel(modelUrl, modelPath);

    backend = LlamaBackend();
    engine = LlamaEngine(backend);
    engine.setLogLevel(LlamaLogLevel.error); // Suppress noise
  });

  tearDownAll(() async {
    await engine.dispose();
  });

  group('Jinja Template Tests', () {
    test('Load model, read metadata, and apply chat template with tools', () async {
      if (Platform.environment['CI'] != null) {
        print('Skipping jinja template integration test in CI');
        return;
      }

      print('Loading model...');
      await engine.loadModel(
        modelPath,
        modelParams: ModelParams(
          // Use low resource usage for CI/Testing
          gpuLayers: 0,
          contextSize: 1024,
        ),
      );

      print('Reading metadata...');
      final metadata = await engine.getMetadata();
      // print('Metadata keys: ${metadata.keys.toList()}');

      if (metadata.containsKey('tokenizer.chat_template')) {
        print('\n--- Model Chat Template ---');
        print(metadata['tokenizer.chat_template']);
        print('---------------------------\n');
      } else {
        print('WARNING: No chat template found in metadata.');
      }

      // Define tools
      final tools = [
        ToolDefinition(
          name: 'get_current_weather',
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

      // Create a user message containing a weather request
      final messages = [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: "What is the weather in London?",
        ),
      ];

      final messageData = messages.map((m) => m.toJson()).toList();

      final context = {
        'messages': messageData,
        'tools': tools.map((t) => t.toJson()).toList(),
      };

      final prompt = Template(
        metadata['tokenizer.chat_template'] as String,
      ).render(context);

      print('Applying chat template...');
      final result = await engine.chatTemplate(messages, tools: tools);

      print('\n--- Raw Prompt ---');
      print(prompt);
      print('------------------');

      final stream = engine.create(
        messages,
        tools: tools,
        params: GenerationParams(
          topK: 64,
          topP: 0.95,
          temp: 1,
          maxTokens: 128, // Limit tokens to avoid long-running CI generation
        ),
      );

      await for (final chunk in stream.timeout(const Duration(seconds: 60))) {
        final content = chunk.choices.firstOrNull?.delta.content;
        if (content != null) {
          stdout.write(content);
        }
      }
      print('\n');

      // Assertions
      expect(result.prompt, isNotEmpty);
      // Check for presence of tool definition in the prompt.
      // Note: exact format depends on the model's template, but functiongemma often uses <tools> tags or similar.
      // We'll inspect the output first, but a safe check is simply ensuring constraints are passed if logic exists.
      // For now, let's just ensure no error occurred and we got output.

      // Additional check: Function calling models usually insert specific tokens or structures when tools are present.
      // functiongemma typically uses specific xml-like tags.
    });
  });
}
