import 'dart:io';

Future<void> main(List<String> args) async {
  // Pin to a specific release tag (approx Jan 2026) to ensure stability
  final targetVersion = args.isNotEmpty ? args[0] : 'b7845';
  const repository = 'https://github.com/ggerganov/llama.cpp.git';
  final tempDir = Directory('temp_llama_cpp');
  final destDir = Directory('src/native/llama_cpp');

  print('llamadart: Vendoring llama.cpp ($targetVersion)...');

  // 1. Clean up old vendor directory
  if (destDir.existsSync()) {
    destDir.deleteSync(recursive: true);
  }
  destDir.createSync(recursive: true);

  // 2. Get Source using Sparse Checkout
  print('llamadart: Cloning $repository (sparse)...');
  if (tempDir.existsSync()) {
    tempDir.deleteSync(recursive: true);
  }
  tempDir.createSync(recursive: true);

  await _runGit(tempDir, ['init']);
  await _runGit(tempDir, ['remote', 'add', 'origin', repository]);
  await _runGit(tempDir, ['config', 'core.sparseCheckout', 'true']);

  final sparseCheckoutFile = File('${tempDir.path}/.git/info/sparse-checkout');
  final content = [
    'ggml/',
    'src/',
    'include/',
    'cmake/',
    'common/',
    'vendor/',
    'CMakeLists.txt',
    'LICENSE',
    'README.md',
  ];
  sparseCheckoutFile.writeAsStringSync('${content.join('\n')}\n');

  await _runGit(tempDir, ['fetch', '--depth', '1', 'origin', targetVersion]);
  await _runGit(tempDir, ['checkout', 'FETCH_HEAD']);

  // 3. Copy essential directories
  print('llamadart: Copying source files...');

  final dirsToCopy = ['ggml', 'src', 'include', 'cmake', 'common', 'vendor'];
  for (final sourceName in dirsToCopy) {
    await _copyDir(Directory('${tempDir.path}/$sourceName'),
        Directory('${destDir.path}/$sourceName'));
  }

  // Copy root files
  // Note: We now copy CMakeLists.txt directly without overwriting with a custom one.
  // The upstream CMakeLists.txt will be used.
  await File('${tempDir.path}/CMakeLists.txt')
      .copy('${destDir.path}/CMakeLists.txt');
  await File('${tempDir.path}/LICENSE').copy('${destDir.path}/LICENSE');
  await File('${tempDir.path}/README.md')
      .copy('${destDir.path}/README.upstream.md');

  // 4. Clean up the copied folders (tests, examples, build)
  print('llamadart: Cleaning up internal tests and examples...');
  await _deleteMatching(destDir, 'tests');
  await _deleteMatching(destDir, 'examples');
  await _deleteMatching(destDir, 'build');
  await _deleteMatching(destDir, 'pocs');
  await _deleteMatching(destDir, 'benches');
  // await _deleteMatching(destDir, 'models'); // Contains source code in master!
  await _deleteMatching(destDir, 'docs');
  await _deleteMatching(destDir, 'media');
  await _deleteMatching(destDir, 'grammars');
  await _deleteMatching(destDir, 'tools'); // Internal tools

  // 4b. Deep Cleanup (Unused Backends & Scripts)
  print('llamadart: Performing deep cleanup of unused backends...');
  final backendsToRemove = [
    'ggml/src/ggml-cann',
    'ggml/src/ggml-hexagon',
    'ggml/src/ggml-musa',
    'ggml/src/ggml-opencl',
    'ggml/src/ggml-rpc',
    'ggml/src/ggml-sycl',
    'ggml/src/ggml-webgpu',
    'ggml/src/ggml-zdnn',
    'ggml/src/ggml-zendnn',
  ];

  for (final backend in backendsToRemove) {
    final dir = Directory('${destDir.path}/$backend');
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  // Remove root level unused folders/files
  final rootRemovals = ['gguf-py', 'requirements', 'scripts'];
  for (final item in rootRemovals) {
    await _deleteMatching(destDir, item);
  }

  // Remove root python scripts
  await for (final entity in destDir.list(recursive: false)) {
    if (entity is File && entity.path.endsWith('.py')) {
      entity.deleteSync();
    }
  }

  // 5. No custom CMakeLists.txt generation!
  // We use the upstream CMakeLists.txt copied in step 3.
  print('llamadart: Using upstream CMakeLists.txt (Zero-Overwrite strategy).');

  // 6. No patches needed!
  // We rely on src/native/cmake/FindVulkan.cmake and parent CMake flags.
  print('llamadart: No source patches applied (using zero-patch strategy).');

  // 7. Final cleanup
  if (tempDir.existsSync()) {
    tempDir.deleteSync(recursive: true);
  }

  print('llamadart: Vendoring complete. Files are in ${destDir.path}.');
  print(
      'llamadart: Remember that CMake patches are now handled via src/native/cmake/FindVulkan.cmake.');
}

Future<void> _runGit(Directory cwd, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: cwd.path);
  if (result.exitCode != 0) {
    print('Error running git ${args.join(' ')}:');
    print(result.stderr);
    exit(1);
  }
}

Future<void> _copyDir(Directory source, Directory dest) async {
  if (!dest.existsSync()) {
    dest.createSync(recursive: true);
  }
  await for (final entity in source.list(recursive: false)) {
    final segment = entity.uri.pathSegments.last.isEmpty
        ? entity.uri.pathSegments[entity.uri.pathSegments.length - 2]
        : entity.uri.pathSegments.last;

    final newPath = dest.path + Platform.pathSeparator + segment;

    if (entity is Directory) {
      await _copyDir(entity, Directory(newPath));
    } else if (entity is File) {
      await entity.copy(newPath);
    }
  }
}

Future<void> _deleteMatching(Directory dir, String name) async {
  if (!dir.existsSync()) return;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is Directory && entity.path.endsWith('/$name')) {
      if (entity.existsSync()) {
        entity.deleteSync(recursive: true);
      }
    }
  }
}
