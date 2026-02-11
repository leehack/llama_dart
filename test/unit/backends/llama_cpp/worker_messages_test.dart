@TestOn('vm')
library;

import 'dart:isolate';
import 'package:test/test.dart';
import 'package:llamadart/src/backends/llama_cpp/worker_messages.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  final rp = ReceivePort();
  final sp = rp.sendPort;

  group('WorkerMessages', () {
    test('ModelLoadRequest', () {
      final req = ModelLoadRequest('path', const ModelParams(), sp);
      expect(req.modelPath, 'path');
      expect(req.sendPort, sp);
    });

    test('ModelFreeRequest', () {
      final req = ModelFreeRequest(1, sp);
      expect(req.modelHandle, 1);
    });

    test('ContextCreateRequest', () {
      final req = ContextCreateRequest(1, const ModelParams(), sp);
      expect(req.modelHandle, 1);
    });

    test('ContextFreeRequest', () {
      final req = ContextFreeRequest(1, sp);
      expect(req.contextHandle, 1);
    });

    test('GenerateRequest', () {
      final req = GenerateRequest(
        1,
        'prompt',
        const GenerationParams(),
        0,
        sp,
        parts: [],
      );
      expect(req.prompt, 'prompt');
      expect(req.parts, isEmpty);
    });

    test('TokenizeRequest', () {
      final req = TokenizeRequest(1, 'text', true, sp);
      expect(req.text, 'text');
      expect(req.addSpecial, true);
    });

    test('DetokenizeRequest', () {
      final req = DetokenizeRequest(1, [1, 2], false, sp);
      expect(req.tokens, [1, 2]);
      expect(req.special, false);
    });

    test('MetadataRequest', () {
      final req = MetadataRequest(1, sp);
      expect(req.modelHandle, 1);
    });

    test('LoraRequest', () {
      final req = LoraRequest(1, 'set', path: 'p', scale: 1.0, sendPort: sp);
      expect(req.op, 'set');
      expect(req.path, 'p');
      expect(req.scale, 1.0);
    });

    test('BackendInfoRequest', () {
      final req = BackendInfoRequest(sp);
      expect(req.sendPort, sp);
    });

    test('GpuSupportRequest', () {
      final req = GpuSupportRequest(sp);
      expect(req.sendPort, sp);
    });

    test('DisposeRequest', () {
      final req = DisposeRequest(sp);
      expect(req.sendPort, sp);
    });

    test('LogLevelRequest', () {
      final req = LogLevelRequest(LlamaLogLevel.info, sp);
      expect(req.logLevel, LlamaLogLevel.info);
    });

    test('GetContextSizeRequest', () {
      final req = GetContextSizeRequest(1, sp);
      expect(req.contextHandle, 1);
    });

    test('MultimodalContextCreateRequest', () {
      final req = MultimodalContextCreateRequest(1, 'proj', sp);
      expect(req.modelHandle, 1);
      expect(req.mmProjPath, 'proj');
    });

    test('MultimodalContextFreeRequest', () {
      final req = MultimodalContextFreeRequest(1, sp);
      expect(req.mmContextHandle, 1);
    });

    test('SupportsVisionRequest', () {
      final req = SupportsVisionRequest(1, sp);
      expect(req.mmContextHandle, 1);
    });

    test('SupportsAudioRequest', () {
      final req = SupportsAudioRequest(1, sp);
      expect(req.mmContextHandle, 1);
    });

    test('Responses', () {
      expect(HandleResponse(1).handle, 1);
      expect(TokenResponse([1]).bytes, [1]);
      expect(TokenizeResponse([1]).tokens, [1]);
      expect(DetokenizeResponse('t').text, 't');
      expect(MetadataResponse({'a': 'b'}).metadata, {'a': 'b'});
      expect(GetContextSizeResponse(10).size, 10);
      expect(ErrorResponse('e').message, 'e');
      expect(BackendInfoResponse('n').name, 'n');
      expect(GpuSupportResponse(true).support, true);
      expect(
        WorkerHandshake(LlamaLogLevel.debug).initialLogLevel,
        LlamaLogLevel.debug,
      );
      expect(DoneResponse(), isNotNull);
    });
  });

  // Close the port to avoid hanging
  rp.close();
}
