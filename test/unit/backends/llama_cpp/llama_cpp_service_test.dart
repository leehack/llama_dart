@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('LlamaCppService can be instantiated', () {
    final service = LlamaCppService();
    expect(service, isA<LlamaCppService>());
  });

  group('resolveGpuLayersForLoad', () {
    test('forces CPU mode to zero gpu layers', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.cpu,
      );

      expect(LlamaCppService.resolveGpuLayersForLoad(params), 0);
    });

    test('preserves configured gpu layers for non-CPU backends', () {
      const params = ModelParams(
        gpuLayers: 42,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(LlamaCppService.resolveGpuLayersForLoad(params), 42);
    });
  });

  group('parseBackendModuleDirectoryFromProcMaps', () {
    test('extracts lib directory from standard maps entry', () {
      const maps = '''
7f8a0000-7f8b0000 r-xp 00000000 103:04 12345 /data/app/~~pkg/lib/arm64/libllamadart.so
''';

      expect(
        LlamaCppService.parseBackendModuleDirectoryFromProcMaps(maps),
        '/data/app/~~pkg/lib/arm64',
      );
    });

    test('handles deleted mapping suffix', () {
      const maps = '''
7f8a0000-7f8b0000 r-xp 00000000 103:04 12345 /tmp/libllamadart.so (deleted)
''';

      expect(
        LlamaCppService.parseBackendModuleDirectoryFromProcMaps(maps),
        '/tmp',
      );
    });

    test('returns null when libllamadart mapping is missing', () {
      const maps = '''
7f8a0000-7f8b0000 r-xp 00000000 103:04 12345 /system/lib64/libc.so
''';

      expect(
        LlamaCppService.parseBackendModuleDirectoryFromProcMaps(maps),
        isNull,
      );
    });
  });

  group('resolveWindowsBackendModuleDirectory', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync(
        'llamadart-windows-modules-',
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('uses explicit environment override when valid', () {
      final overrideDir = Directory(path.join(tempRoot.path, 'override'))
        ..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(overrideDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(tempRoot.path, 'dart.exe'),
        currentDirectoryPath: tempRoot.path,
        environment: {'LLAMADART_NATIVE_LIB_DIR': overrideDir.path},
      );

      expect(path.normalize(resolved!), path.normalize(overrideDir.path));
    });

    test('falls back to hook cache extracted bundle directory', () {
      final extractedDir = Directory(
        path.join(
          tempRoot.path,
          '.dart_tool',
          'llamadart',
          'native_bundles',
          'b8095',
          'windows-x64',
          'extracted',
        ),
      )..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(extractedDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(
          tempRoot.path,
          'dart-sdk',
          'dart.exe',
        ),
        currentDirectoryPath: tempRoot.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(extractedDir.path));
    });
  });
}

void _createWindowsBundleMarkerFiles(String directoryPath) {
  final markerFiles = <String>['llama.dll', 'ggml.dll', 'ggml-cpu.dll'];
  for (final fileName in markerFiles) {
    File(path.join(directoryPath, fileName)).writeAsStringSync('');
  }
}
