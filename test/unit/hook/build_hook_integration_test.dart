@TestOn('vm')
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../hook/build.dart' as build_hook;

void main() {
  final nativeTag = _readHookNativeTag();
  final bundleRelativePath =
      '.dart_tool/llamadart/native_bundles/$nativeTag/windows-arm64/extracted';
  final bundleDir = Directory(bundleRelativePath);
  final backupDir = Directory('$bundleRelativePath.__hook_test_backup');

  setUpAll(() async {
    if (backupDir.existsSync()) {
      await backupDir.delete(recursive: true);
    }

    if (bundleDir.existsSync()) {
      await bundleDir.rename(backupDir.path);
    }

    await bundleDir.create(recursive: true);

    for (final name in const [
      'llamadart-windows-arm64.dll',
      'llama-windows-arm64.dll',
      'ggml-windows-arm64.dll',
      'ggml-base-windows-arm64.dll',
      'ggml-vulkan-windows-arm64.dll',
      'ggml-blas-windows-arm64.dll',
    ]) {
      await File(path.join(bundleDir.path, name)).writeAsString('fake-$name');
    }
  });

  tearDownAll(() async {
    if (bundleDir.existsSync()) {
      await bundleDir.delete(recursive: true);
    }
    if (backupDir.existsSync()) {
      await backupDir.rename(bundleDir.path);
    }
  });

  test(
    'build hook selects configured backend modules and emits primary asset',
    () async {
      final userDefines = PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {
            'llamadart_native_backends': {
              'platforms': {
                'windows-arm64': ['blas'],
              },
            },
          },
          basePath: Directory.current.uri,
        ),
      );

      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.windows,
        targetArchitecture: Architecture.arm64,
        userDefines: userDefines,
        check: (input, output) {
          final codeAssets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset)
              .toList(growable: false);

          final codeAssetIds = codeAssets.map((asset) => asset.id).toSet();
          expect(codeAssetIds, contains('package:llamadart/llamadart'));

          final emittedNames = codeAssets
              .map((asset) => path.basename(asset.file!.toFilePath()))
              .toSet();

          expect(emittedNames, contains('ggml-blas-windows-arm64.dll'));
          expect(
            emittedNames,
            isNot(contains('ggml-vulkan-windows-arm64.dll')),
          );

          expect(emittedNames, contains('llamadart-windows-arm64.dll'));
          expect(emittedNames, contains('llama-windows-arm64.dll'));
          expect(emittedNames, contains('ggml-windows-arm64.dll'));
          expect(emittedNames, contains('ggml-base-windows-arm64.dll'));
        },
      );
    },
  );
}

String _readHookNativeTag() {
  final source = File('hook/build.dart').readAsStringSync();
  final match = RegExp(r"const _llamaCppTag = '([^']+)';").firstMatch(source);
  if (match == null) {
    throw StateError('Could not locate _llamaCppTag in hook/build.dart');
  }
  return match.group(1)!;
}
