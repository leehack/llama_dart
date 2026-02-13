@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/interop.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';

void main() {
  group('WebGpuLlamaBackend Unit', () {
    late JSObject bridge;
    late WebGpuLlamaBackend backend;
    late bool mmLoaded;
    late bool sawMediaParts;
    late bool sawAudioParts;
    late bool sawAudioBytes;

    setUp(() {
      bridge = JSObject();
      mmLoaded = false;
      sawMediaParts = false;
      sawAudioParts = false;
      sawAudioBytes = false;

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
            sawMediaParts = true;

            for (int i = 0; i < parts.length; i++) {
              final rawPart = parts.getProperty(i.toJS);
              if (!rawPart.isA<JSObject>()) {
                continue;
              }

              final part = rawPart as JSObject;
              final type = part.getProperty('type'.toJS);
              if (type.isA<JSString>() &&
                  (type as JSString).toDart == 'audio') {
                sawAudioParts = true;

                final bytes = part.getProperty('bytes'.toJS);
                if (bytes.isA<JSUint8Array>() &&
                    (bytes as JSUint8Array).toDart.isNotEmpty) {
                  sawAudioBytes = true;
                }
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
      bridge.setProperty('supportsVision'.toJS, (() => mmLoaded).toJS);
      bridge.setProperty('supportsAudio'.toJS, (() => false).toJS);

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

      bridge.setProperty('getContextSize'.toJS, (() => 4096).toJS);
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
    });

    tearDown(() async {
      await backend.dispose();
    });

    test('uses bridge when available', () async {
      final modelHandle = await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(contextSize: 4096),
      );

      expect(modelHandle, 1);
      expect(await backend.getBackendName(), 'WebGPU (Mock)');
      expect(await backend.isGpuSupported(), isTrue);
      expect(await backend.getContextSize(1), 4096);
    });

    test('streams generated tokens from bridge callback', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final chunks = await backend
          .generate(1, 'Hello', const GenerationParams())
          .toList();

      expect(chunks, isNotEmpty);
      expect(chunks.first, <int>[72, 101, 108, 108, 111]);
    });

    test('suppresses stop sequence text from streamed output', () async {
      bridge.setProperty(
        'createCompletion'.toJS,
        ((String prompt, JSObject opts) {
          final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
          if (onToken != null) {
            final firstPiece = JSUint8Array.withLength(2);
            firstPiece.toDart.setAll(0, <int>[104, 105]);
            onToken.callAsFunction(null, firstPiece, 'hi'.toJS);

            final stopBytes = '<|im_end|>\n'.codeUnits;
            final secondPiece = JSUint8Array.withLength(stopBytes.length);
            secondPiece.toDart.setAll(0, stopBytes);
            onToken.callAsFunction(null, secondPiece, 'hi<|im_end|>\n'.toJS);
          }
          return Future<void>.value().toJS;
        }).toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final chunks = await backend
          .generate(
            1,
            'Hello',
            const GenerationParams(stopSequences: <String>['<|im_end|>']),
          )
          .toList();

      final output = utf8.decode(chunks.expand((b) => b).toList());
      expect(output, 'hi');
      expect(output.contains('<|im_end|>'), isFalse);
    });

    test('throws when bridge load fails', () async {
      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          return Future<void>.error(Exception('bridge load failed')).toJS;
        }).toJS,
      );

      await expectLater(
        () => backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        ),
        throwsA(anything),
      );
      expect(await backend.getBackendName(), contains('not loaded'));
    });

    test('throws on multimodal prompt parts before projector load', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      expect(
        () => backend.generate(
          1,
          'Describe this image',
          const GenerationParams(),
          parts: <LlamaContentPart>[
            LlamaImageContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('creates and uses multimodal context with media parts', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final mmHandle = await backend.multimodalContextCreate(
        1,
        'https://example.com/mmproj.gguf',
      );

      expect(mmHandle, 1);
      expect(await backend.supportsVision(mmHandle!), isTrue);
      expect(await backend.supportsAudio(mmHandle), isFalse);

      final chunks = await backend
          .generate(
            1,
            'Describe this image',
            const GenerationParams(),
            parts: <LlamaContentPart>[
              LlamaImageContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
            ],
          )
          .toList();

      expect(chunks, isNotEmpty);
      expect(sawMediaParts, isTrue);
      expect(mmLoaded, isTrue);

      await backend.multimodalContextFree(mmHandle);
      expect(mmLoaded, isFalse);
      expect(await backend.supportsVision(mmHandle), isFalse);
    });

    test('reports audio support and forwards audio parts', () async {
      bridge.setProperty('supportsAudio'.toJS, (() => mmLoaded).toJS);

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final mmHandle = await backend.multimodalContextCreate(
        1,
        'https://example.com/mmproj.gguf',
      );

      expect(mmHandle, isNotNull);
      expect(await backend.supportsAudio(mmHandle!), isTrue);

      final chunks = await backend
          .generate(
            1,
            'Transcribe this audio',
            const GenerationParams(),
            parts: <LlamaContentPart>[
              LlamaAudioContent(
                samples: Float32List.fromList(<double>[0.1, -0.2, 0.3]),
              ),
            ],
          )
          .toList();

      expect(chunks, isNotEmpty);
      expect(sawAudioParts, isTrue);
    });

    test('forwards encoded audio bytes parts', () async {
      bridge.setProperty('supportsAudio'.toJS, (() => mmLoaded).toJS);

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final mmHandle = await backend.multimodalContextCreate(
        1,
        'https://example.com/mmproj.gguf',
      );

      expect(mmHandle, isNotNull);
      expect(await backend.supportsAudio(mmHandle!), isTrue);

      final chunks = await backend
          .generate(
            1,
            'Transcribe this audio',
            const GenerationParams(),
            parts: <LlamaContentPart>[
              LlamaAudioContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
            ],
          )
          .toList();

      expect(chunks, isNotEmpty);
      expect(sawAudioParts, isTrue);
      expect(sawAudioBytes, isTrue);
    });
  });
}
