import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

// Constants for release
// This should match the pinned llama.cpp submodule tag in third_party/llama_cpp
const _llamaCppTag = 'b7883';
const _baseUrl =
    'https://github.com/leehack/llamadart/releases/download/$_llamaCppTag';

void main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(
    (r) => print('${r.level.name}: ${r.time}: ${r.message}'),
  );
  final log = Logger('llamadart_hook');

  await build(args, (input, output) async {
    final code = input.config.code;
    final (os, arch) = (code.targetOS, code.targetArchitecture);

    log.info('Hook Start: $os-$arch');

    try {
      final preferredLinkMode = code.linkModePreference;
      // Allow dynamic linking on all platforms if requested by the build tool.
      // This is necessary because Flutter's build process for iOS and Android
      // often mandates dynamic linking for native assets.
      final bool useShared = preferredLinkMode == LinkModePreference.dynamic;

      // 1. Resolve Platform Configuration
      final isSimulator =
          os == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator;

      final (relPath, archFileName) = switch ((os, arch)) {
        (OS.windows, _) => ('windows/x64', 'libllamadart.dll'),
        (OS.linux, Architecture.arm64) => ('linux/arm64', 'libllamadart.so'),
        (OS.linux, Architecture.x64) => ('linux/x64', 'libllamadart.so'),
        (OS.macOS, _) => (
          'macos/${arch.name}',
          useShared
              ? 'libllamadart-macos-${arch.name}.dylib'
              : 'libllamadart-macos-${arch.name}.a',
        ),
        (OS.android, Architecture.arm64) => (
          'android/arm64',
          'libllamadart.so',
        ),
        (OS.android, Architecture.x64) => ('android/x64', 'libllamadart.so'),
        (OS.iOS, _) => ('ios', _getIOSFileName(isSimulator, arch, useShared)),
        _ => (null, null),
      };

      if (relPath == null || archFileName == null) {
        log.warning('Unsupported platform: $os-$arch');
        return;
      }

      // 2. Hybrid Search Strategy
      final localBinDir = path.join(
        input.packageRoot.toFilePath(),
        'third_party',
        'bin',
        relPath,
      );
      final localAssetPath = path.join(localBinDir, archFileName);

      final cacheDir = path.join(
        input.packageRoot.toFilePath(),
        '.dart_tool',
        'llamadart',
        'binaries',
        relPath,
      );
      final cacheAssetPath = path.join(cacheDir, archFileName);

      String? finalAssetPath;

      if (_exists(localAssetPath)) {
        log.info('Using local binary: $localAssetPath');
        finalAssetPath = localAssetPath;
      } else {
        log.info('Local binary not found, ensuring cached assets...');
        await _ensureAssets(
          targetDir: cacheDir,
          os: os,
          arch: arch,
          log: log,
          isSimulator: isSimulator,
          useShared: useShared,
        );
        if (_exists(cacheAssetPath)) {
          finalAssetPath = cacheAssetPath;
        }
      }

      if (finalAssetPath == null) {
        log.severe('Missing Asset: $archFileName for $os-$arch');
        return;
      }

      // 3. Standardize Filename for Flutter/Dart
      // We copy the arch-specific file to a generic name so the Asset ID and
      // Framework name (on Apple) are consistent.
      // On Apple, we remove 'lib' prefix to avoid Flutter creating 'libllamadart.framework'.
      final extension = useShared
          ? (os == OS.windows
                ? 'dll'
                : (os == OS.macOS || os == OS.iOS ? 'dylib' : 'so'))
          : 'a';
      final genericFileName = (os == OS.macOS || os == OS.iOS)
          ? 'llamadart.$extension'
          : (os == OS.windows ? 'libllamadart.dll' : 'libllamadart.$extension');

      final reportDir = path.join(
        input.outputDirectory.toFilePath(),
        'llamadart_bin',
      );
      if (!Directory(reportDir).existsSync()) {
        await Directory(reportDir).create(recursive: true);
      }

      final reportedAssetPath = path.join(reportDir, genericFileName);
      await File(finalAssetPath).copy(reportedAssetPath);

      // 4. MacOS/iOS Thinning (if needed)
      if (os == OS.macOS && reportedAssetPath.endsWith('.dylib')) {
        await _thinBinary(reportedAssetPath, arch, log);
      }

      // 5. Report Asset
      final absoluteAssetPath = path.absolute(reportedAssetPath);
      final linkMode = useShared ? DynamicLoadingBundled() : StaticLinking();
      log.info('Reporting: $absoluteAssetPath');
      log.info('Link Mode: ${useShared ? "Dynamic" : "Static"}');

      output.assets.code.add(
        CodeAsset(
          package: 'llamadart',
          name: 'llamadart',
          linkMode: linkMode,
          file: Uri.file(absoluteAssetPath),
        ),
      );
    } catch (e, st) {
      log.severe('FATAL ERROR in hook', e, st);
      rethrow;
    }
  });
}

