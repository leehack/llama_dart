import 'dart:io';

Future<void> main() async {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final projectRoot = scriptDir.parent;
  final llamaCppDir = Directory('${projectRoot.path}/src/native/llama_cpp');
  final outputDir = Directory('${projectRoot.path}/ios/Frameworks');

  // Build Directories (using /tmp for writability)
  final baseBuildDir = Directory('/tmp/llamadart_build_ios');
  final buildDirDevice = Directory('${baseBuildDir.path}/device');
  final buildDirSimArm64 = Directory('${baseBuildDir.path}/sim-arm64');
  final buildDirSimX86 = Directory('${baseBuildDir.path}/sim-x86');

  print('Cleaning previous builds...');
  if (Directory('${outputDir.path}/llama_cpp.xcframework').existsSync()) {
    Directory('${outputDir.path}/llama_cpp.xcframework')
        .deleteSync(recursive: true);
  }
  if (baseBuildDir.existsSync()) {
    baseBuildDir.deleteSync(recursive: true);
  }
  outputDir.createSync(recursive: true);
  baseBuildDir.createSync(recursive: true);

  // 1. Build for Device (arm64)
  await _buildPlatform(
    'Device',
    buildDirDevice,
    llamaCppDir,
    ['-DCMAKE_OSX_ARCHITECTURES=arm64', '-DGGML_METAL=ON'],
  );

  // 2. Build for Simulator (arm64)
  await _buildPlatform(
    'Simulator-arm64',
    buildDirSimArm64,
    llamaCppDir,
    ['-DCMAKE_OSX_SYSROOT=iphonesimulator', '-DCMAKE_OSX_ARCHITECTURES=arm64'],
  );

  // 3. Build for Simulator (x86_64)
  await _buildPlatform(
    'Simulator-x86_64',
    buildDirSimX86,
    llamaCppDir,
    ['-DCMAKE_OSX_SYSROOT=iphonesimulator', '-DCMAKE_OSX_ARCHITECTURES=x86_64'],
  );

  print('Creating XCFramework...');

  // Merge libs for each platform
  final deviceLibDir = Directory('${baseBuildDir.path}/device_final');
  final simLibDir = Directory('${baseBuildDir.path}/sim_final');
  deviceLibDir.createSync(recursive: true);
  simLibDir.createSync(recursive: true);

  final deviceLibPath = '${deviceLibDir.path}/libllama_cpp.a';
  final simArm64LibPath = '${baseBuildDir.path}/libllama_sim_arm64.a';
  final simX86LibPath = '${baseBuildDir.path}/libllama_sim_x86.a';
  final simLibPath = '${simLibDir.path}/libllama_cpp.a';

  await _mergeLibs(buildDirDevice, deviceLibPath);
  await _mergeLibs(buildDirSimArm64, simArm64LibPath);
  await _mergeLibs(buildDirSimX86, simX86LibPath);

  // Lipo the simulator libs into a universal static lib
  print('Creating universal simulator library...');
  await _runCommand('lipo', [
    '-create',
    simArm64LibPath,
    simX86LibPath,
    '-output',
    simLibPath,
  ]);

  // Prepare Headers directory for XCFramework
  final headersDir = Directory('${baseBuildDir.path}/headers');
  headersDir.createSync(recursive: true);
  await _copyHeaders(headersDir, llamaCppDir);

  // Create XCFramework using -library and -headers (Standard for static libs)
  print('Generating llama_cpp.xcframework...');
  await _runCommand('xcodebuild', [
    '-create-xcframework',
    '-library',
    deviceLibPath,
    '-headers',
    headersDir.path,
    '-library',
    simLibPath,
    '-headers',
    headersDir.path,
    '-output',
    '${outputDir.path}/llama_cpp.xcframework',
  ]);

  print(
      'iOS XCFramework Build Complete: ${outputDir.path}/llama_cpp.xcframework');
}

Future<void> _buildPlatform(
  String platformName,
  Directory buildDir,
  Directory llamaCppDir,
  List<String> cmakeArgs,
) async {
  print('Building llama.cpp for iOS $platformName...');
  buildDir.createSync(recursive: true);

  final args = [
    llamaCppDir.path,
    '-G',
    'Xcode',
    '-DCMAKE_SYSTEM_NAME=iOS',
    ...cmakeArgs,
    '-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0',
    '-DGGML_BLAS=OFF',
    '-DBUILD_SHARED_LIBS=OFF',
    '-DLLAMA_BUILD_TESTS=OFF',
    '-DLLAMA_BUILD_EXAMPLES=OFF',
    '-DLLAMA_BUILD_SERVER=OFF',
    '-DLLAMA_CURL=OFF',
    '-DGGML_OPENMP=OFF',
    '-DLLAMA_BUILD_COMMON=OFF',
    '-DLLAMA_BUILD_TOOLS=OFF',
    '-DGGML_METAL_EMBED_LIBRARY=ON',
  ];

  await _runCommand('cmake', args, workingDirectory: buildDir.path);

  await _runCommand(
    'cmake',
    [
      '--build',
      '.',
      '--config',
      'Release',
      '--target',
      'llama',
      '--target',
      'ggml',
      '--',
      '-allowProvisioningUpdates',
      'CODE_SIGNING_ALLOWED=NO'
    ],
    workingDirectory: buildDir.path,
  );
}

Future<void> _mergeLibs(Directory buildDir, String outputLib) async {
  print('Merging libraries from ${buildDir.path}...');

  final libsToMerge = <String>[];
  await for (final entity in buildDir.list(recursive: true)) {
    if (entity is File) {
      if (entity.path.endsWith('.a') && !entity.path.contains('/install/')) {
        libsToMerge.add(entity.path);
      }
    }
  }

  if (libsToMerge.isEmpty) {
    print('Error: No libraries found in ${buildDir.path}');
    exit(1);
  }

  print('Found libs: ${libsToMerge.join(', ')}');
  await _runCommand('libtool', ['-static', '-o', outputLib, ...libsToMerge]);
}

Future<void> _copyHeaders(Directory headersDir, Directory llamaCppDir) async {
  print('Copying headers to ${headersDir.path}...');
  final headerDirs = [
    Directory('${llamaCppDir.path}/include'),
    Directory('${llamaCppDir.path}/ggml/include'),
  ];

  for (final dir in headerDirs) {
    if (dir.existsSync()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.h')) {
          entity.copySync('${headersDir.path}/${entity.uri.pathSegments.last}');
        }
      }
    }
  }
}

Future<void> _runCommand(String executable, List<String> args,
    {String? workingDirectory}) async {
  final result =
      await Process.run(executable, args, workingDirectory: workingDirectory);
  if (result.exitCode != 0) {
    print('Error running $executable ${args.join(' ')}:');
    print(result.stdout);
    print(result.stderr);
    exit(1);
  }
}
