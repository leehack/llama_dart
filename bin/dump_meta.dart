import 'package:llamadart/llamadart.dart';

void main() async {
  final engine = LlamaEngine(LlamaBackend());
  await engine.loadModel('models/moondream2-q5k.gguf');
  final meta = await engine.getMetadata();
  print('Template: ${meta['tokenizer.chat_template']}');
  await engine.dispose();
}
