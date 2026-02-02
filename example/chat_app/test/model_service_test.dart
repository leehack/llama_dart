import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart_chat_example/models/downloadable_model.dart';
import 'package:llamadart_chat_example/services/model_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late HttpServer server;
  late String baseUrl;
  late ModelService service;
  late List<int> testData;

  const int testDataSize = 1024 * 1024 * 5; // 5 MB

  setUp(() async {
    // Generate random test data
    testData = List.generate(testDataSize, (i) => i % 256);
    tempDir = await Directory.systemTemp.createTemp('model_service_test');
    service = TestModelService(tempDir);

    // Start local server
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';

    server.listen((HttpRequest request) async {
      final path = request.uri.path;
      if (path == '/model.gguf') {
        if (request.method == 'HEAD') {
          request.response.headers.contentLength = testDataSize;
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
        } else if (request.method == 'GET') {
          final rangeHeader = request.headers.value('range');
          int start = 0;
          int end = testDataSize - 1;

          if (rangeHeader != null) {
            final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(rangeHeader);
            if (match != null) {
              start = int.parse(match.group(1)!);
              end = int.parse(match.group(2)!);
            }
          }

          if (start >= testDataSize) {
            request.response.statusCode =
                HttpStatus.requestedRangeNotSatisfiable;
            await request.response.close();
            return;
          }

          // Check if client disconnected, though difficult to detect reliably in dart:io instantly
          // We will just stream
          request.response.headers.contentLength = end - start + 1;
          request.response.headers.set(
            'Content-Range',
            'bytes $start-$end/$testDataSize',
          );
          request.response.statusCode = HttpStatus.partialContent;

          // Stream the data
          final stream = Stream.fromIterable([
            testData.sublist(start, end + 1),
          ]);
          await request.response.addStream(stream);
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Full download works correctly', () async {
    final model = DownloadableModel(
      name: 'Test Model',
      description: 'Test',
      url: '$baseUrl/model.gguf',
      filename: 'model.gguf',
      sizeBytes: testDataSize,
    );

    await service.downloadModel(
      model: model,
      modelsDir: tempDir.path,
      onProgress: (p) {},
      onSuccess: (path) {},
      onError: (e) => fail('Download failed: $e'),
    );

    final file = File(p.join(tempDir.path, 'model.gguf'));
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), testDataSize);
    expect(file.readAsBytesSync(), testData);
  });

  test('Resume functionality works', () async {
    final model = DownloadableModel(
      name: 'Test Model',
      description: 'Test',
      url: '$baseUrl/model.gguf',
      filename: 'model.gguf',
      sizeBytes: testDataSize, // 5MB
    );

    // 1. Start download but cancel it halfway
    // We simulate this by throwing an error inside onProgress or interrupting
    // Since we can't easily interrupt the Future from outside without cancellation token support (which we didn't implement fully exposed),
    // we will rely on a trick: we will close the server or similar? No, ModelService catches errors.
    // Actually, we can hack the service to accept a cancellation token or just rely on the fact that if we throw in onProgress, it might propagate?
    // Wait, onProgress is a callback. If we throw there, `_downloadFileParallel` calls `onProgress`. It might not catch it if it's sync.
    // Let's modify ModelService to panic in onProgress if we want to simulate crash.

    bool simulatedCrash = false;
    try {
      await service.downloadModel(
        model: model,
        modelsDir: tempDir.path,
        onProgress: (val) {
          if (val > 0.3 && !simulatedCrash) {
            simulatedCrash = true;
            throw Exception("Simulated Crash");
          }
        },
        onSuccess: (_) {},
        onError: (e) {
          // Expected to fail here
        },
      );
    } catch (_) {}

    // Verify partial state
    final file = File(p.join(tempDir.path, 'model.gguf'));
    final meta = File(p.join(tempDir.path, 'model.gguf.meta'));

    expect(file.existsSync(), isTrue);
    expect(meta.existsSync(), isTrue);
    expect(file.lengthSync(), equals(testDataSize)); // Pre-allocated
    // We expect some parts to be missing (zeros) or just trust meta
    final metaContent = meta.readAsStringSync();
    expect(metaContent, contains(",")); // Basic csv check
    expect(simulatedCrash, isTrue);

    // 2. Resume download
    await service.downloadModel(
      model: model,
      modelsDir: tempDir.path,
      onProgress: (p) {},
      onSuccess: (path) {},
      onError: (e) => fail('Resume failed: $e'),
    );

    // Verify final state
    expect(file.lengthSync(), testDataSize);
    expect(file.readAsBytesSync(), testData);
    expect(meta.existsSync(), isFalse); // Should be cleaned up
  });

  test('Incomplete download is not marked as downloaded', () async {
    final model = DownloadableModel(
      name: 'Existing Model',
      description: 'Test',
      url: '$baseUrl/model.gguf',
      filename: 'existing.gguf',
      sizeBytes: testDataSize,
    );

    // Create fake partial file
    final file = File(p.join(tempDir.path, 'existing.gguf'));
    final meta = File(p.join(tempDir.path, 'existing.gguf.meta'));
    await file.create();
    await file.writeAsBytes(testData); // Full size
    await meta.create(); // Meta exists -> incomplete

    final downloaded = await service.getDownloadedModels([model]);
    expect(downloaded, isNot(contains(model.filename)));

    // valid without meta
    await meta.delete();
    await service.getDownloadedModels([model]);
    // Note: getDownloadedModels uses getApplicationDocumentsDirectory which is mocked/stubbed in flutter_test usually to a temp dir,
    // but in unit test it might default to something else or fail if not mocked.
    // Wait, ModelService uses getApplicationDocumentsDirectory.
    // In strict unit test without PathProviderPlatform mock, this fails.
    // However, we can inject the path or just override it?
    // ModelService.getModelsDirectory() calls getApplicationDocumentsDirectory().
    // We haven't mocked PathProvider in this integration test.
    // We should subclass ModelService or mock the method.
    // OR we can just use the fact that we can't easily test this without mocking.
    // Actually, let's just create a subclass of ModelService that overrides getModelsDirectory for testing.
  });
}

class TestModelService extends ModelService {
  final Directory testDir;
  TestModelService(this.testDir);

  @override
  Future<String> getModelsDirectory() async {
    return testDir.path;
  }
}
