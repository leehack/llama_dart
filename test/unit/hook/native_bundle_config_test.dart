@TestOn('vm')
library;

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../../../hook/src/native_bundle_config.dart';

void main() {
  group('resolveNativeBundleSpec', () {
    test('resolves android arm64 with cpu+vulkan defaults', () {
      final spec = resolveNativeBundleSpec(
        os: OS.android,
        arch: Architecture.arm64,
        isIosSimulator: false,
      );

      expect(spec, isNotNull);
      expect(spec!.bundle, 'android-arm64');
      expect(spec.configurableBackends, isTrue);
      expect(spec.defaultBackends, ['cpu', 'vulkan']);
    });

    test('resolves iOS x64 simulator as non-configurable', () {
      final spec = resolveNativeBundleSpec(
        os: OS.iOS,
        arch: Architecture.x64,
        isIosSimulator: true,
      );

      expect(spec, isNotNull);
      expect(spec!.bundle, 'ios-x86_64-sim');
      expect(spec.configurableBackends, isFalse);
      expect(spec.defaultBackends, isEmpty);
    });
  });

  group('describeNativeLibrary', () {
    test('classifies core llama library', () {
      final descriptor = describeNativeLibrary('/tmp/libllamadart.so');

      expect(descriptor.canonicalName, 'llamadart');
      expect(descriptor.isCore, isTrue);
      expect(descriptor.isPrimary, isTrue);
      expect(descriptor.backend, isNull);
    });

    test('classifies ggml backend module', () {
      final descriptor = describeNativeLibrary('/tmp/libggml-vulkan.so');

      expect(descriptor.canonicalName, 'ggml-vulkan');
      expect(descriptor.isCore, isFalse);
      expect(descriptor.backend, 'vulkan');
    });

    test('normalizes legacy suffix naming', () {
      final descriptor = describeNativeLibrary(
        '/tmp/ggml-cuda-windows-x64.dll',
      );

      expect(descriptor.canonicalName, 'ggml-cuda');
      expect(descriptor.backend, 'cuda');
    });

    test('maps OpenCL loader to opencl backend', () {
      final descriptor = describeNativeLibrary('/tmp/libOpenCL.so');

      expect(descriptor.canonicalName, 'opencl');
      expect(descriptor.backend, 'opencl');
    });

    test('does not classify cublas runtime as a backend module', () {
      final descriptor = describeNativeLibrary('/tmp/cublas64_12.dll');

      expect(descriptor.canonicalName, 'cublas64_12');
      expect(descriptor.backend, isNull);
    });

    test('normalizes Linux SONAME suffix for core libraries', () {
      final descriptor = describeNativeLibrary('/tmp/libllama.so.0');

      expect(descriptor.canonicalName, 'llama');
      expect(descriptor.isCore, isTrue);
      expect(descriptor.backend, isNull);
    });

    test('normalizes Linux SONAME suffix for ggml base library', () {
      final descriptor = describeNativeLibrary('/tmp/libggml-base.so.1');

      expect(descriptor.canonicalName, 'ggml-base');
      expect(descriptor.isCore, isTrue);
      expect(descriptor.backend, isNull);
    });
  });

  group('parseRequestedBackends', () {
    test('parses hooks user-defines platform map', () {
      final requested = parseRequestedBackends(
        bundle: 'linux-x64',
        rawUserConfig: {
          'platforms': {
            'linux-x64': ['CUDA', ' vulkan '],
          },
        },
      );

      expect(requested, ['cuda', 'vulkan']);
    });

    test('supports direct platform map shape', () {
      final requested = parseRequestedBackends(
        bundle: 'windows-x64',
        rawUserConfig: {
          'windows-x64': ['vulkan'],
        },
      );

      expect(requested, ['vulkan']);
    });
  });

  group('selectLibrariesForBundling', () {
    final spec = resolveNativeBundleSpec(
      os: OS.linux,
      arch: Architecture.x64,
      isIosSimulator: false,
    )!;

    final libraries = [
      describeNativeLibrary('/tmp/libllamadart.so'),
      describeNativeLibrary('/tmp/libllama.so'),
      describeNativeLibrary('/tmp/libggml.so'),
      describeNativeLibrary('/tmp/libggml-base.so'),
      describeNativeLibrary('/tmp/libggml-cpu.so'),
      describeNativeLibrary('/tmp/libggml-vulkan.so'),
      describeNativeLibrary('/tmp/libggml-opencl.so'),
    ];

    test('keeps defaults when no user config is provided', () {
      final selected = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: null,
        warn: (_) {},
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu'));
      expect(selectedNames, contains('ggml-vulkan'));
      expect(selectedNames, isNot(contains('ggml-opencl')));
    });

    test('uses requested backend when available', () {
      final selected = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: {
          'platforms': {
            'linux-x64': ['opencl'],
          },
        },
        warn: (_) {},
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu'));
      expect(selectedNames, contains('ggml-opencl'));
      expect(selectedNames, isNot(contains('ggml-vulkan')));
      expect(selectedNames, contains('llamadart'));
    });

    test('falls back to defaults when requested backend is unavailable', () {
      final warnings = <String>[];
      final selected = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: {
          'platforms': {
            'linux-x64': ['cuda'],
          },
        },
        warn: warnings.add,
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu'));
      expect(selectedNames, contains('ggml-vulkan'));
      expect(selectedNames, isNot(contains('ggml-opencl')));
      expect(warnings, isNotEmpty);
    });

    test('apple targets ignore backend config and include all libraries', () {
      final appleSpec = resolveNativeBundleSpec(
        os: OS.macOS,
        arch: Architecture.arm64,
        isIosSimulator: false,
      )!;

      final selected = selectLibrariesForBundling(
        spec: appleSpec,
        libraries: libraries,
        rawUserConfig: {
          'platforms': {
            'macos-arm64': ['cpu'],
          },
        },
        warn: (_) {},
      );

      expect(selected.length, libraries.length);
    });
  });

  group('codeAssetNameForLibrary', () {
    test('maps Windows llama core to primary asset id', () {
      final spec = resolveNativeBundleSpec(
        os: OS.windows,
        arch: Architecture.x64,
        isIosSimulator: false,
      )!;
      final library = describeNativeLibrary('/tmp/llama-windows-x64.dll');

      expect(
        codeAssetNameForLibrary(spec: spec, library: library),
        'llamadart',
      );
    });

    test('maps Windows wrapper to non-primary asset id', () {
      final spec = resolveNativeBundleSpec(
        os: OS.windows,
        arch: Architecture.x64,
        isIosSimulator: false,
      )!;
      final library = describeNativeLibrary('/tmp/llamadart-windows-x64.dll');

      expect(
        codeAssetNameForLibrary(spec: spec, library: library),
        'llamadart_wrapper',
      );
    });

    test('keeps non-Windows primary mapping unchanged', () {
      final spec = resolveNativeBundleSpec(
        os: OS.linux,
        arch: Architecture.x64,
        isIosSimulator: false,
      )!;
      final library = describeNativeLibrary('/tmp/libllamadart.so');

      expect(
        codeAssetNameForLibrary(spec: spec, library: library),
        'llamadart',
      );
    });
  });
}
