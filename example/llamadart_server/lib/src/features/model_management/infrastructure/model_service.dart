import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Resolves a model path or downloads a model URL into local cache.
class ModelService {
  /// Directory where downloaded model files are cached.
  final String cacheDir;

  /// Creates a model service with optional custom [cacheDir].
  ModelService([String? cacheDir])
    : cacheDir = cacheDir ?? path.join(Directory.current.path, 'models');

  /// Ensures [urlOrPath] exists locally, downloading when needed.
  Future<File> ensureModel(String urlOrPath) async {
    if (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')) {
      return _downloadModel(urlOrPath);
    }

    final file = File(urlOrPath);
    if (!file.existsSync()) {
      throw Exception('Model file not found at: $urlOrPath');
    }

    return file;
  }

  Future<File> _downloadModel(String url) async {
    final fileName = url.split('/').last.split('?').first;
    final file = File(path.join(cacheDir, fileName));

    if (file.existsSync() && file.lengthSync() > 0) {
      return file;
    }

    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    stdout.writeln('Downloading model: $fileName');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != HttpStatus.ok) {
        throw Exception(
          'Failed to download model: '
          '${response.statusCode} ${response.reasonPhrase}',
        );
      }

      final contentLength = response.contentLength ?? 0;
      var downloaded = 0;
      final sink = file.openWrite();

      await response.stream
          .listen(
            (List<int> chunk) {
              sink.add(chunk);
              downloaded += chunk.length;

              if (contentLength > 0) {
                final progress = (downloaded / contentLength * 100)
                    .toStringAsFixed(1);
                stdout.write('\rProgress: $progress%');
              } else {
                final mb = (downloaded / 1024 / 1024).toStringAsFixed(1);
                stdout.write('\rDownloaded: $mb MB');
              }
            },
            onDone: () async {
              await sink.close();
              stdout.writeln('\nDownload complete.');
            },
            onError: (Object error) {
              sink.close();
              if (file.existsSync()) {
                file.deleteSync();
              }
              throw error;
            },
          )
          .asFuture<void>();

      return file;
    } finally {
      client.close();
    }
  }
}
