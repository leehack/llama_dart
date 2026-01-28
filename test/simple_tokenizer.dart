import 'dart:io';
import 'package:llamadart/llamadart.dart';

void main() async {
  final service = LlamaService();
  final modelPath = 'models/stories15M.gguf';

  if (!File(modelPath).existsSync()) {
    print(
        'Model not found at $modelPath. Run dart tool/download_model.dart first.');
    exit(1);
  }

  try {
    print('Initializing service...');
    await service.init(modelPath);
    print('Service initialized.');

    final text = "Hello world! This is a test.";
    print('Text to tokenize: "$text"');

    final tokens = await service.tokenize(text);
    print('Tokens: $tokens');

    if (tokens.isEmpty) {
      print('Error: Token list is empty.');
      exit(1);
    }

    final detokenized = await service.detokenize(tokens);
    print('Detokenized text: "$detokenized"');

    // Note: Detokenized text usually contains the special BOS token if tokenize added it.
    // Llama 2/3 usually adds BOS.
    // Let's check if the original text is contained in the detokenized text.
    if (detokenized.contains(text)) {
      print('SUCCESS: Detokenized text contains original text.');
    } else {
      print('FAILURE: Detokenized text does not match.');
      print('Original: "$text"');
      print('Result:   "$detokenized"');
      exit(1);
    }
  } catch (e) {
    print('Error: $e');
    exit(1);
  } finally {
    service.dispose();
  }
}