String _getIOSFileName(bool isSimulator, Architecture arch, bool useShared) {
  final ext = useShared ? 'dylib' : 'a';
  if (arch == Architecture.x64) return 'libllamadart-ios-x86_64-sim.$ext';

  if (isSimulator) {
    return 'libllamadart-ios-arm64-sim.$ext';
  }
  return 'libllamadart-ios-arm64.$ext';
}

bool _exists(String p) => File(p).existsSync() || Directory(p).existsSync();

Future<void> _ensureAssets({
  required String targetDir,
  required OS os,
  required Architecture arch,
  required Logger log,
  required bool isSimulator,
  required bool useShared,
}) async {
  final dir = Directory(targetDir);
  if (!dir.existsSync()) await dir.create(recursive: true);

  switch (os) {
    case OS.iOS:
      final fileName = _getIOSFileName(isSimulator, arch, useShared);
      await _download(fileName, path.join(targetDir, fileName), log);
    case OS.macOS:
      final archStr = arch == Architecture.arm64 ? 'arm64' : 'x86_64';
      final ext = useShared ? 'dylib' : 'a';
      await _download(
        'libllamadart-macos-$archStr.$ext',
        path.join(targetDir, 'libllamadart-macos-$archStr.$ext'),
        log,
      );
    case OS.windows:
      await _download(
        'libllamadart-windows-x64.dll',
        path.join(targetDir, 'libllamadart.dll'),
        log,
      );
    case OS.linux:
    case OS.android:
      final osStr = os == OS.android ? 'android' : 'linux';
      final archStr = arch == Architecture.arm64 ? 'arm64' : 'x64';
      await _download(
        'libllamadart-$osStr-$archStr.so',
        path.join(targetDir, 'libllamadart.so'),
        log,
      );
    default:
      throw UnsupportedError('Unsupported OS: $os');
  }
}

Future<void> _download(String assetName, String destPath, Logger log) async {
  final file = File(destPath);
  if (file.existsSync()) return;

  final url = '$_baseUrl/$assetName';
  log.info('Downloading $url...');
  final res = await http.get(Uri.parse(url));

  if (res.statusCode != 200) {
    // Fallback logic for name transition
    final oldAssetName = assetName.replaceAll('llamadart', 'llama');
    if (oldAssetName != assetName) {
      log.warning('Trying fallback $oldAssetName');
      final oldUrl = '$_baseUrl/$oldAssetName';
      final oldRes = await http.get(Uri.parse(oldUrl));
      if (oldRes.statusCode == 200) {
        await file.writeAsBytes(oldRes.bodyBytes);
        return;
      }
    }
    throw Exception('Failed to download $url (${res.statusCode})');
  }
  await file.writeAsBytes(res.bodyBytes);
  log.info('Saved to $destPath');
}

Future<void> _thinBinary(
  String binaryPath,
  Architecture arch,
  Logger log,
) async {
  final info = await Process.run('lipo', ['-info', binaryPath]);
  final stdout = info.stdout.toString();
  if (!stdout.contains('Architectures in the fat file')) return;

  final archName = arch == Architecture.arm64 ? 'arm64' : 'x86_64';

  if (stdout.contains(archName)) {
    log.info('Thinning binary to $archName...');
    final tempPath = '$binaryPath.thin';
    await Process.run('lipo', [
      '-thin',
      archName,
      binaryPath,
      '-output',
      tempPath,
    ]);
    await File(tempPath).rename(binaryPath);
  }
}
