@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:test/test.dart';
import 'package:llamadart/src/backends/wllama/wllama_backend.dart';
import 'package:llamadart/src/backends/wllama/interop.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  group('WebLlamaBackend Unit', () {
    late WebLlamaBackend backend;
    late JSObject mockJs;

    setUp(() {
      mockJs = JSObject();

      mockJs.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSAny? config) {
          return Future.value(null).toJS;
        }).toJS,
      );

      // WebLlamaBackend now expects getModelMetadata to be synchronous returning JSObject
      mockJs.setProperty(
        'getModelMetadata'.toJS,
        (([String? key]) {
          final meta = JSObject();
          meta.setProperty('general.architecture'.toJS, 'llama'.toJS);
          meta.setProperty('n_ctx'.toJS, '2048'.toJS);
          meta.setProperty('tokenizer.chat_template'.toJS, 'im_end'.toJS);
          return meta;
        }).toJS,
      );

      mockJs.setProperty(
        'tokenize'.toJS,
        ((String text) {
          final arr = JSUint32Array.withLength(3);
          arr.toDart[0] = 1;
          arr.toDart[1] = 2;
          arr.toDart[2] = 3;
          return Future.value(arr).toJS;
        }).toJS,
      );

      mockJs.setProperty(
        'detokenize'.toJS,
        ((JSArray tokens) {
          return Future.value('decoded'.toJS).toJS;
        }).toJS,
      );

      mockJs.setProperty(
        'exit'.toJS,
        (() {
          return Future.value(null).toJS;
        }).toJS,
      );

      mockJs.setProperty('isMultithread'.toJS, (() => true).toJS);

      mockJs.setProperty(
        'formatChat'.toJS,
        ((JSArray messages, bool addAssistant, [String? tmpl]) {
          return Future.value('templated prompt'.toJS).toJS;
        }).toJS,
      );

      final utils = JSObject();
      utils.setProperty(
        'chatTemplate'.toJS,
        ((JSArray messages, [String? tmpl]) {
          return Future.value('templated prompt'.toJS).toJS;
        }).toJS,
      );
      mockJs.setProperty('utils'.toJS, utils);

      backend = WebLlamaBackend(
        wllamaFactory: (pathConfig, [config]) => mockJs as Wllama,
      );
    });

    tearDown(() async {
      await backend.dispose();
    });

    test('handle missing metadata gracefully', () async {
      mockJs.setProperty(
        'getModelMetadata'.toJS,
        (([String? key]) => null).toJS,
      );

      // Should not throw
      final meta = await backend.modelMetadata(1);
      expect(meta, isEmpty);
    });


    test('generate with mock', () async {
      mockJs.setProperty(
        'createCompletion'.toJS,
        ((String prompt, JSObject opts) {
          // Mock progress
          final onNewToken = opts.getProperty('onNewToken'.toJS) as JSFunction?;
          if (onNewToken != null) {
            final piece = JSUint8Array.withLength(5);
            piece.toDart.setAll(0, [72, 101, 108, 108, 111]); // "Hello"
            onNewToken.callAsFunction(null, null, piece, 'Hello'.toJS, null);
          }
          return Future.value('done'.toJS).toJS;
        }).toJS,
      );

      await backend.modelLoad('http://mock/model.gguf', const ModelParams());
      final stream = backend.generate(1, 'prompt', const GenerationParams());
      final result = await stream.toList();
      expect(result, isNotEmpty);
      expect(result.first, [72, 101, 108, 108, 111]);
    });

    test('supportsUrlLoading is true', () {
      expect(backend.supportsUrlLoading, isTrue);
    });

    test('getBackendName includes threading info', () async {
      await backend.modelLoad('http://mock/model.gguf', const ModelParams());
      final name = await backend.getBackendName();
      expect(name, contains('Multi-thread'));
    });

    test('getContextSize returns last nCtx', () async {
      await backend.modelLoad('url', const ModelParams(contextSize: 4096));
      final size = await backend.getContextSize(1);
      expect(size, 4096);
    });

    test('multiple model loads cleans up previous instance', () async {
      int exitCalls = 0;
      mockJs.setProperty(
        'exit'.toJS,
        (() {
          exitCalls++;
          return Future.value(null).toJS;
        }).toJS,
      );

      await backend.modelLoad('http://mock/model1.gguf', const ModelParams());
      expect(
        exitCalls,
        0,
      ); // First load doesn't call exit if no previous _wllama

      await backend.modelLoad('http://mock/model2.gguf', const ModelParams());
      expect(exitCalls, 1); // Second load calls exit on previous instance
    });
  });
}
