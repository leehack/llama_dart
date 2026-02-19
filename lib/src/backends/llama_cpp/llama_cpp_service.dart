import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import '../../core/models/chat/content_part.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/model_params.dart';
import 'bindings.dart';

typedef _GgmlBackendLoadNative = ggml_backend_reg_t Function(Pointer<Char>);
typedef _GgmlBackendLoadDart = ggml_backend_reg_t Function(Pointer<Char>);
typedef _GgmlBackendLoadAllNative = Void Function();
typedef _GgmlBackendLoadAllDart = void Function();
typedef _LlamaDartSetLogLevelNative = Void Function(Int32);
typedef _LlamaDartSetLogLevelDart = void Function(int);
typedef _MtmdDefaultMarkerNative = Pointer<Char> Function();
typedef _MtmdDefaultMarkerDart = Pointer<Char> Function();
typedef _MtmdContextParamsDefaultNative = mtmd_context_params Function();
typedef _MtmdContextParamsDefaultDart = mtmd_context_params Function();
typedef _MtmdInitFromFileNative =
    Pointer<mtmd_context> Function(
      Pointer<Char>,
      Pointer<llama_model>,
      mtmd_context_params,
    );
typedef _MtmdInitFromFileDart =
    Pointer<mtmd_context> Function(
      Pointer<Char>,
      Pointer<llama_model>,
      mtmd_context_params,
    );
typedef _MtmdFreeNative = Void Function(Pointer<mtmd_context>);
typedef _MtmdFreeDart = void Function(Pointer<mtmd_context>);
typedef _MtmdInputChunksInitNative = Pointer<mtmd_input_chunks> Function();
typedef _MtmdInputChunksInitDart = Pointer<mtmd_input_chunks> Function();
typedef _MtmdInputChunksFreeNative = Void Function(Pointer<mtmd_input_chunks>);
typedef _MtmdInputChunksFreeDart = void Function(Pointer<mtmd_input_chunks>);
typedef _MtmdHelperBitmapInitFromFileNative =
    Pointer<mtmd_bitmap> Function(Pointer<mtmd_context>, Pointer<Char>);
typedef _MtmdHelperBitmapInitFromFileDart =
    Pointer<mtmd_bitmap> Function(Pointer<mtmd_context>, Pointer<Char>);
typedef _MtmdHelperBitmapInitFromBufNative =
    Pointer<mtmd_bitmap> Function(
      Pointer<mtmd_context>,
      Pointer<UnsignedChar>,
      Size,
    );
typedef _MtmdHelperBitmapInitFromBufDart =
    Pointer<mtmd_bitmap> Function(
      Pointer<mtmd_context>,
      Pointer<UnsignedChar>,
      int,
    );
typedef _MtmdBitmapInitFromAudioNative =
    Pointer<mtmd_bitmap> Function(Size, Pointer<Float>);
typedef _MtmdBitmapInitFromAudioDart =
    Pointer<mtmd_bitmap> Function(int, Pointer<Float>);
typedef _MtmdBitmapFreeNative = Void Function(Pointer<mtmd_bitmap>);
typedef _MtmdBitmapFreeDart = void Function(Pointer<mtmd_bitmap>);
typedef _MtmdTokenizeNative =
    Int32 Function(
      Pointer<mtmd_context>,
      Pointer<mtmd_input_chunks>,
      Pointer<mtmd_input_text>,
      Pointer<Pointer<mtmd_bitmap>>,
      Size,
    );
typedef _MtmdTokenizeDart =
    int Function(
      Pointer<mtmd_context>,
      Pointer<mtmd_input_chunks>,
      Pointer<mtmd_input_text>,
      Pointer<Pointer<mtmd_bitmap>>,
      int,
    );
typedef _MtmdHelperEvalChunksNative =
    Int32 Function(
      Pointer<mtmd_context>,
      Pointer<llama_context>,
      Pointer<mtmd_input_chunks>,
      llama_pos,
      llama_seq_id,
      Int32,
      Bool,
      Pointer<llama_pos>,
    );
typedef _MtmdHelperEvalChunksDart =
    int Function(
      Pointer<mtmd_context>,
      Pointer<llama_context>,
      Pointer<mtmd_input_chunks>,
      int,
      int,
      int,
      bool,
      Pointer<llama_pos>,
    );

/// Service responsible for managing Llama.cpp models and contexts.
///
/// This service handles the direct interaction with the native Llama.cpp library,
/// including loading models, creating contexts, managing memory, and running inference.
class LlamaCppService {
  int _nextHandle = 1;
  String? _backendModuleDirectory;
  final Set<String> _loadedBackendModules = <String>{};
  bool _backendLoadAllSymbolUnavailable = false;
  bool _backendLoadSymbolUnavailable = false;
  bool _backendRegistrySymbolUnavailable = false;
  bool _ggmlFallbackLookupAttempted = false;
  _GgmlBackendLoadDart? _ggmlBackendLoadFallback;
  _GgmlBackendLoadAllDart? _ggmlBackendLoadAllFallback;
  bool _logLevelFallbackLookupAttempted = false;
  String? _logLevelFallbackLookupSearchKey;
  _LlamaDartSetLogLevelDart? _llamaDartSetLogLevelFallback;
  LlamaLogLevel _configuredLogLevel = LlamaLogLevel.warn;
  bool _mtmdFallbackLookupAttempted = false;
  bool _mtmdPrimarySymbolsUnavailable = false;
  _MtmdApi? _mtmdFallbackApi;

  // --- Internal State ---
  final Map<int, _LlamaModelWrapper> _models = {};
  final Map<int, _LlamaContextWrapper> _contexts = {};
  final Map<int, int> _contextToModel = {};
  final Map<int, Pointer<llama_sampler>> _samplers = {};
  final Map<int, llama_batch> _batches = {};
  final Map<int, llama_context_params> _contextParams = {};
  final Map<int, Map<String, _LlamaLoraWrapper>> _loraAdapters = {};
  final Map<int, Map<String, double>> _activeLoras = {};

  // Mapping: modelHandle -> mtmdContextHandle
  final Map<int, int> _modelToMtmd = {};
  final Map<int, Pointer<mtmd_context>> _mtmdContexts = {};

  int _getHandle() => _nextHandle++;

  /// Resolves the effective GPU layer count for model loading.
  ///
  /// CPU backend preference always forces zero offloaded layers.
  static int resolveGpuLayersForLoad(ModelParams modelParams) {
    return modelParams.preferredBackend == GpuBackend.cpu
        ? 0
        : modelParams.gpuLayers;
  }

  // --- Core Methods ---

  /// Sets the log level for the Llama.cpp library.
  void setLogLevel(LlamaLogLevel level) {
    _configuredLogLevel = level;
    _applyConfiguredLogLevel();
  }

  void _applyConfiguredLogLevel() {
    var applied = false;
    try {
      llama_dart_set_log_level(_configuredLogLevel.index);
      applied = true;
    } on ArgumentError {
      // Continue with explicit fallback lookup below.
    }

    // Apply via explicit wrapper lookup as well. On Windows split bundles the
    // primary @DefaultAsset can resolve to a different loaded copy than the
    // runtime backend modules, so applying to both keeps log-level state in
    // sync across module-loading layouts.
    _resolveLogLevelFallbackFunction();
    final fallback = _llamaDartSetLogLevelFallback;
    if (fallback != null) {
      try {
        fallback(_configuredLogLevel.index);
        applied = true;
      } catch (_) {
        // Ignore fallback invocation errors and preserve existing behavior.
      }
    }

    if (!applied) {
      // No applicable symbol found for this runtime layout.
    }
  }

  /// Initializes the Llama.cpp backend.
  ///
  /// This must be called before loading any models.
  void initializeBackend() {
    _backendModuleDirectory = resolveBackendModuleDirectory();
    _applyConfiguredLogLevel();

    if (_backendModuleDirectory == null) {
      _tryLoadAllBackendsBestEffort();
    } else {
      // Split-module bundles: load CPU and proactively probe optional
      // backend modules so capability discovery works before first model load.
      _tryLoadBackendModule('cpu');
      _prepareBackendsForModelLoad(GpuBackend.auto);
    }

    if (_backendRegistryOr<int>(0, ggml_backend_reg_count) == 0) {
      // Fallback path: attempt to load CPU backend by filename resolution.
      _tryLoadBackendModule('cpu');
    }

    llama_backend_init();
    _applyConfiguredLogLevel();
  }

  void _tryLoadAllBackendsBestEffort() {
    if (_backendLoadAllSymbolUnavailable) {
      return;
    }

    try {
      ggml_backend_load_all();
    } on ArgumentError {
      _resolveGgmlFallbackFunctions();
      final fallback = _ggmlBackendLoadAllFallback;
      if (fallback != null) {
        fallback();
        return;
      }

      // Some split bundles don't expose this symbol on the primary FFI asset.
      // Continue with explicit backend-module loading fallback.
      _backendLoadAllSymbolUnavailable = true;
    }
  }

  /// Resolves the native backend module directory for dynamic backend loading.
  ///
  /// On Android/Linux we inspect `/proc/self/maps` to find the loaded
  /// `libllamadart.so` location, then load backend modules from that directory.
  /// Returns `null` when the path cannot be resolved.
  static String? resolveBackendModuleDirectory() {
    if (Platform.isWindows) {
      return resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: Platform.resolvedExecutable,
        currentDirectoryPath: Directory.current.path,
        environment: Platform.environment,
      );
    }

