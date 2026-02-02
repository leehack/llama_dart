import 'dart:io';
import 'package:args/args.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_basic_example/services/model_service.dart';

const defaultModelUrl =
    'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('model',
        abbr: 'm',
        help: 'Path or URL to the GGUF model file.',
        defaultsTo: defaultModelUrl)
    ..addOption('text',
        abbr: 't',
        help: 'Text to get embeddings for.',
        defaultsTo: 'Hello, world!')
    ..addOption('pooling',
        abbr: 'p',
        help: 'Pooling type (1=MEAN, 2=CLS, 3=LAST)',
        defaultsTo: '1')
    ..addFlag('help',
        abbr: 'h', help: 'Show this help message.', negatable: false);

  final results = parser.parse(arguments);

  if (results['help'] as bool) {
    print('🦙 llamadart Embeddings Example\n');
    print(parser.usage);
    return;
  }

  final modelUrlOrPath = results['model'] as String;
  final text = results['text'] as String;
  final poolingType = int.parse(results['pooling'] as String);

  final modelService = ModelService();
  final engine = LlamaEngine(LlamaBackend());

  try {
    print('Checking model...');
    final modelFile = await modelService.ensureModel(modelUrlOrPath);

    print('Loading model with embeddings enabled...');
    await engine.loadModel(
      modelFile.path,
      modelParams: ModelParams(
        enableEmbeddings: true,
        poolingType: poolingType,
        logLevel: LlamaLogLevel.none,
      ),
    );
    print('Model loaded successfully.\n');

    print('Getting embeddings for: "$text"');
    final embeddings = await engine.getEmbeddings(text);

    print('\nEmbeddings dimension: ${embeddings.length}');
    print('First 10 values: ${embeddings.take(10).toList()}');

    // Calculate L2 norm for demonstration
    final norm = _l2Norm(embeddings);
    print('L2 norm: ${norm.toStringAsFixed(4)}');
  } catch (e) {
    print('\nError: $e');
  } finally {
    await engine.dispose();
    exit(0);
  }
}

double _l2Norm(List<double> vector) {
  double sum = 0.0;
  for (final value in vector) {
    sum += value * value;
  }
  return sum > 0 ? 1.0 / (1.0 + sum) : 0.0;
}
