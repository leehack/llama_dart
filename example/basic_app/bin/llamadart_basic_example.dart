import 'dart:io';
import 'package:args/args.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_basic_example/services/model_service.dart';
import 'package:llamadart_basic_example/services/llama_service.dart';

const defaultModelUrl =
    'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('model',
        abbr: 'm',
        help: 'Path or URL to the GGUF model file.',
        defaultsTo: defaultModelUrl)
    ..addMultiOption('lora',
        abbr: 'l',
        help: 'Path to LoRA adapter(s). Can be specified multiple times.')
    ..addOption('prompt', abbr: 'p', help: 'Prompt for single response mode.')
    ..addFlag('interactive',
        abbr: 'i',
        help: 'Start in interactive conversation mode.',
        defaultsTo: true)
    ..addFlag('log',
        abbr: 'g',
        help: 'Enable native engine logging output.',
        defaultsTo: false)
    ..addOption('grammar',
        abbr: 'G',
        help: 'GBNF grammar string for structured output.\n'
            'Example: "root ::= [0-9]+" (only numbers)\n'
            'Example: "root ::= \\"yes\\" | \\"no\\"" (binary choice)')
    ..addFlag('tool-test',
        abbr: 't',
        help: 'Enable a sample "get_weather" tool for testing tool calls.',
        defaultsTo: false)
    ..addOption('temp',
        help: 'Generation temperature (default: 0.8)', defaultsTo: '0.8')
    ..addOption('top-k', help: 'Top-k sampling (default: 40)', defaultsTo: '40')
    ..addOption('top-p',
        help: 'Top-p sampling (default: 0.95)', defaultsTo: '0.95')
    ..addOption('penalty',
        help: 'Repeat penalty (default: 1.1)', defaultsTo: '1.1')
    ..addFlag('help',
        abbr: 'h', help: 'Show this help message.', negatable: false);

  final results = parser.parse(arguments);

  if (results['help'] as bool) {
    print('🦙 llamadart CLI Chat\n');
    print(parser.usage);
    print('\nUsage Examples:');
    print('  - Structured Numbers: -G \'root ::= [0-9]+\'');
    print('  - Binary Choice:      -G \'root ::= "yes" | "no"\'');
    print(
        '  - List of colors:    -G \'root ::= ("red" | "green" | "blue") (", " ("red" | "green" | "blue"))*\'');
    return;
  }

  final modelUrlOrPath = results['model'] as String;
  final singlePrompt = results['prompt'] as String?;
  final grammar = results['grammar'] as String?;
  final enableToolTest = results['tool-test'] as bool;
  final isInteractive = results['interactive'] as bool && singlePrompt == null;

  final modelService = ModelService();
  final llamaService = LlamaCliService();

  // Define sample tools using the typed ToolRegistry API
  final toolRegistry = enableToolTest
      ? ToolRegistry([
          ToolDefinition(
            name: 'get_weather',
            description: 'Get the current weather for a location.',
            parameters: [
              ToolParam.string(
                'location',
                description: 'The city and state, e.g. San Francisco, CA',
                required: true,
              ),
              ToolParam.enumType(
                'unit',
                values: ['celsius', 'fahrenheit'],
                description: 'The unit of temperature',
              ),
            ],
            handler: (params) async {
              final location = params.getRequiredString('location');
              final unit = params.getString('unit') ?? 'celsius';
              // Mock weather response
              final temp = 22;
              final unitSymbol = unit == 'fahrenheit' ? '°F' : '°C';
              return 'The weather in $location is $temp$unitSymbol and Sunny.';
            },
          ),
        ])
      : null;

  try {
    print('Checking model...');
    final modelFile = await modelService.ensureModel(modelUrlOrPath);

    final loraPaths = results['lora'] as List<String>;
    final loras = loraPaths.map((p) => LoraAdapterConfig(path: p)).toList();
    final enableLog = results['log'] as bool;

    print('Initializing engine...');
    await llamaService.init(
      modelFile.path,
      loras: loras,
      logLevel: enableLog ? LlamaLogLevel.info : LlamaLogLevel.none,
      toolRegistry: toolRegistry,
    );
    print('Model loaded successfully.\n');

    if (enableToolTest) {
      print(
          '🛠️ Tool test enabled. The model will be forced to use the "get_weather" tool.');
    }

    if (grammar != null) {
      print('📜 Using custom grammar: $grammar');
    }

    final generationParams = GenerationParams(
      grammar: grammar,
      temp: double.tryParse(results['temp'] as String) ?? 0.8,
      topK: int.tryParse(results['top-k'] as String) ?? 40,
      topP: double.tryParse(results['top-p'] as String) ?? 0.95,
      penalty: double.tryParse(results['penalty'] as String) ?? 1.1,
    );

    if (singlePrompt != null) {
      await _runSingleResponse(llamaService, singlePrompt, generationParams);
    } else if (isInteractive) {
      await _runInteractiveMode(llamaService, generationParams);
    }
  } catch (e) {
    print('\nError: $e');
  } finally {
    // CRITICAL: Always dispose resources to prevent memory leaks and native process hangs
    await llamaService.dispose();
    exit(0);
  }
}

Future<void> _runSingleResponse(
  LlamaCliService service,
  String prompt,
  GenerationParams params,
) async {
  stdout.write('\nAssistant: ');
  await for (final token in service.chatStream(prompt, params: params)) {
    stdout.write(token);
  }
  print('\n');
}

Future<void> _runInteractiveMode(
  LlamaCliService service,
  GenerationParams params,
) async {
  print('Starting interactive mode. Type "exit" or "quit" to stop.\n');

  while (true) {
    stdout.write('User: ');
    final input = stdin.readLineSync();

    if (input == null ||
        input.toLowerCase() == 'exit' ||
        input.toLowerCase() == 'quit') {
      break;
    }

    stdout.write('Assistant: ');
    await for (final token in service.chatStream(input, params: params)) {
      stdout.write(token);
    }
    print('\n');
  }
}