    if (!Platform.isAndroid && !Platform.isLinux) {
      return null;
    }

    try {
      final mapsFile = File('/proc/self/maps');
      if (!mapsFile.existsSync()) {
        return null;
      }

      final mapsContent = mapsFile.readAsStringSync();
      return parseBackendModuleDirectoryFromProcMaps(mapsContent);
    } catch (_) {
      return null;
    }
  }

  /// Resolves Windows backend-module directory for dynamic backend loading.
  ///
  /// Resolution order:
  /// 1. Explicit environment override (`LLAMADART_NATIVE_LIB_DIR` or
  ///    `LLAMADART_BACKEND_MODULE_DIR`)
  /// 2. Directory of resolved executable (if it looks like a native bundle)
  /// 3. Current working directory (if it looks like a native bundle)
  /// 4. Hook cache under `.dart_tool/llamadart/native_bundles/*/windows-*/`
  /// 5. Directory of resolved executable (best-effort fallback)
  static String? resolveWindowsBackendModuleDirectory({
    required String resolvedExecutablePath,
    required String currentDirectoryPath,
    required Map<String, String> environment,
  }) {
    final overrideCandidates = <String>[
      environment['LLAMADART_NATIVE_LIB_DIR'] ?? '',
      environment['LLAMADART_BACKEND_MODULE_DIR'] ?? '',
    ];
    for (final override in overrideCandidates) {
      if (override.isEmpty) {
        continue;
      }
      if (_containsWindowsNativeModules(override)) {
        return override;
      }
    }

    final executableDir = path.dirname(resolvedExecutablePath);
    if (_containsWindowsNativeModules(executableDir)) {
      return executableDir;
    }

    if (_containsWindowsNativeModules(currentDirectoryPath)) {
      return currentDirectoryPath;
    }

    final preferredBundle = _preferredWindowsBundleName();
    final hookCacheDir = _findHookCacheWindowsBundleDirectory(
      currentDirectoryPath,
      preferredBundleName: preferredBundle,
    );
    if (hookCacheDir != null) {
      return hookCacheDir;
    }

    return executableDir;
  }

  static String? _preferredWindowsBundleName() {
    switch (Abi.current()) {
      case Abi.windowsX64:
        return 'windows-x64';
      case Abi.windowsArm64:
        return 'windows-arm64';
      default:
        return null;
    }
  }

  static String? _findHookCacheWindowsBundleDirectory(
    String currentDirectoryPath, {
    String? preferredBundleName,
  }) {
    var cursor = Directory(currentDirectoryPath).absolute;
    while (true) {
      final cacheRoot = Directory(
        path.join(cursor.path, '.dart_tool', 'llamadart', 'native_bundles'),
      );
      if (cacheRoot.existsSync()) {
        final found = _selectWindowsBundleDirectoryFromCache(
          cacheRoot.path,
          preferredBundleName: preferredBundleName,
        );
        if (found != null) {
          return found;
        }
      }

      final parent = cursor.parent;
      if (parent.path == cursor.path) {
        break;
      }
      cursor = parent;
    }

    return null;
  }

  static String? _selectWindowsBundleDirectoryFromCache(
    String cacheRootPath, {
    String? preferredBundleName,
  }) {
    final cacheRoot = Directory(cacheRootPath);
    List<Directory> tagDirectories;
    try {
      tagDirectories = cacheRoot.listSync().whereType<Directory>().toList(
        growable: false,
      );
    } catch (_) {
      return null;
    }

    tagDirectories.sort(
      (a, b) => path.basename(b.path).compareTo(path.basename(a.path)),
    );

    for (final tagDirectory in tagDirectories) {
      final bundleDirs = <Directory>[];
      if (preferredBundleName != null) {
        final preferred = Directory(
          path.join(tagDirectory.path, preferredBundleName),
        );
        if (preferred.existsSync()) {
          bundleDirs.add(preferred);
        }
      }

      try {
        final otherWindowsBundles = tagDirectory
            .listSync()
            .whereType<Directory>()
            .where(
              (directory) =>
                  path.basename(directory.path).startsWith('windows-'),
            )
            .toList(growable: false);
        bundleDirs.addAll(otherWindowsBundles);
      } catch (_) {
        // Ignore and continue with what we have.
      }

      final seen = <String>{};
      for (final bundleDir in bundleDirs) {
        final normalizedBundle = path.normalize(bundleDir.path);
        if (!seen.add(normalizedBundle)) {
          continue;
        }

        final extractedDir = path.join(bundleDir.path, 'extracted');
        if (_containsWindowsNativeModules(extractedDir)) {
          return extractedDir;
        }
        if (_containsWindowsNativeModules(bundleDir.path)) {
          return bundleDir.path;
        }
      }
    }

    return null;
  }

  static bool _containsWindowsNativeModules(String directoryPath) {
    try {
      final directory = Directory(directoryPath);
      if (!directory.existsSync()) {
        return false;
      }

      final fileNames = directory
          .listSync()
          .whereType<File>()
          .map((file) => path.basename(file.path).toLowerCase())
          .toSet();

      final hasLlama = fileNames.contains('llama.dll');
      final hasGgml = fileNames.contains('ggml.dll');
      final hasCpuBackend = fileNames.any(
        (name) => RegExp(r'^ggml-cpu(?:-[^.\\/]+)*\.dll$').hasMatch(name),
      );
      return hasLlama && hasGgml && hasCpuBackend;
    } catch (_) {
      return false;
    }
  }

  /// Parses `/proc/self/maps` content and returns the module directory.
  ///
  /// This is exposed for testability.
  static String? parseBackendModuleDirectoryFromProcMaps(String mapsContent) {
    for (final rawLine in mapsContent.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final slashIndex = line.indexOf('/');
      if (slashIndex < 0) {
        continue;
      }

      final mappedPath = line.substring(slashIndex).trim();
      final normalizedPath = mappedPath.endsWith(' (deleted)')
          ? mappedPath.substring(0, mappedPath.length - ' (deleted)'.length)
          : mappedPath;

      if (!normalizedPath.endsWith('/libllamadart.so')) {
        continue;
      }

      return path.dirname(normalizedPath);
    }

    return null;
  }

  /// Loads a model from the specified [modelPath].
  ///
  /// Returns a handle to the loaded model.
  /// Throws an [Exception] if the file does not exist or fails to load.
  int loadModel(String modelPath, ModelParams modelParams) {
    final modelFile = File(modelPath);
    if (!modelFile.existsSync()) {
      throw Exception("File not found: $modelPath");
    }
    final modelFileSize = modelFile.lengthSync();
    if (modelFileSize <= 0) {
      throw Exception("Model file is empty: $modelPath");
    }
    if (!_looksLikeGguf(modelFile)) {
      throw Exception(
        "Model file does not appear to be GGUF: $modelPath. "
        "Please verify the download completed correctly.",
      );
    }

    _prepareBackendsForModelLoad(modelParams.preferredBackend);
    _applyConfiguredLogLevel();

    final modelPathPtr = modelPath.toNativeUtf8();
    final mparams = llama_model_default_params();
    var preferredDevices = _createPreferredDeviceList(
      modelParams.preferredBackend,
    );
    var gpuLayers = resolveGpuLayersForLoad(modelParams);

    final explicitGpuBackend =
        modelParams.preferredBackend != GpuBackend.auto &&
        modelParams.preferredBackend != GpuBackend.cpu;
    if (explicitGpuBackend && preferredDevices == null) {
      // Honor explicit backend intent: if requested GPU backend is unavailable,
      // fall back to CPU instead of letting another GPU backend auto-select.
      preferredDevices = _createPreferredDeviceList(GpuBackend.cpu);
      gpuLayers = 0;
    }

    mparams.n_gpu_layers = gpuLayers;
    mparams.use_mmap = true;
    if (preferredDevices != null) {
      mparams.devices = preferredDevices;
    }

    Pointer<llama_model> modelPtr = nullptr;
    try {
      modelPtr = llama_model_load_from_file(modelPathPtr.cast(), mparams);
    } finally {
      malloc.free(modelPathPtr);
      if (preferredDevices != null) {
        malloc.free(preferredDevices);
      }
    }

    if (modelPtr == nullptr) {
      final diagnostics = _backendDiagnostics();
      throw Exception(
        "Failed to load model (size=$modelFileSize bytes, "
        "diagnostics=$diagnostics)",
      );
    }

    final handle = _getHandle();
    _models[handle] = _LlamaModelWrapper(modelPtr);
    _loraAdapters[handle] = {};

    return handle;
  }

  void _prepareBackendsForModelLoad(GpuBackend preferredBackend) {
    // Apple bundles are consolidated into a single native library and do not
    // ship separate ggml backend modules.
    if ((Platform.isMacOS || Platform.isIOS) &&
        _backendModuleDirectory == null) {
      return;
    }

    // Always try CPU first; _tryLoadBackendModule can use either absolute path
    // (when module dir is known) or filename resolution fallback.
    _tryLoadBackendModule('cpu');

    // Probe Vulkan on desktop/mobile platforms where it is commonly provided as
    // a separate backend module, even if user preference is currently CPU.
    if (Platform.isAndroid || Platform.isLinux || Platform.isWindows) {
      _tryLoadBackendModule('vulkan');
    }
    if (Platform.isLinux || Platform.isWindows) {
      _tryLoadBackendModule('blas');
      _tryLoadBackendModule('cuda');
    }
    if (Platform.isLinux) {
      _tryLoadBackendModule('hip');
    }

    switch (preferredBackend) {
      case GpuBackend.auto:
        return;
      case GpuBackend.vulkan:
        return;
      case GpuBackend.metal:
        _tryLoadBackendModule('metal');
        return;
      case GpuBackend.cuda:
        _tryLoadBackendModule('cuda');
        return;
      case GpuBackend.blas:
        _tryLoadBackendModule('blas');
        return;
      case GpuBackend.opencl:
        _tryLoadBackendModule('opencl');
        return;
      case GpuBackend.hip:
        _tryLoadBackendModule('hip');
        return;
      case GpuBackend.cpu:
        return;
    }
  }

  bool _tryLoadBackendModule(String backend) {
    if (_backendLoadSymbolUnavailable) {
      return false;
    }

    if (_loadedBackendModules.contains(backend)) {
      return true;
    }

    final fileNameCandidates = _backendLibraryCandidateFileNames(backend);
    final candidates = <String>{};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory != null) {
      for (final fileName in fileNameCandidates) {
        candidates.add(path.join(backendModuleDirectory, fileName));
      }
    }
    // Keep bare-name fallback last so module-dir resolution wins when present.
    candidates.addAll(fileNameCandidates);

    for (final candidate in candidates) {
      if (path.isAbsolute(candidate) && !File(candidate).existsSync()) {
        continue;
      }

      final libraryPathPtr = candidate.toNativeUtf8();
      try {
        ggml_backend_reg_t reg;
        try {
          reg = ggml_backend_load(libraryPathPtr.cast());
        } on ArgumentError {
          _resolveGgmlFallbackFunctions();
          final fallback = _ggmlBackendLoadFallback;
          if (fallback == null) {
            // Optional dynamic-loader symbol can be missing from the primary
            // FFI asset in split bundles. If ggml fallback is unavailable,
            // stop retrying.
            _backendLoadSymbolUnavailable = true;
            return false;
          }
          reg = fallback(libraryPathPtr.cast());
        }
        if (reg == nullptr) {
          continue;
        }

        _loadedBackendModules.add(backend);
        return true;
      } finally {
        malloc.free(libraryPathPtr);
      }
    }

    return false;
  }

  void _resolveGgmlFallbackFunctions() {
    if (_ggmlFallbackLookupAttempted) {
      return;
    }
    _ggmlFallbackLookupAttempted = true;

    final fileNameCandidates = _ggmlLibraryCandidateFileNames();
    final candidates = <String>{};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory != null) {
      for (final fileName in fileNameCandidates) {
        candidates.add(path.join(backendModuleDirectory, fileName));
      }
    }
    // Keep bare-name fallback last so module-dir resolution wins when present.
    candidates.addAll(fileNameCandidates);

    DynamicLibrary? library;
    for (final candidate in candidates) {
      try {
        library = DynamicLibrary.open(candidate);
        break;
      } catch (_) {
        continue;
      }
    }
    if (library == null) {
      return;
    }

    try {
      _ggmlBackendLoadFallback = library
          .lookupFunction<_GgmlBackendLoadNative, _GgmlBackendLoadDart>(
            'ggml_backend_load',
          );
    } catch (_) {
      _ggmlBackendLoadFallback = null;
    }

    try {
      _ggmlBackendLoadAllFallback = library
          .lookupFunction<_GgmlBackendLoadAllNative, _GgmlBackendLoadAllDart>(
            'ggml_backend_load_all',
          );
    } catch (_) {
      _ggmlBackendLoadAllFallback = null;
    }
  }

  void _resolveLogLevelFallbackFunction() {
    final directories = _llamadartFallbackLookupDirectories();
    final searchKey = directories.map(path.normalize).join('|');

    if (_logLevelFallbackLookupAttempted &&
        _llamaDartSetLogLevelFallback != null) {
      return;
    }

    if (_logLevelFallbackLookupAttempted &&
        _llamaDartSetLogLevelFallback == null &&
        _logLevelFallbackLookupSearchKey == searchKey) {
      return;
    }

    _logLevelFallbackLookupAttempted = true;
    _logLevelFallbackLookupSearchKey = searchKey;

    final fileNameCandidates = _llamadartLibraryCandidateFileNames();
    final candidates = <String>[..._llamadartAssetUriCandidates()];
    final pattern = _llamadartLibraryPattern();
    for (final directoryPath in directories) {
      for (final fileName in fileNameCandidates) {
        candidates.add(path.join(directoryPath, fileName));
      }
      for (final fileName in _matchingLibraryNames(directoryPath, pattern)) {
        candidates.add(path.join(directoryPath, fileName));
      }
    }
    // Keep bare-name fallback last so module-dir resolution wins when present.
    candidates.addAll(fileNameCandidates);

    final seen = <String>{};
    for (final candidate in candidates) {
      if (!seen.add(candidate)) {
        continue;
      }
      try {
        final library = DynamicLibrary.open(candidate);
        _llamaDartSetLogLevelFallback = library
            .lookupFunction<
              _LlamaDartSetLogLevelNative,
              _LlamaDartSetLogLevelDart
            >('llama_dart_set_log_level');
        return;
      } catch (_) {
        continue;
      }
    }
  }

  List<String> _llamadartAssetUriCandidates() {
    // Prefer asset-URI resolution so Windows split bundles can reliably resolve
    // the wrapper helper library without relying on process cwd/search paths.
    if (Platform.isWindows) {
      return const <String>[
        'package:llamadart/llamadart_wrapper',
        'package:llamadart/llamadart',
      ];
    }
    return const <String>['package:llamadart/llamadart'];
  }

  List<String> _llamadartFallbackLookupDirectories() {
    final directories = <String>{};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory != null) {
      directories.add(backendModuleDirectory);
    }

    final executableDir = path.dirname(Platform.resolvedExecutable);
    directories.add(executableDir);
    directories.add(Directory.current.path);

    if (Platform.isMacOS) {
      directories.add(
        path.normalize(path.join(executableDir, '..', 'Frameworks')),
      );
      directories.add(path.normalize(path.join(executableDir, 'Frameworks')));
    }

    return directories.toList(growable: false);
  }

  static String _ggmlLibraryFileName() {
    if (Platform.isWindows) {
      return 'ggml.dll';
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return 'libggml.dylib';
    }
    return 'libggml.so';
  }

  static String _llamadartLibraryFileName() {
    if (Platform.isWindows) {
      return 'llamadart.dll';
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return 'libllamadart.dylib';
    }
    return 'libllamadart.so';
  }

  List<String> _backendLibraryCandidateFileNames(String backend) {
    final baseName = _backendLibraryFileName(backend);
    final candidates = <String>{baseName};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      return candidates.toList(growable: false);
    }

    final dynamicNames = _matchingLibraryNames(
      backendModuleDirectory,
      _backendLibraryPattern(backend),
    );
    candidates.addAll(dynamicNames);
    return candidates.toList(growable: false);
  }

  List<String> _ggmlLibraryCandidateFileNames() {
    final baseName = _ggmlLibraryFileName();
    final candidates = <String>{baseName};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      return candidates.toList(growable: false);
    }

    final dynamicNames = _matchingLibraryNames(
      backendModuleDirectory,
      _ggmlLibraryPattern(),
    );
    candidates.addAll(dynamicNames);
    return candidates.toList(growable: false);
  }

  List<String> _llamadartLibraryCandidateFileNames() {
    final candidates = _llamadartStaticCandidateFileNames();
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      return candidates.toList(growable: false);
    }

    final dynamicNames = _matchingLibraryNames(
      backendModuleDirectory,
      _llamadartLibraryPattern(),
    );
    candidates.addAll(dynamicNames);
    return candidates.toList(growable: false);
  }

  Set<String> _llamadartStaticCandidateFileNames() {
    final candidates = <String>{_llamadartLibraryFileName()};
    if (Platform.isWindows) {
      // Hook asset naming can expose wrapper helper as `llamadart_wrapper.dll`.
      candidates.add('llamadart_wrapper.dll');
    }
    return candidates;
  }

  RegExp _backendLibraryPattern(String backend) {
    final escapedBackend = RegExp.escape(backend);
    if (Platform.isWindows) {
      return RegExp('^ggml-$escapedBackend(?:-[^.\\\\/]+)*\\.dll\$');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return RegExp('^libggml-$escapedBackend(?:-[^.\\\\/]+)*\\.dylib\$');
    }
    return RegExp('^libggml-$escapedBackend(?:-[^.\\\\/]+)*\\.so\$');
  }

  RegExp _ggmlLibraryPattern() {
    if (Platform.isWindows) {
      return RegExp(r'^ggml(?:-[^.\\/]+)*\.dll$');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return RegExp(r'^libggml(?:-[^.\\/]+)*\.dylib$');
    }
    return RegExp(r'^libggml(?:-[^.\\/]+)*\.so$');
  }

  RegExp _llamadartLibraryPattern() {
    if (Platform.isWindows) {
      return RegExp(r'^llamadart(?:[-_][^.\\/]+)*\.dll$');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return RegExp(r'^libllamadart(?:[-_][^.\\/]+)*\.dylib$');
    }
    return RegExp(r'^libllamadart(?:[-_][^.\\/]+)*\.so$');
  }

  static List<String> _matchingLibraryNames(
    String directoryPath,
    RegExp regex,
  ) {
    try {
      final names = <String>[];
      for (final entity in Directory(directoryPath).listSync()) {
        if (entity is! File) {
          continue;
        }
        final name = path.basename(entity.path);
        if (regex.hasMatch(name)) {
          names.add(name);
        }
      }
      names.sort();
      return names;
    } catch (_) {
      return const [];
    }
  }

  T _backendRegistryOr<T>(T fallback, T Function() call) {
    try {
      return call();
    } on ArgumentError {
      // Some split bundles may omit a subset of registry symbols on the
      // primary lookup target. Treat this call as unavailable, but continue
      // attempting other registry APIs that may still be present.
      _backendRegistrySymbolUnavailable = true;
      return fallback;
    }
  }

  static String _backendLibraryFileName(String backend) {
    if (Platform.isWindows) {
      return 'ggml-$backend.dll';
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return 'libggml-$backend.dylib';
    }
    return 'libggml-$backend.so';
  }

  static bool _looksLikeGguf(File modelFile) {
    try {
      final header = modelFile.openSync(mode: FileMode.read);
      try {
        final magic = header.readSync(4);
        if (magic.length < 4) {
          return false;
        }
        return magic[0] == 0x47 &&
            magic[1] == 0x47 &&
            magic[2] == 0x55 &&
            magic[3] == 0x46;
      } finally {
        header.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  String _backendDiagnostics() {
    final regs = <String>[];
    final regCount = _backendRegistryOr<int>(0, ggml_backend_reg_count);
    for (var i = 0; i < regCount; i++) {
      final reg = _backendRegistryOr<ggml_backend_reg_t>(
        nullptr,
        () => ggml_backend_reg_get(i),
      );
      if (reg == nullptr) {
        continue;
      }
      final regNamePtr = _backendRegistryOr<Pointer<Char>>(
        nullptr,
        () => ggml_backend_reg_name(reg),
      );
      if (regNamePtr == nullptr) {
        continue;
      }
      regs.add(regNamePtr.cast<Utf8>().toDartString());
    }

    final devices = getBackendInfo();
    return '{moduleDir=${_backendModuleDirectory ?? "null"}, '
        'loadedModules=${_loadedBackendModules.toList(growable: false)}, '
        'registeredBackends=$regs, devices=$devices, '
        'registryApisUnavailable=$_backendRegistrySymbolUnavailable}';
  }

  Pointer<ggml_backend_dev_t>? _createPreferredDeviceList(GpuBackend backend) {
    final devices = _resolvePreferredDevices(backend);
    if (devices == null || devices.isEmpty) {
      return null;
    }

    final ptr = malloc<ggml_backend_dev_t>(devices.length + 1);
    for (var i = 0; i < devices.length; i++) {
      ptr[i] = devices[i];
    }
    ptr[devices.length] = nullptr;
    return ptr;
  }

  List<ggml_backend_dev_t>? _resolvePreferredDevices(GpuBackend backend) {
    switch (backend) {
      case GpuBackend.auto:
        return null;
      case GpuBackend.cpu:
        final cpuDev = _backendRegistryOr<ggml_backend_dev_t>(
          nullptr,
          () => ggml_backend_dev_by_type(
            ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU,
          ),
        );
        if (cpuDev == nullptr) {
          return null;
        }
        return [cpuDev];
      case GpuBackend.vulkan:
        return _devicesForBackendRegName('Vulkan');
      case GpuBackend.metal:
        return _devicesForBackendRegName('Metal');
      case GpuBackend.cuda:
        return _devicesForBackendRegName('CUDA');
      case GpuBackend.blas:
        return _devicesForBackendRegName('BLAS');
      case GpuBackend.opencl:
        return _devicesForBackendRegName('OpenCL');
      case GpuBackend.hip:
        return _devicesForBackendRegName('HIP');
    }
  }

  List<ggml_backend_dev_t>? _devicesForBackendRegName(String regName) {
    final regNamePtr = regName.toNativeUtf8();
    try {
      final reg = _backendRegistryOr<ggml_backend_reg_t>(
        nullptr,
        () => ggml_backend_reg_by_name(regNamePtr.cast()),
      );
      if (reg == nullptr) {
        return null;
      }

      final count = _backendRegistryOr<int>(
        0,
        () => ggml_backend_reg_dev_count(reg),
      );
      if (count <= 0) {
        return null;
      }

      final devices = <ggml_backend_dev_t>[];
      for (var i = 0; i < count; i++) {
        final dev = _backendRegistryOr<ggml_backend_dev_t>(
          nullptr,
          () => ggml_backend_reg_dev_get(reg, i),
        );
        if (dev != nullptr) {
          devices.add(dev);
        }
      }

      if (devices.isEmpty) {
        return null;
      }

      return devices;
    } finally {
      malloc.free(regNamePtr);
    }
  }

  /// Frees the model associated with [modelHandle].
  ///
  /// This also frees all contexts and LoRA adapters associated with the model.
  void freeModel(int modelHandle) {
    final model = _models.remove(modelHandle);
    if (model != null) {
      final contextsToRemove = _contextToModel.entries
          .where((e) => e.value == modelHandle)
          .map((e) => e.key)
          .toList();
      for (final ctxHandle in contextsToRemove) {
        _freeContext(ctxHandle);
      }
      final adapters = _loraAdapters.remove(modelHandle);
      adapters?.values.forEach((a) => a.dispose());

      // Free associated multimodal context
      final mmHandle = _modelToMtmd.remove(modelHandle);
      if (mmHandle != null) {
        final mmCtx = _mtmdContexts.remove(mmHandle);
        if (mmCtx != null) _mtmdFree(mmCtx);
      }

      model.dispose();
    }
  }

  /// Creates an inference context for the specified [modelHandle].
  ///
  /// Returns a handle to the created context.
  /// Throws an [Exception] if the model handle is invalid or context creation fails.
  int createContext(int modelHandle, ModelParams params) {
    final model = _models[modelHandle];
    if (model == null) {
      throw Exception("Invalid model handle");
    }

    final ctxParams = llama_context_default_params();
    int nCtx = params.contextSize;
    if (nCtx <= 0) {
      nCtx = llama_model_n_ctx_train(model.pointer);
    }
    ctxParams.n_ctx = nCtx;
    ctxParams.n_batch = nCtx; // logic from original code
    ctxParams.n_ubatch = nCtx; // logic from original code
    ctxParams.n_threads = params.numberOfThreads;
    ctxParams.n_threads_batch = params.numberOfThreadsBatch;

    final ctxPtr = llama_init_from_model(model.pointer, ctxParams);
    if (ctxPtr == nullptr) {
      throw Exception("Failed to create context");
    }

    final handle = _getHandle();
    _contexts[handle] = _LlamaContextWrapper(ctxPtr, model);
    _contextToModel[handle] = modelHandle;
    _activeLoras[handle] = {};
    _contextParams[handle] = ctxParams;
    _samplers[handle] = llama_sampler_chain_init(
      llama_sampler_chain_default_params(),
    );
    _batches[handle] = llama_batch_init(nCtx, 0, 1);

    return handle;
  }

  /// Frees the context associated with [contextHandle].
  void freeContext(int contextHandle) {
    _freeContext(contextHandle);
  }

  void _freeContext(int handle) {
    _contextToModel.remove(handle);
    _activeLoras.remove(handle);
    _contextParams.remove(handle);
    final sampler = _samplers.remove(handle);
    if (sampler != null && sampler != nullptr) llama_sampler_free(sampler);
    final batch = _batches.remove(handle);
    if (batch != null) llama_batch_free(batch);
    _contexts.remove(handle)?.dispose();
  }

  /// Generates text based on the given [prompt] and [params].
  ///
  /// Returns a [Stream] of token bytes.
  /// Supports multimodal input via [parts].
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    List<LlamaContentPart>? parts,
  }) async* {
    var ctx = _contexts[contextHandle];
    if (ctx == null) throw Exception("Invalid context handle");

    final modelHandle = _contextToModel[contextHandle]!;
    final model = _models[modelHandle]!;
    final modelParams = _contextParams[contextHandle]!;
    final vocab = llama_model_get_vocab(model.pointer);

    // 1. Reset Context
    ctx = _resetContext(contextHandle, ctx);

    // 2. Prepare Resources
    final nCtx = llama_n_ctx(ctx.pointer);
    final batch = _batches[contextHandle]!;
    final tokensPtr = malloc<Int32>(nCtx);
    final pieceBuf = malloc<Uint8>(256);
    Pointer<Utf8> grammarPtr = nullptr;
    Pointer<Utf8> rootPtr = nullptr;
    _LazyGrammarConfig? lazyGrammarConfig;

    if (params.grammar != null) {
      grammarPtr = params.grammar!.toNativeUtf8();
      rootPtr = params.grammarRoot.toNativeUtf8();
      if (params.grammarLazy && params.grammarTriggers.isNotEmpty) {
        lazyGrammarConfig = _buildLazyGrammarConfig(params);
      }
    }

    try {
      // 3. Ingest Prompt (Text or Multimodal)
      final initialTokens = _ingestPrompt(
        contextHandle,
        modelHandle,
        ctx,
        batch,
        vocab,
        prompt,
        parts,
        tokensPtr,
        nCtx,
        modelParams,
      );

      // 4. Initialize and Run Sampler Loop
      final sampler = _initializeSampler(
        params,
        vocab,
        grammarPtr,
        rootPtr,
        lazyGrammarConfig,
        initialTokens,
        tokensPtr,
      );

      final preservedTokenIds = _resolvePreservedTokenIds(
        vocab,
        params.preservedTokens,
      );
      final effectiveStopSequences = _effectiveStopSequences(
        params.stopSequences,
        params.preservedTokens,
      );

      yield* _runInferenceLoop(
        ctx,
        batch,
        vocab,
        sampler,
        params,
        initialTokens,
        nCtx,
        cancelTokenAddress,
        pieceBuf,
        grammarPtr,
        preservedTokenIds,
        effectiveStopSequences,
      );

      llama_sampler_free(sampler);
    } finally {
      malloc.free(tokensPtr);
      malloc.free(pieceBuf);
      if (grammarPtr != nullptr) malloc.free(grammarPtr);
      if (rootPtr != nullptr) malloc.free(rootPtr);
      lazyGrammarConfig?.dispose();
    }
  }

  /// Helper: Resets the context state to be ready for new generation.
  _LlamaContextWrapper _resetContext(
    int contextHandle,
    _LlamaContextWrapper ctx,
  ) {
    llama_synchronize(ctx.pointer);

    final memory = llama_get_memory(ctx.pointer);
    if (memory == nullptr) {
      throw Exception("Failed to reset context memory");
    }

    llama_memory_clear(memory, true);
    _contexts[contextHandle] = ctx;
    return ctx;
  }

  /// Helper: Ingests the prompt (text or multimodal) and returns initial token count.
  int _ingestPrompt(
    int contextHandle,
    int modelHandle,
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    String prompt,
    List<LlamaContentPart>? parts,
    Pointer<Int32> tokensPtr,
    int nCtx,
    llama_context_params modelParams,
  ) {
    final mediaParts =
        parts
            ?.where((p) => p is LlamaImageContent || p is LlamaAudioContent)
            .toList() ??
        [];
    final mmHandle = _modelToMtmd[modelHandle];
    final mmCtx = mmHandle != null ? _mtmdContexts[mmHandle] : null;

    if (mediaParts.isNotEmpty && mmCtx != null) {
      return _ingestMultimodalPrompt(
        mmCtx,
        ctx,
        vocab,
        prompt,
        mediaParts,
        modelParams,
      );
    } else {
      return _ingestTextPrompt(batch, vocab, prompt, tokensPtr, nCtx, ctx);
    }
  }

  int _ingestMultimodalPrompt(
    Pointer<mtmd_context> mmCtx,
    _LlamaContextWrapper ctx,
    Pointer<llama_vocab> vocab,
    String prompt,
    List<LlamaContentPart> mediaParts,
    llama_context_params modelParams,
  ) {
    int initialTokens = 0;
    final bitmaps = malloc<Pointer<mtmd_bitmap>>(mediaParts.length);
    final chunks = _mtmdInputChunksInit();

    try {
      for (int i = 0; i < mediaParts.length; i++) {
        final p = mediaParts[i];
        bitmaps[i] = nullptr;
        if (p is LlamaImageContent) {
          if (p.path != null) {
            final pathPtr = p.path!.toNativeUtf8();
            bitmaps[i] = _mtmdHelperBitmapInitFromFile(mmCtx, pathPtr.cast());
            malloc.free(pathPtr);
          } else if (p.bytes != null) {
            final dataPtr = malloc<Uint8>(p.bytes!.length);
            dataPtr.asTypedList(p.bytes!.length).setAll(0, p.bytes!);
            bitmaps[i] = _mtmdHelperBitmapInitFromBuf(
              mmCtx,
              dataPtr.cast(),
              p.bytes!.length,
            );
            malloc.free(dataPtr);
          }
        } else if (p is LlamaAudioContent) {
          if (p.path != null) {
            final pathPtr = p.path!.toNativeUtf8();
            bitmaps[i] = _mtmdHelperBitmapInitFromFile(mmCtx, pathPtr.cast());
            malloc.free(pathPtr);
          } else if (p.bytes != null) {
            final dataPtr = malloc<Uint8>(p.bytes!.length);
            dataPtr.asTypedList(p.bytes!.length).setAll(0, p.bytes!);
            bitmaps[i] = _mtmdHelperBitmapInitFromBuf(
              mmCtx,
              dataPtr.cast(),
              p.bytes!.length,
            );
            malloc.free(dataPtr);
          } else if (p.samples != null) {
            final dataPtr = malloc<Float>(p.samples!.length);
            dataPtr.asTypedList(p.samples!.length).setAll(0, p.samples!);
            bitmaps[i] = _mtmdBitmapInitFromAudio(
              p.samples!.length,
              dataPtr.cast(),
            );
            malloc.free(dataPtr);
          }
        }

        if (bitmaps[i] == nullptr) {
          throw Exception("Failed to load media part $i");
        }
      }

      final inputText = malloc<mtmd_input_text>();
      final normalizedPrompt = _normalizeMtmdPromptMarkers(
        prompt,
        mediaParts.length,
      );
      final promptPtr = normalizedPrompt.toNativeUtf8();
      inputText.ref.text = promptPtr.cast();

      final bos = llama_vocab_bos(vocab);
      final eos = llama_vocab_eos(vocab);
      inputText.ref.add_special = (bos != eos && bos != -1);
      inputText.ref.parse_special = true;

      final res = _mtmdTokenize(
        mmCtx,
        chunks,
        inputText,
        bitmaps.cast(),
        mediaParts.length,
      );

      if (res == 0) {
        final newPast = malloc<llama_pos>();
        if (_mtmdHelperEvalChunks(
              mmCtx,
              ctx.pointer,
              chunks,
              0,
              0,
              modelParams.n_batch,
              true,
              newPast,
            ) ==
            0) {
          initialTokens = newPast.value;
        }
        malloc.free(newPast);
      } else {
        throw Exception("mtmd_tokenize failed: $res");
      }

      malloc.free(promptPtr);
      malloc.free(inputText);
    } finally {
      for (int i = 0; i < mediaParts.length; i++) {
        if (bitmaps[i] != nullptr) _mtmdBitmapFree(bitmaps[i]);
      }
      malloc.free(bitmaps);
      _mtmdInputChunksFree(chunks);
    }
    return initialTokens;
  }

  String _normalizeMtmdPromptMarkers(String prompt, int mediaPartCount) {
    final markerPtr = _mtmdDefaultMarker();
    final marker = markerPtr == nullptr
        ? '<__media__>'
        : markerPtr.cast<Utf8>().toDartString();

    var normalized = prompt;
    const directPlaceholders = [
      '<image>',
      '[IMG]',
      '<|image|>',
      '<img>',
      '<|img|>',
    ];

    for (final placeholder in directPlaceholders) {
      normalized = normalized.replaceAll(placeholder, marker);
    }

    // Some VLM templates index image placeholders (e.g. <|image_1|>).
    normalized = normalized.replaceAll(RegExp(r'<\|image_\d+\|>'), marker);

    if (mediaPartCount <= 0) {
      return normalized;
    }

    final markerCount = _countOccurrences(normalized, marker);
    if (markerCount < mediaPartCount) {
      final missing = mediaPartCount - markerCount;
      final markerBlock = List.filled(missing, marker).join(' ');

      if (normalized.contains('User:')) {
        normalized = normalized.replaceFirst('User:', 'User: $markerBlock ');
      } else if (normalized.contains('user:')) {
        normalized = normalized.replaceFirst('user:', 'user: $markerBlock ');
      } else {
        normalized = '$markerBlock\n$normalized';
      }
    }

    return normalized;
  }

  int _countOccurrences(String text, String pattern) {
    if (pattern.isEmpty) {
      return 0;
    }

    int count = 0;
    int start = 0;
    while (true) {
      final index = text.indexOf(pattern, start);
      if (index == -1) {
        break;
      }
      count++;
      start = index + pattern.length;
    }
    return count;
  }

  int _ingestTextPrompt(
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    String prompt,
    Pointer<Int32> tokensPtr,
    int nCtx,
    _LlamaContextWrapper ctx,
  ) {
    final promptPtr = prompt.toNativeUtf8();
    final nTokens = llama_tokenize(
      vocab,
      promptPtr.cast(),
      promptPtr.length,
      tokensPtr,
      nCtx,
      true,
      true,
    );
    malloc.free(promptPtr);

    if (nTokens < 0 || nTokens > nCtx) {
      throw Exception("Tokenization failed or prompt too long");
    }

    batch.n_tokens = nTokens;
    for (int i = 0; i < nTokens; i++) {
      batch.token[i] = tokensPtr[i];
      batch.pos[i] = i;
      batch.n_seq_id[i] = 1;
      batch.seq_id[i][0] = 0;
      batch.logits[i] = (i == nTokens - 1) ? 1 : 0;
    }

    if (llama_decode(ctx.pointer, batch) != 0) {
      throw Exception("Initial decode failed");
    }

    return nTokens;
  }

  /// Helper: Initializes the sampler chain.
  Pointer<llama_sampler> _initializeSampler(
    GenerationParams params,
    Pointer<llama_vocab> vocab,
    Pointer<Utf8> grammarPtr,
    Pointer<Utf8> rootPtr,
    _LazyGrammarConfig? lazyGrammarConfig,
    int initialTokens,
    Pointer<Int32> tokensPtr,
  ) {
    final sampler = llama_sampler_chain_init(
      llama_sampler_chain_default_params(),
    );

    llama_sampler_chain_add(
      sampler,
      llama_sampler_init_penalties(64, params.penalty, 0.0, 0.0),
    );

    if (grammarPtr != nullptr) {
      if (params.grammarLazy && lazyGrammarConfig != null) {
        llama_sampler_chain_add(
          sampler,
          llama_sampler_init_grammar_lazy_patterns(
            vocab,
            grammarPtr.cast(),
            rootPtr.cast(),
            lazyGrammarConfig.triggerPatterns,
            lazyGrammarConfig.numTriggerPatterns,
            lazyGrammarConfig.triggerTokens,
            lazyGrammarConfig.numTriggerTokens,
          ),
        );
      } else {
        llama_sampler_chain_add(
          sampler,
          llama_sampler_init_grammar(vocab, grammarPtr.cast(), rootPtr.cast()),
        );
      }
    }

    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(params.topK));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(params.topP, 1));
    if (params.minP > 0) {
      llama_sampler_chain_add(
        sampler,
        llama_sampler_init_min_p(params.minP, 1),
      );
    }
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(params.temp));

    if (params.temp <= 0) {
      llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    } else {
      final seed = params.seed ?? DateTime.now().millisecondsSinceEpoch;
      llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));
    }

    if (grammarPtr == nullptr && tokensPtr != nullptr && initialTokens > 0) {
      for (int i = 0; i < initialTokens; i++) {
        llama_sampler_accept(sampler, tokensPtr[i]);
      }
    }

    return sampler;
  }

  /// Helper: Runs the main inference loop and yields tokens.
  Stream<List<int>> _runInferenceLoop(
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    Pointer<llama_sampler> sampler,
    GenerationParams params,
    int startPos,
    int nCtx,
    int cancelTokenAddress,
    Pointer<Uint8> pieceBuf,
    Pointer<Utf8> grammarPtr,
    Set<int> preservedTokenIds,
    List<String> stopSequences,
  ) async* {
    final cancelToken = Pointer<Int8>.fromAddress(cancelTokenAddress);
    int currentPos = startPos;
    final accumulatedBytes = <int>[];

    for (int i = 0; i < params.maxTokens; i++) {
      await Future.delayed(Duration.zero);
      if (cancelToken.value == 1) break;
      if (currentPos >= nCtx) break;

      final selectedToken = llama_sampler_sample(sampler, ctx.pointer, -1);
      if (llama_vocab_is_eog(vocab, selectedToken)) break;

      final n = llama_token_to_piece(
        vocab,
        selectedToken,
        pieceBuf.cast(),
        256,
        0,
        preservedTokenIds.contains(selectedToken),
      );

      if (n > 0) {
        final bytes = pieceBuf.asTypedList(n).toList();
        yield bytes;

        if (stopSequences.isNotEmpty) {
          accumulatedBytes.addAll(bytes);
          if (accumulatedBytes.length > 64) {
            accumulatedBytes.removeRange(0, accumulatedBytes.length - 64);
          }
          final text = utf8.decode(accumulatedBytes, allowMalformed: true);
          if (stopSequences.any((s) => text.endsWith(s))) break;
        }
      }

      batch.n_tokens = 1;
      batch.token[0] = selectedToken;
      batch.pos[0] = currentPos++;
      batch.n_seq_id[0] = 1;
      batch.seq_id[0][0] = 0;
      batch.logits[0] = 1;

      if (llama_decode(ctx.pointer, batch) != 0) break;
    }
  }

  _LazyGrammarConfig? _buildLazyGrammarConfig(GenerationParams params) {
    final triggerPatterns = <String>[];
    final triggerTokens = <int>[];

    for (final trigger in params.grammarTriggers) {
      switch (trigger.type) {
        case 0:
          triggerPatterns.add(_regexEscape(trigger.value));
          break;
        case 1:
          final token = trigger.token ?? int.tryParse(trigger.value);
          if (token != null) {
            triggerTokens.add(token);
          }
          break;
        case 2:
          triggerPatterns.add(trigger.value);
          break;
        case 3:
          final pattern = trigger.value;
          final anchored = pattern.isEmpty
              ? r'^$'
              : "${pattern.startsWith('^') ? '' : '^'}$pattern${pattern.endsWith(r'$') ? '' : r'$'}";
          triggerPatterns.add(anchored);
          break;
      }
    }

    if (triggerPatterns.isEmpty && triggerTokens.isEmpty) {
      return null;
    }

    final allocatedPatternPtrs = triggerPatterns
        .map((pattern) => pattern.toNativeUtf8())
        .toList(growable: false);

    final triggerPatternsPtr = allocatedPatternPtrs.isEmpty
        ? nullptr
        : malloc<Pointer<Char>>(allocatedPatternPtrs.length);

    if (triggerPatternsPtr != nullptr) {
      for (var i = 0; i < allocatedPatternPtrs.length; i++) {
        triggerPatternsPtr[i] = allocatedPatternPtrs[i].cast();
      }
    }

    final triggerTokensPtr = triggerTokens.isEmpty
        ? nullptr
        : malloc<llama_token>(triggerTokens.length);

    if (triggerTokensPtr != nullptr) {
      for (var i = 0; i < triggerTokens.length; i++) {
        triggerTokensPtr[i] = triggerTokens[i];
      }
    }

    return _LazyGrammarConfig(
      triggerPatterns: triggerPatternsPtr,
      numTriggerPatterns: allocatedPatternPtrs.length,
      triggerTokens: triggerTokensPtr,
      numTriggerTokens: triggerTokens.length,
      allocatedPatternPointers: allocatedPatternPtrs,
    );
  }

  Set<int> _resolvePreservedTokenIds(
    Pointer<llama_vocab> vocab,
    List<String> preservedTokens,
  ) {
    if (preservedTokens.isEmpty) {
      return const <int>{};
    }

    final ids = <int>{};
    for (final tokenText in preservedTokens) {
      if (tokenText.isEmpty) {
        continue;
      }

      final textPtr = tokenText.toNativeUtf8();
      try {
        final required = -llama_tokenize(
          vocab,
          textPtr.cast(),
          textPtr.length,
          nullptr,
          0,
          false,
          true,
        );

        if (required <= 0) {
          continue;
        }

        final tokenIds = malloc<Int32>(required);
        try {
          final actual = llama_tokenize(
            vocab,
            textPtr.cast(),
            textPtr.length,
            tokenIds,
            required,
            false,
            true,
          );

          if (actual > 0) {
            for (int i = 0; i < actual; i++) {
              ids.add(tokenIds[i]);
            }
          }
        } finally {
          malloc.free(tokenIds);
        }
      } finally {
        malloc.free(textPtr);
      }
    }

    return ids;
  }

  List<String> _effectiveStopSequences(
    List<String> stopSequences,
    List<String> preservedTokens,
  ) {
    if (stopSequences.isEmpty || preservedTokens.isEmpty) {
      return stopSequences;
    }

    final preservedSet = preservedTokens.toSet();
    return stopSequences
        .where((sequence) => !preservedSet.contains(sequence))
        .toList(growable: false);
  }

  String _regexEscape(String input) {
    final escaped = StringBuffer();
    const regexMeta = r'\^$.*+?()[]{}|';
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (regexMeta.contains(char)) {
        escaped.write('\\');
      }
      escaped.write(char);
    }
    return escaped.toString();
  }

  /// Tokenizes the given [text].
  List<int> tokenize(int modelHandle, String text, bool addSpecial) {
    final model = _models[modelHandle];
    if (model == null) return [];
    final vocab = llama_model_get_vocab(model.pointer);
    final textPtr = text.toNativeUtf8();
    final n = -llama_tokenize(
      vocab,
      textPtr.cast(),
      textPtr.length,
      nullptr,
      0,
      addSpecial,
      true,
    );
    final tokensPtr = malloc<Int32>(n);
    final actual = llama_tokenize(
      vocab,
      textPtr.cast(),
      textPtr.length,
      tokensPtr,
      n,
      addSpecial,
      true,
    );
    final result = List.generate(actual, (i) => tokensPtr[i]);
    malloc.free(textPtr);
    malloc.free(tokensPtr);
    return result;
  }

  /// Detokenizes the given [tokens].
  String detokenize(int modelHandle, List<int> tokens, bool special) {
    final model = _models[modelHandle];
    if (model == null) return "";
    final vocab = llama_model_get_vocab(model.pointer);
    final buffer = malloc<Int8>(256);
    final bytes = <int>[];
    for (final t in tokens) {
      final n = llama_token_to_piece(vocab, t, buffer.cast(), 256, 0, special);
      if (n > 0) bytes.addAll(buffer.asTypedList(n));
    }
    malloc.free(buffer);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Returns metadata for the specified [modelHandle].
  Map<String, String> getMetadata(int modelHandle) {
    final model = _models[modelHandle];
    if (model == null) return {};
    final metadata = <String, String>{};
    final keyBuf = malloc<Int8>(1024);
    final valBuf = malloc<Int8>(1024 * 64);
    final n = llama_model_meta_count(model.pointer);
    for (int i = 0; i < n; i++) {
      llama_model_meta_key_by_index(model.pointer, i, keyBuf.cast(), 1024);
      llama_model_meta_val_str_by_index(
        model.pointer,
        i,
        valBuf.cast(),
        1024 * 64,
      );
      metadata[keyBuf.cast<Utf8>().toDartString()] = valBuf
          .cast<Utf8>()
          .toDartString();
    }
    malloc.free(keyBuf);
    malloc.free(valBuf);
    return metadata;
  }

  /// Handles LoRA adapter operations.
  void handleLora(int contextHandle, String? path, double? scale, String op) {
    final ctx = _contexts[contextHandle];
    final modelHandle = _contextToModel[contextHandle];
    if (ctx == null || modelHandle == null) return;

    final modelAdapters = _loraAdapters[modelHandle];
    final activeLoras = _activeLoras[contextHandle];
    if (modelAdapters == null || activeLoras == null) return;

    try {
      if (op == 'set') {
        if (path == null) {
          throw Exception('LoRA path is required for set operation');
        }
        if (scale == null) {
          throw Exception('LoRA scale is required for set operation');
        }

        var adapter = modelAdapters[path];
        if (adapter == null) {
          final pathPtr = path.toNativeUtf8();
          final adapterPtr = llama_adapter_lora_init(
            _models[modelHandle]!.pointer,
            pathPtr.cast(),
          );
          malloc.free(pathPtr);
          if (adapterPtr == nullptr) {
            throw Exception("Failed to load LoRA at $path");
          }
          adapter = _LlamaLoraWrapper(adapterPtr);
          modelAdapters[path] = adapter;
        }
        activeLoras[path] = scale;
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
      } else if (op == 'remove') {
        if (path == null) {
          throw Exception('LoRA path is required for remove operation');
        }
        activeLoras.remove(path);
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
      } else if (op == 'clear') {
        activeLoras.clear();
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
      } else {
        throw Exception('Unknown LoRA operation: $op');
      }
    } catch (e) {
      rethrow;
    }
  }

  void _applyActiveLoras(
    Pointer<llama_context> context,
    Map<String, _LlamaLoraWrapper> loadedAdapters,
    Map<String, double> activeLoras,
  ) {
    if (activeLoras.isEmpty) {
      final result = llama_set_adapters_lora(context, nullptr, 0, nullptr);
      if (result != 0) {
        throw Exception('Failed to clear LoRA adapters (code: $result)');
      }
      return;
    }

    final activeEntries = activeLoras.entries.toList(growable: false);
    final adapterPointers = malloc<Pointer<llama_adapter_lora>>(
      activeEntries.length,
    );
    final scalesPointer = malloc<Float>(activeEntries.length);

    try {
      for (var i = 0; i < activeEntries.length; i++) {
        final entry = activeEntries[i];
        final adapter = loadedAdapters[entry.key];
        if (adapter == null) {
          throw Exception(
            'LoRA adapter not loaded for active path: ${entry.key}',
          );
        }
        adapterPointers[i] = adapter.pointer;
        scalesPointer[i] = entry.value;
      }

      final result = llama_set_adapters_lora(
        context,
        adapterPointers,
        activeEntries.length,
        scalesPointer,
      );
      if (result != 0) {
        throw Exception('Failed to apply LoRA adapters (code: $result)');
      }
    } finally {
      malloc.free(adapterPointers);
      malloc.free(scalesPointer);
    }
  }

  /// Returns information about available backend devices.
  List<String> getBackendInfo() {
    final count = _backendRegistryOr<int>(0, ggml_backend_dev_count);
    final devices = <String>{};
    for (var i = 0; i < count; i++) {
      final dev = _backendRegistryOr<ggml_backend_dev_t>(
        nullptr,
        () => ggml_backend_dev_get(i),
      );
      if (dev == nullptr) continue;

      final devNamePtr = _backendRegistryOr<Pointer<Char>>(
        nullptr,
        () => ggml_backend_dev_name(dev),
      );
      if (devNamePtr == nullptr) continue;
      final devName = devNamePtr.cast<Utf8>().toDartString();

      String label = devName;
      final reg = _backendRegistryOr<ggml_backend_reg_t>(
        nullptr,
        () => ggml_backend_dev_backend_reg(dev),
      );
      if (reg != nullptr) {
        final regNamePtr = _backendRegistryOr<Pointer<Char>>(
          nullptr,
          () => ggml_backend_reg_name(reg),
        );
        if (regNamePtr != nullptr) {
          final regName = regNamePtr.cast<Utf8>().toDartString();
          if (regName.toLowerCase() == devName.toLowerCase()) {
            label = regName;
          } else {
            label = '$regName ($devName)';
          }
        }
      }

      devices.add(label);
    }
    if (devices.isNotEmpty) {
      return devices.toList(growable: false);
    }

    // Fallback when device-enumeration symbols are unavailable: surface loaded
    // backend modules so UI can still present selectable backends.
    final moduleBackends =
        _loadedBackendModules
            .map(_backendDisplayName)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    return moduleBackends;
  }

  static String _backendDisplayName(String backend) {
    switch (backend.toLowerCase()) {
      case 'cpu':
        return 'CPU';
      case 'vulkan':
        return 'Vulkan';
      case 'opencl':
        return 'OpenCL';
      case 'metal':
        return 'Metal';
      case 'cuda':
        return 'CUDA';
      case 'hip':
        return 'HIP';
      case 'blas':
        return 'BLAS';
      default:
        return backend;
    }
  }

  /// Returns whether GPU offloading is supported.
  bool getGpuSupport() {
    return llama_supports_gpu_offload();
  }

  /// Disposes of all resources managed by the service.
  void dispose() {
    for (final c in _contexts.values) {
      c.dispose();
    }
    _contexts.clear();
    for (final m in _models.values) {
      m.dispose();
    }
    _models.clear();
    for (final m in _mtmdContexts.values) {
      _mtmdFree(m);
    }
    _mtmdContexts.clear();
    // llama_backend_free(); // DISABLED: Prevents race conditions with other isolates
  }

  /// Creates a multimodal context (projector) for the model.
  int createMultimodalContext(int modelHandle, String mmProjPath) {
    final model = _models[modelHandle];
    if (model == null) {
      throw Exception("Invalid model handle");
    }

    final mmProjPathPtr = mmProjPath.toNativeUtf8();
    Pointer<mtmd_context> mmCtx = nullptr;
    try {
      final ctxParams = _mtmdContextParamsDefault();
      mmCtx = _mtmdInitFromFile(mmProjPathPtr.cast(), model.pointer, ctxParams);
    } finally {
      malloc.free(mmProjPathPtr);
    }

    if (mmCtx == nullptr) {
      throw Exception("Failed to load multimodal projector");
    }

    final handle = _getHandle();
    _mtmdContexts[handle] = mmCtx;
    _modelToMtmd[modelHandle] = handle;
    return handle;
  }

  /// Frees the multimodal context (projector).
  void freeMultimodalContext(int mmContextHandle) {
    final mmCtx = _mtmdContexts.remove(mmContextHandle);
    if (mmCtx != null) {
      _mtmdFree(mmCtx);
      _modelToMtmd.removeWhere((k, v) => v == mmContextHandle);
    }
  }

  Pointer<Char> _mtmdDefaultMarker() {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_default_marker();
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    return fallback?.defaultMarker() ?? nullptr;
  }

  mtmd_context_params _mtmdContextParamsDefault() {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_context_params_default();
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_context_params_default'));
    }
    return fallback.contextParamsDefault();
  }

  Pointer<mtmd_context> _mtmdInitFromFile(
    Pointer<Char> mmProjPath,
    Pointer<llama_model> model,
    mtmd_context_params ctxParams,
  ) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_init_from_file(mmProjPath, model, ctxParams);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_init_from_file'));
    }
    return fallback.initFromFile(mmProjPath, model, ctxParams);
  }

  void _mtmdFree(Pointer<mtmd_context> ctx) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        mtmd_free(ctx);
        return;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      return;
    }
    fallback.free(ctx);
  }

  Pointer<mtmd_input_chunks> _mtmdInputChunksInit() {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_input_chunks_init();
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_input_chunks_init'));
    }
    return fallback.inputChunksInit();
  }

  void _mtmdInputChunksFree(Pointer<mtmd_input_chunks> chunks) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        mtmd_input_chunks_free(chunks);
        return;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      return;
    }
    fallback.inputChunksFree(chunks);
  }

  Pointer<mtmd_bitmap> _mtmdHelperBitmapInitFromFile(
    Pointer<mtmd_context> ctx,
    Pointer<Char> pathPtr,
  ) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_helper_bitmap_init_from_file(ctx, pathPtr);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(
        _mtmdUnavailableMessage('mtmd_helper_bitmap_init_from_file'),
      );
    }
    return fallback.helperBitmapInitFromFile(ctx, pathPtr);
  }

  Pointer<mtmd_bitmap> _mtmdHelperBitmapInitFromBuf(
    Pointer<mtmd_context> ctx,
    Pointer<UnsignedChar> data,
    int size,
  ) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_helper_bitmap_init_from_buf(ctx, data, size);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(
        _mtmdUnavailableMessage('mtmd_helper_bitmap_init_from_buf'),
      );
    }
    return fallback.helperBitmapInitFromBuf(ctx, data, size);
  }

  Pointer<mtmd_bitmap> _mtmdBitmapInitFromAudio(int n, Pointer<Float> samples) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_bitmap_init_from_audio(n, samples);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_bitmap_init_from_audio'));
    }
    return fallback.bitmapInitFromAudio(n, samples);
  }

  void _mtmdBitmapFree(Pointer<mtmd_bitmap> bitmap) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        mtmd_bitmap_free(bitmap);
        return;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      return;
    }
    fallback.bitmapFree(bitmap);
  }

  int _mtmdTokenize(
    Pointer<mtmd_context> ctx,
    Pointer<mtmd_input_chunks> output,
    Pointer<mtmd_input_text> text,
    Pointer<Pointer<mtmd_bitmap>> bitmaps,
    int nBitmaps,
  ) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_tokenize(ctx, output, text, bitmaps, nBitmaps);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_tokenize'));
    }
    return fallback.tokenize(ctx, output, text, bitmaps, nBitmaps);
  }

  int _mtmdHelperEvalChunks(
    Pointer<mtmd_context> ctx,
    Pointer<llama_context> lctx,
    Pointer<mtmd_input_chunks> chunks,
    int nPast,
    int seqId,
    int nBatch,
    bool logitsLast,
    Pointer<llama_pos> newNPast,
  ) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_helper_eval_chunks(
          ctx,
          lctx,
          chunks,
          nPast,
          seqId,
          nBatch,
          logitsLast,
          newNPast,
        );
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_helper_eval_chunks'));
    }
    return fallback.helperEvalChunks(
      ctx,
      lctx,
      chunks,
      nPast,
      seqId,
      nBatch,
      logitsLast,
      newNPast,
    );
  }

  _MtmdApi? _resolveMtmdFallbackApi() {
    if (_mtmdFallbackLookupAttempted) {
      return _mtmdFallbackApi;
    }
    _mtmdFallbackLookupAttempted = true;

    final fileNameCandidates = _mtmdLibraryCandidateFileNames();
    final candidates = <String>{...fileNameCandidates};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory != null) {
      for (final fileName in fileNameCandidates) {
        candidates.add(path.join(backendModuleDirectory, fileName));
      }
    }

    DynamicLibrary? library;
    for (final candidate in candidates) {
      try {
        library = DynamicLibrary.open(candidate);
        break;
      } catch (_) {
        continue;
      }
    }
    if (library == null) {
      return null;
    }

    _mtmdFallbackApi = _MtmdApi.tryLoad(library);
    return _mtmdFallbackApi;
  }

  List<String> _mtmdLibraryCandidateFileNames() {
    final baseName = _mtmdLibraryFileName();
    final candidates = <String>{baseName};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      return candidates.toList(growable: false);
    }

    final dynamicNames = _matchingLibraryNames(
      backendModuleDirectory,
      _mtmdLibraryPattern(),
    );
    candidates.addAll(dynamicNames);
    return candidates.toList(growable: false);
  }

  static String _mtmdLibraryFileName() {
    if (Platform.isWindows) {
      return 'mtmd.dll';
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return 'libmtmd.dylib';
    }
    return 'libmtmd.so';
  }

  RegExp _mtmdLibraryPattern() {
    if (Platform.isWindows) {
      return RegExp(r'^mtmd(?:-[^.\\/]+)*\.dll$');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return RegExp(r'^libmtmd(?:-[^.\\/]+)*\.dylib$');
    }
    return RegExp(r'^libmtmd(?:-[^.\\/]+)*\.so$');
  }

  String _mtmdUnavailableMessage(String symbol) {
    return 'Multimodal support is unavailable in this native runtime bundle '
        '(missing `$symbol` in both primary and mtmd libraries).';
  }

  // --- Helper Getters ---

  /// Returns the context size for the given [contextHandle].
  int getContextSize(int contextHandle) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) return 0;
    return llama_n_ctx(ctx.pointer);
  }

  /// Checks if a multimodal context exists.
  bool hasMultimodalContext(int mmContextHandle) {
    return _mtmdContexts.containsKey(mmContextHandle);
  }
}

