import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:test/test.dart';

void main() {
  test('GenerationParams copyWith updates selected fields', () {
    const params = GenerationParams(temp: 0.5, maxTokens: 10);
    final updated = params.copyWith(topK: 12, grammarRoot: 'main');

    expect(updated.temp, 0.5);
    expect(updated.maxTokens, 10);
    expect(updated.topK, 12);
    expect(updated.grammarRoot, 'main');
  });
}
