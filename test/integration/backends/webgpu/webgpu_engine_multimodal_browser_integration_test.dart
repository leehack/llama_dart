@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/interop.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';

void main() {
  group('WebGPU multimodal engine integration', () {
    late JSObject bridge;
    late WebGpuLlamaBackend backend;
    late LlamaEngine engine;
    late bool mmLoaded;
    late bool sawAudioPart;

    setUp(() {
      bridge = JSObject();
      mmLoaded = false;
      sawAudioPart = false;

      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          return Future<void>.value().toJS;
        }).toJS,
      );

      bridge.setProperty(
        'createCompletion'.toJS,
        ((String prompt, JSObject opts) {
          final parts = opts.getProperty('parts'.toJS);
          if (parts.isA<JSArray>() && (parts as JSArray).length > 0) {
            for (int i = 0; i < parts.length; i++) {
              final rawPart = parts.getProperty(i.toJS);
              if (!rawPart.isA<JSObject>()) {
                continue;
              }

              final part = rawPart as JSObject;
              final type = part.getProperty('type'.toJS);
              if (type.isA<JSString>() &&
                  (type as JSString).toDart == 'audio') {
                sawAudioPart = true;
              }
            }
          }

          final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
          if (onToken != null) {
            final piece = JSUint8Array.withLength(5);
            piece.toDart.setAll(0, <int>[72, 101, 108, 108, 111]);
            onToken.callAsFunction(null, piece, 'Hello'.toJS);
          }

          return Future<void>.value().toJS;
        }).toJS,
      );

      bridge.setProperty(
        'loadMultimodalProjector'.toJS,
        ((String path) {
          mmLoaded = true;
          return Future<JSNumber>.value(1.toJS).toJS;
        }).toJS,
      );
      bridge.setProperty(
        'unloadMultimodalProjector'.toJS,
        (() {
          mmLoaded = false;
          return Future<void>.value().toJS;
        }).toJS,
      );
      bridge.setProperty('supportsVision'.toJS, (() => false).toJS);
      bridge.setProperty('supportsAudio'.toJS, (() => mmLoaded).toJS);

      bridge.setProperty(
        'tokenize'.toJS,
        ((String text, bool addSpecial) {
          final arr = JSUint32Array.withLength(3);
          arr.toDart[0] = 1;
          arr.toDart[1] = 2;
          arr.toDart[2] = 3;
          return Future<JSUint32Array>.value(arr).toJS;
        }).toJS,
      );

      bridge.setProperty(
        'detokenize'.toJS,
        ((JSArray tokens, bool special) {
          return Future<JSString>.value('decoded'.toJS).toJS;
        }).toJS,
      );

      bridge.setProperty(
        'getModelMetadata'.toJS,
        (() {
          final meta = JSObject();
          meta.setProperty('general.architecture'.toJS, 'llama'.toJS);
          return meta;
        }).toJS,
      );

      bridge.setProperty('getContextSize'.toJS, (() => 1024).toJS);
      bridge.setProperty('isGpuActive'.toJS, (() => true).toJS);
      bridge.setProperty('getBackendName'.toJS, (() => 'WebGPU (Mock)').toJS);
      bridge.setProperty('cancel'.toJS, (() {}).toJS);
      bridge.setProperty(
        'dispose'.toJS,
        (() {
          return Future<void>.value().toJS;
        }).toJS,
      );
      bridge.setProperty(
        'applyChatTemplate'.toJS,
        ((JSArray messages, bool addAssistant, String? customTemplate) {
          return Future<JSString>.value('templated'.toJS).toJS;
        }).toJS,
      );

      backend = WebGpuLlamaBackend(
        bridgeFactory: ([config]) => bridge as LlamaWebGpuBridge,
      );
      engine = LlamaEngine(backend);
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('LlamaEngine create forwards multimodal audio parts', () async {
      await engine.loadModelFromUrl(
        'https://example.com/model.gguf',
        modelParams: const ModelParams(contextSize: 1024),
      );
      await engine.loadMultimodalProjector('https://example.com/mmproj.gguf');

      expect(await engine.supportsAudio, isTrue);
      expect(await engine.supportsVision, isFalse);

      final chunks = await engine.create(<LlamaChatMessage>[
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: <LlamaContentPart>[
            const LlamaTextContent('Transcribe this audio.'),
            LlamaAudioContent(
              samples: Float32List.fromList(<double>[0.1, -0.2, 0.3]),
            ),
          ],
        ),
      ], params: const GenerationParams(maxTokens: 8)).toList();

      final output = chunks
          .map((chunk) => chunk.choices.first.delta.content ?? '')
          .join();

      expect(output, contains('Hello'));
      expect(sawAudioPart, isTrue);
    });
  });
}