class _LazyGrammarConfig {
  final Pointer<Pointer<Char>> triggerPatterns;
  final int numTriggerPatterns;
  final Pointer<llama_token> triggerTokens;
  final int numTriggerTokens;
  final List<Pointer<Utf8>> allocatedPatternPointers;

  const _LazyGrammarConfig({
    required this.triggerPatterns,
    required this.numTriggerPatterns,
    required this.triggerTokens,
    required this.numTriggerTokens,
    required this.allocatedPatternPointers,
  });

  void dispose() {
    for (final pointer in allocatedPatternPointers) {
      malloc.free(pointer);
    }

    if (triggerPatterns != nullptr) {
      malloc.free(triggerPatterns);
    }
    if (triggerTokens != nullptr) {
      malloc.free(triggerTokens);
    }
  }
}

class _MtmdApi {
  final _MtmdDefaultMarkerDart defaultMarker;
  final _MtmdContextParamsDefaultDart contextParamsDefault;
  final _MtmdInitFromFileDart initFromFile;
  final _MtmdFreeDart free;
  final _MtmdInputChunksInitDart inputChunksInit;
  final _MtmdInputChunksFreeDart inputChunksFree;
  final _MtmdHelperBitmapInitFromFileDart helperBitmapInitFromFile;
  final _MtmdHelperBitmapInitFromBufDart helperBitmapInitFromBuf;
  final _MtmdBitmapInitFromAudioDart bitmapInitFromAudio;
  final _MtmdBitmapFreeDart bitmapFree;
  final _MtmdTokenizeDart tokenize;
  final _MtmdHelperEvalChunksDart helperEvalChunks;

