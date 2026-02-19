import 'package:code_assets/code_assets.dart';
import 'package:path/path.dart' as path;

const String nativeBackendUserDefineKey = 'llamadart_native_backends';

const Set<String> _coreLibraries = {
  'llamadart',
  'llama',
  'ggml',
  'ggml-base',
  'mtmd',
};

const Set<String> _knownBundleKeys = {
  'android-arm64',
  'android-x64',
  'ios-arm64',
  'ios-arm64-sim',
  'ios-x86_64-sim',
  'linux-arm64',
  'linux-x64',
  'macos-arm64',
  'macos-x86_64',
  'windows-arm64',
  'windows-x64',
};

const List<String> _platformSuffixes = [
  '-ios-x86_64-sim',
  '-ios-arm64-sim',
  '-windows-arm64',
  '-windows-x64',
  '-android-arm64',
  '-android-x64',
  '-macos-x86_64',
  '-macos-arm64',
  '-linux-arm64',
  '-linux-x64',
  '-ios-arm64',
];

const Map<String, String> _bundleAliases = {
  'android-arm64-v8a': 'android-arm64',
  'android-x86_64': 'android-x64',
  'ios-x64-sim': 'ios-x86_64-sim',
  'linux-x86_64': 'linux-x64',
  'macos-x64': 'macos-x86_64',
  'windows-x86_64': 'windows-x64',
};

const Map<String, String> _backendAliases = {
  'vk': 'vulkan',
  'ocl': 'opencl',
  'open-cl': 'opencl',
};

class NativeBundleSpec {
  final String bundle;
  final bool configurableBackends;
  final List<String> defaultBackends;

  const NativeBundleSpec({
    required this.bundle,
    required this.configurableBackends,
    required this.defaultBackends,
  });
}

class NativeLibraryDescriptor {
  final String filePath;
  final String fileName;
  final String canonicalName;
  final bool isCore;
  final bool isPrimary;
  final String? backend;

  const NativeLibraryDescriptor({
    required this.filePath,
    required this.fileName,
    required this.canonicalName,
    required this.isCore,
    required this.isPrimary,
    required this.backend,
  });
}

