import 'dart:io';

import 'package:llamadart_basic_example/models.dart';
import 'package:llamadart_basic_example/services/model_service.dart';
import 'package:test/test.dart';

void main() {
  group('CliMessage', () {
    test('stores role and text', () {
      final message = CliMessage(text: 'hello', role: CliRole.user);

      expect(message.text, equals('hello'));
      expect(message.role, equals(CliRole.user));
    });
  });

  group('ModelService', () {
    late Directory tempDir;
    late ModelService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('basic_app_test_');
      service = ModelService(tempDir.path);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns file when local path exists', () async {
      final modelFile = File('${tempDir.path}/model.gguf');
      await modelFile.writeAsString('dummy-model');

      final result = await service.ensureModel(modelFile.path);

      expect(result.path, equals(modelFile.path));
      expect(result.existsSync(), isTrue);
    });

    test('throws when local path does not exist', () async {
      final missingPath = '${tempDir.path}/missing.gguf';

      await expectLater(service.ensureModel(missingPath), throwsException);
    });
  });
}