  const _MtmdApi({
    required this.defaultMarker,
    required this.contextParamsDefault,
    required this.initFromFile,
    required this.free,
    required this.inputChunksInit,
    required this.inputChunksFree,
    required this.helperBitmapInitFromFile,
    required this.helperBitmapInitFromBuf,
    required this.bitmapInitFromAudio,
    required this.bitmapFree,
    required this.tokenize,
    required this.helperEvalChunks,
  });

  static _MtmdApi? tryLoad(DynamicLibrary library) {
    try {
      return _MtmdApi(
        defaultMarker: library
            .lookupFunction<_MtmdDefaultMarkerNative, _MtmdDefaultMarkerDart>(
              'mtmd_default_marker',
            ),
        contextParamsDefault: library
            .lookupFunction<
              _MtmdContextParamsDefaultNative,
              _MtmdContextParamsDefaultDart
            >('mtmd_context_params_default'),
        initFromFile: library
            .lookupFunction<_MtmdInitFromFileNative, _MtmdInitFromFileDart>(
              'mtmd_init_from_file',
            ),
        free: library.lookupFunction<_MtmdFreeNative, _MtmdFreeDart>(
          'mtmd_free',
        ),
        inputChunksInit: library
            .lookupFunction<
              _MtmdInputChunksInitNative,
              _MtmdInputChunksInitDart
            >('mtmd_input_chunks_init'),
        inputChunksFree: library
            .lookupFunction<
              _MtmdInputChunksFreeNative,
              _MtmdInputChunksFreeDart
            >('mtmd_input_chunks_free'),
        helperBitmapInitFromFile: library
            .lookupFunction<
              _MtmdHelperBitmapInitFromFileNative,
              _MtmdHelperBitmapInitFromFileDart
            >('mtmd_helper_bitmap_init_from_file'),
        helperBitmapInitFromBuf: library
            .lookupFunction<
              _MtmdHelperBitmapInitFromBufNative,
              _MtmdHelperBitmapInitFromBufDart
            >('mtmd_helper_bitmap_init_from_buf'),
        bitmapInitFromAudio: library
            .lookupFunction<
              _MtmdBitmapInitFromAudioNative,
              _MtmdBitmapInitFromAudioDart
            >('mtmd_bitmap_init_from_audio'),
        bitmapFree: library
            .lookupFunction<_MtmdBitmapFreeNative, _MtmdBitmapFreeDart>(
              'mtmd_bitmap_free',
            ),
        tokenize: library
            .lookupFunction<_MtmdTokenizeNative, _MtmdTokenizeDart>(
              'mtmd_tokenize',
            ),
        helperEvalChunks: library
            .lookupFunction<
              _MtmdHelperEvalChunksNative,
              _MtmdHelperEvalChunksDart
            >('mtmd_helper_eval_chunks'),
      );
    } catch (_) {
      return null;
    }
  }
}

// --- Native Wrappers ---

class _LlamaLoraWrapper {
  final Pointer<llama_adapter_lora> pointer;
  _LlamaLoraWrapper(this.pointer);
  void dispose() {
    llama_adapter_lora_free(pointer);
  }
}

class _LlamaModelWrapper {
  final Pointer<llama_model> pointer;
  _LlamaModelWrapper(this.pointer);
  void dispose() {
    llama_model_free(pointer);
  }
}

class _LlamaContextWrapper {
  final Pointer<llama_context> pointer;
  final _LlamaModelWrapper? _modelKeepAlive;
  _LlamaContextWrapper(this.pointer, this._modelKeepAlive);
  void dispose() {
    // ignore: unused_local_variable
    final _ = _modelKeepAlive;
    llama_free(pointer);
  }
}
