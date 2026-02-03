import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  group('ModelParams', () {
    test('default values', () {
      const params = ModelParams();
      expect(params.contextSize, 0); // 0 means default/train
      expect(params.gpuLayers, 99);
      expect(params.logLevel, LlamaLogLevel.none);
      expect(params.preferredBackend, GpuBackend.auto);
    });

    test('copyWith', () {
      const params = ModelParams(contextSize: 1024);
      final updated = params.copyWith(
        gpuLayers: 10,
        logLevel: LlamaLogLevel.info,
        preferredBackend: GpuBackend.metal,
      );
      expect(updated.contextSize, 1024);
      expect(updated.gpuLayers, 10);
      expect(updated.logLevel, LlamaLogLevel.info);
      expect(updated.preferredBackend, GpuBackend.metal);
    });
  });

  group('GenerationParams', () {
    test('default values', () {
      const params = GenerationParams();
      expect(params.temp, 0.8);
      expect(params.topK, 40);
      expect(params.topP, 0.9);
      expect(params.maxTokens, 512);
      expect(params.stopSequences, isEmpty);
    });

    test('copyWith', () {
      const params = GenerationParams(temp: 0.5);
      final updated = params.copyWith(
        maxTokens: 50,
        stopSequences: ['</s>'],
        topP: 0.8,
      );
      expect(updated.temp, 0.5);
      expect(updated.maxTokens, 50);
      expect(updated.stopSequences, ['</s>']);
      expect(updated.topP, 0.8);
    });
  });

  group('LlamaChatMessage', () {
    test('properties', () {
      const msg = LlamaChatMessage(role: 'user', content: 'hello');
      expect(msg.role, LlamaChatRole.user);
      expect(msg.content, 'hello');
    });
  });

  group('LlamaChatTemplateResult', () {
    test('properties', () {
      const result = LlamaChatTemplateResult(
        prompt: 'formatted',
        stopSequences: ['stop'],
      );
      expect(result.prompt, 'formatted');
      expect(result.stopSequences, ['stop']);
    });
  });

  group('LoraAdapterConfig', () {
    test('properties', () {
      const config = LoraAdapterConfig(path: 'path', scale: 0.5);
      expect(config.path, 'path');
      expect(config.scale, 0.5);
    });
  });

  group('Enums', () {
    test('LlamaLogLevel values', () {
      expect(LlamaLogLevel.values, contains(LlamaLogLevel.debug));
      expect(LlamaLogLevel.values, contains(LlamaLogLevel.info));
      expect(LlamaLogLevel.values, contains(LlamaLogLevel.warn));
      expect(LlamaLogLevel.values, contains(LlamaLogLevel.error));
    });

    test('GpuBackend values', () {
      expect(GpuBackend.values, contains(GpuBackend.auto));
      expect(GpuBackend.values, contains(GpuBackend.metal));
    });
  });

  group('Exceptions', () {
    test('LlamaModelException', () {
      final ex = LlamaModelException('msg', 'original');
      expect(ex.message, 'msg');
      expect(ex.details, 'original');
      expect(ex.toString(), contains('LlamaException: msg (original)'));
    });

    test('LlamaContextException', () {
      final ex = LlamaContextException('msg');
      expect(ex.message, 'msg');
      expect(ex.toString(), contains('LlamaException: msg'));
    });
  });
}