NativeBundleSpec? resolveNativeBundleSpec({
  required OS os,
  required Architecture arch,
  required bool isIosSimulator,
}) {
  switch ((os, arch)) {
    case (OS.android, Architecture.arm64):
      return const NativeBundleSpec(
        bundle: 'android-arm64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    case (OS.android, Architecture.x64):
      return const NativeBundleSpec(
        bundle: 'android-x64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    case (OS.iOS, Architecture.arm64):
      return NativeBundleSpec(
        bundle: isIosSimulator ? 'ios-arm64-sim' : 'ios-arm64',
        configurableBackends: false,
        defaultBackends: const [],
      );
    case (OS.iOS, Architecture.x64):
      return const NativeBundleSpec(
        bundle: 'ios-x86_64-sim',
        configurableBackends: false,
        defaultBackends: [],
      );
    case (OS.linux, Architecture.arm64):
      return const NativeBundleSpec(
        bundle: 'linux-arm64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    case (OS.linux, Architecture.x64):
      return const NativeBundleSpec(
        bundle: 'linux-x64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    case (OS.macOS, Architecture.arm64):
      return const NativeBundleSpec(
        bundle: 'macos-arm64',
        configurableBackends: false,
        defaultBackends: [],
      );
    case (OS.macOS, Architecture.x64):
      return const NativeBundleSpec(
        bundle: 'macos-x86_64',
        configurableBackends: false,
        defaultBackends: [],
      );
    case (OS.windows, Architecture.arm64):
      return const NativeBundleSpec(
        bundle: 'windows-arm64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    case (OS.windows, Architecture.x64):
      return const NativeBundleSpec(
        bundle: 'windows-x64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    default:
      return null;
  }
}

String canonicalizeBundleKey(String value) {
  var normalized = value.trim().toLowerCase().replaceAll(' ', '');
  normalized = normalized.replaceAll('_', '-');
  normalized = normalized.replaceAll('x86-64', 'x86_64');
  return _bundleAliases[normalized] ?? normalized;
}

NativeLibraryDescriptor describeNativeLibrary(String filePath) {
  final fileName = path.basename(filePath);
  final canonicalName = _canonicalLibraryName(fileName);
  final backend = _inferBackend(canonicalName);
  final isCore = _coreLibraries.contains(canonicalName);

  return NativeLibraryDescriptor(
    filePath: filePath,
    fileName: fileName,
    canonicalName: canonicalName,
    isCore: isCore,
    isPrimary: canonicalName == 'llamadart',
    backend: isCore ? null : backend,
  );
}

List<NativeLibraryDescriptor> describeNativeLibraries(
  Iterable<String> filePaths,
) {
  return filePaths.map(describeNativeLibrary).toList(growable: false);
}

Set<String> collectAvailableBackends(
  Iterable<NativeLibraryDescriptor> libraries,
) {
  final backends = <String>{};
  for (final library in libraries) {
    if (library.backend != null) {
      backends.add(library.backend!);
    }
  }
  return backends;
}

List<String>? parseRequestedBackends({
  required String bundle,
  required Object? rawUserConfig,
}) {
  final root = _toStringMap(rawUserConfig);
  if (root == null) {
    return null;
  }

  final platformsMap = _extractPlatformsMap(root);
  if (platformsMap == null) {
    return null;
  }

  final canonicalBundle = canonicalizeBundleKey(bundle);
  Object? platformValue;
  for (final entry in platformsMap.entries) {
    if (canonicalizeBundleKey(entry.key) == canonicalBundle) {
      platformValue = entry.value;
      break;
    }
  }

  if (platformValue == null) {
    return null;
  }

  if (platformValue is Map<Object?, Object?> &&
      platformValue['backends'] != null) {
    return _parseBackendList(platformValue['backends']);
  }

  return _parseBackendList(platformValue);
}

List<String> selectBackendsForBundle({
  required NativeBundleSpec spec,
  required Set<String> availableBackends,
  required Object? rawUserConfig,
  required void Function(String message) warn,
}) {
  if (!spec.configurableBackends) {
    return const [];
  }

  final defaults = spec.defaultBackends
      .where(availableBackends.contains)
      .toList(growable: false);
  final effectiveDefaults = _ensureCpuBackend(defaults, availableBackends);

  final requested = parseRequestedBackends(
    bundle: spec.bundle,
    rawUserConfig: rawUserConfig,
  );

  if (requested == null || requested.isEmpty) {
    if (effectiveDefaults.isNotEmpty || availableBackends.isEmpty) {
      return effectiveDefaults;
    }

    final fallback = availableBackends.toList()..sort();
    warn(
      'No default backend module was found for ${spec.bundle}; '
      'bundling all available modules: ${fallback.join(', ')}.',
    );
    return fallback;
  }

  final missing = requested
      .where((backend) => !availableBackends.contains(backend))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    warn(
      'Requested backend(s) ${missing.join(', ')} are unavailable for '
      '${spec.bundle}. Falling back to defaults: '
      '${effectiveDefaults.join(', ')}.',
    );
    if (effectiveDefaults.isNotEmpty || availableBackends.isEmpty) {
      return effectiveDefaults;
    }

    final fallback = availableBackends.toList()..sort();
    warn(
      'Default backends are also unavailable for ${spec.bundle}; '
      'bundling all available modules: ${fallback.join(', ')}.',
    );
    return fallback;
  }

  return _ensureCpuBackend(requested, availableBackends);
}

List<NativeLibraryDescriptor> selectLibrariesForBundling({
  required NativeBundleSpec spec,
  required List<NativeLibraryDescriptor> libraries,
  required Object? rawUserConfig,
  required void Function(String message) warn,
}) {
  if (!spec.configurableBackends) {
    return libraries;
  }

  final selectedBackends = selectBackendsForBundle(
    spec: spec,
    availableBackends: collectAvailableBackends(libraries),
    rawUserConfig: rawUserConfig,
    warn: warn,
  );

  return libraries
      .where((library) {
        if (library.isCore || library.backend == null) {
          return true;
        }
        return selectedBackends.contains(library.backend);
      })
      .toList(growable: false);
}

String codeAssetNameForLibrary(NativeLibraryDescriptor library) {
  if (library.isPrimary) {
    return 'llamadart';
  }
  return library.canonicalName.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
}

List<String> _ensureCpuBackend(
  List<String> backends,
  Set<String> availableBackends,
) {
  if (!availableBackends.contains('cpu') || backends.contains('cpu')) {
    return backends;
  }

  final updated = <String>['cpu', ...backends];
  return updated;
}

Map<String, Object?>? _extractPlatformsMap(Map<String, Object?> root) {
  final platformsValue = root['platforms'];
  final platformsMap = _toStringMap(platformsValue);
  if (platformsMap != null) {
    return platformsMap;
  }

  // Backward-compatible shape: direct platform map.
  final hasPlatformKeys = root.keys.any(
    (key) => _knownBundleKeys.contains(canonicalizeBundleKey(key)),
  );
  if (hasPlatformKeys) {
    return root;
  }

  return null;
}

Map<String, Object?>? _toStringMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return null;
  }

  final mapped = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      mapped[key] = entry.value;
    }
  }
  return mapped;
}

List<String> _parseBackendList(Object? value) {
  final result = <String>[];

  if (value is String) {
    for (final token in value.split(',')) {
      final normalized = _normalizeBackend(token);
      if (normalized != null && !result.contains(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }

  if (value is! List<Object?>) {
    return result;
  }

  for (final entry in value) {
    if (entry is! String) {
      continue;
    }
    final normalized = _normalizeBackend(entry);
    if (normalized != null && !result.contains(normalized)) {
      result.add(normalized);
    }
  }

  return result;
}

String? _normalizeBackend(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('_', '-');
  if (normalized.isEmpty) {
    return null;
  }
  return _backendAliases[normalized] ?? normalized;
}

String _canonicalLibraryName(String fileName) {
  var stem = fileName;
  final dotIndex = stem.lastIndexOf('.');
  if (dotIndex > 0) {
    stem = stem.substring(0, dotIndex);
  }

  if (stem.startsWith('lib') && stem.length > 3) {
    stem = stem.substring(3);
  }

  stem = stem.toLowerCase();

  for (final suffix in _platformSuffixes) {
    if (stem.endsWith(suffix)) {
      return stem.substring(0, stem.length - suffix.length);
    }
  }

  return stem;
}

String? _inferBackend(String canonicalName) {
  if (canonicalName.startsWith('ggml-')) {
    final suffix = canonicalName.substring('ggml-'.length);
    if (suffix.isEmpty || suffix == 'base') {
      return null;
    }
    return _normalizeBackend(suffix.split('-').first);
  }

  if (canonicalName.contains('opencl')) {
    return 'opencl';
  }
  if (canonicalName.contains('vulkan')) {
    return 'vulkan';
  }
  if (canonicalName.contains('cuda')) {
    return 'cuda';
  }
  if (canonicalName.contains('blas')) {
    return 'blas';
  }
  if (canonicalName.contains('metal')) {
    return 'metal';
  }
  if (canonicalName.contains('hip')) {
    return 'hip';
  }

  return null;
}
