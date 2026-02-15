import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'llama_cli_config.dart';

/// Parsed value for llama.cpp-style `-hf repo[:file-hint]`.
class HfModelSpec {
  /// Hugging Face repository, for example `unsloth/GLM-4.7-Flash-GGUF`.
  final String repository;

  /// Optional file name or quant hint after `:`.
  final String? fileHint;

  /// Creates a parsed Hugging Face model spec.
  const HfModelSpec({required this.repository, this.fileHint});

  /// Parses shorthand `repo[:hint]` syntax.
  static HfModelSpec parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw const FormatException('Hugging Face spec cannot be empty.');
    }

    final separatorIndex = value.indexOf(':');
    final repository = separatorIndex == -1
        ? value
        : value.substring(0, separatorIndex).trim();
    final hint = separatorIndex == -1
        ? null
        : value.substring(separatorIndex + 1).trim();

    if (repository.isEmpty || !repository.contains('/')) {
      throw FormatException(
        'Invalid Hugging Face repo: "$repository". Expected owner/repo.',
      );
    }

    return HfModelSpec(
      repository: repository,
      fileHint: hint == null || hint.isEmpty ? null : hint,
    );
  }
}

/// Streaming progress state for model downloads.
class DownloadProgress {
  /// Number of bytes received.
  final int receivedBytes;

  /// Expected total bytes, if known.
  final int? totalBytes;

  /// Creates a progress snapshot.
  const DownloadProgress({required this.receivedBytes, this.totalBytes});

  /// Fraction in [0.0, 1.0], or null when total size is unknown.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }

    final ratio = receivedBytes / total;
    if (ratio < 0) {
      return 0;
    }
    if (ratio > 1) {
      return 1;
    }
    return ratio;
  }
}

/// Resolves CLI model references to a local GGUF file path.
class ModelLocator {
  final String _modelsDirectory;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  /// Creates a model locator bound to a cache directory.
  ModelLocator({required String modelsDirectory, http.Client? httpClient})
    : _modelsDirectory = modelsDirectory,
      _httpClient = httpClient ?? http.Client(),
      _ownsHttpClient = httpClient == null;

  /// Releases internal network resources when applicable.
  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  /// Resolves the configured model source and returns a local file path.
  Future<String> resolve(
    LlamaCliConfig config, {
    void Function(String status)? onStatus,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final explicitModel = config.modelPathOrUrl;
    if (explicitModel != null) {
      return _resolveDirectSource(
        explicitModel,
        onStatus: onStatus,
        onProgress: onProgress,
      );
    }

    final hfSpec = config.huggingFaceSpec;
    if (hfSpec != null) {
      return _resolveHfSource(
        hfSpec,
        onStatus: onStatus,
        onProgress: onProgress,
      );
    }

    throw StateError('No model source configured.');
  }

  Future<String> _resolveDirectSource(
    String source, {
    void Function(String status)? onStatus,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    if (_isHttpUrl(source)) {
      return _downloadIfNeeded(
        Uri.parse(source),
        onStatus: onStatus,
        onProgress: onProgress,
      );
    }

    final file = File(source);
    if (!file.existsSync()) {
      throw FileSystemException('Model file not found', source);
    }

    return file.absolute.path;
  }

  Future<String> _resolveHfSource(
    String rawSpec, {
    void Function(String status)? onStatus,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final spec = HfModelSpec.parse(rawSpec);

    final selectedFileName = await _resolveHfFileName(spec);
    final downloadUri = _buildHfDownloadUri(spec.repository, selectedFileName);

    onStatus?.call('Resolved $rawSpec to $selectedFileName');
    return _downloadIfNeeded(
      downloadUri,
      forceFilename: p.basename(selectedFileName),
      onStatus: onStatus,
      onProgress: onProgress,
    );
  }

  Future<String> _resolveHfFileName(HfModelSpec spec) async {
    final hint = spec.fileHint;
    if (hint != null && hint.toLowerCase().endsWith('.gguf')) {
      return hint;
    }

    final uri = Uri.https('huggingface.co', '/api/models/${spec.repository}');
    final response = await _httpClient.get(uri);

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Failed to inspect Hugging Face repo ${spec.repository} '
        '(HTTP ${response.statusCode}).',
        uri: uri,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected Hugging Face API response body.');
    }

    final siblings = decoded['siblings'];
    if (siblings is! List) {
      throw const FormatException('Missing siblings list in Hugging Face API.');
    }

    final files = <String>[];
    for (final item in siblings) {
      if (item is Map<String, dynamic>) {
        final filename = item['rfilename'];
        if (filename is String && filename.isNotEmpty) {
          files.add(filename);
        }
      }
    }

    return selectBestGgufFile(files, hint: hint);
  }

  Uri _buildHfDownloadUri(String repository, String filename) {
    final segments = <String>[
      ...repository.split('/').where((segment) => segment.isNotEmpty),
      'resolve',
      'main',
      ...filename.split('/').where((segment) => segment.isNotEmpty),
    ];

    final path = '/${segments.join('/')}';
    return Uri.https('huggingface.co', path, {'download': 'true'});
  }

  Future<String> _downloadIfNeeded(
    Uri uri, {
    String? forceFilename,
    void Function(String status)? onStatus,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final modelsDir = Directory(_modelsDirectory);
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    final filename = forceFilename ?? _filenameFromUri(uri);
    final targetFile = File(p.join(modelsDir.path, filename));
    final tempFile = File('${targetFile.path}.download');

    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      final bytes = targetFile.lengthSync();
      onProgress?.call(
        DownloadProgress(receivedBytes: bytes, totalBytes: bytes),
      );
      return targetFile.absolute.path;
    }

    var resumeOffset = tempFile.existsSync() ? tempFile.lengthSync() : 0;
    final request = http.Request('GET', uri);
    if (resumeOffset > 0) {
      request.headers[HttpHeaders.rangeHeader] = 'bytes=$resumeOffset-';
    }

    onStatus?.call('Downloading $filename');
    final response = await _httpClient.send(request);
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw HttpException(
        'Failed to download model (HTTP ${response.statusCode}).',
        uri: uri,
      );
    }

    final appendMode =
        response.statusCode == HttpStatus.partialContent && resumeOffset > 0;

    if (!appendMode) {
      resumeOffset = 0;
    }

    final contentLength = response.contentLength;
    final total = contentLength == null || contentLength <= 0
        ? null
        : contentLength + (appendMode ? resumeOffset : 0);

    final sink = tempFile.openWrite(
      mode: appendMode ? FileMode.append : FileMode.write,
    );

    try {
      var received = resumeOffset;
      if (received > 0) {
        onProgress?.call(
          DownloadProgress(receivedBytes: received, totalBytes: total),
        );
      }

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          DownloadProgress(receivedBytes: received, totalBytes: total),
        );
      }

      await sink.flush();
    } finally {
      await sink.close();
    }

    if (targetFile.existsSync()) {
      await targetFile.delete();
    }

    await tempFile.rename(targetFile.path);
    final finalBytes = targetFile.lengthSync();
    onProgress?.call(
      DownloadProgress(
        receivedBytes: finalBytes,
        totalBytes: total ?? finalBytes,
      ),
    );
    return targetFile.absolute.path;
  }

  bool _isHttpUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  String _filenameFromUri(Uri uri) {
    if (uri.pathSegments.isEmpty) {
      return 'model.gguf';
    }

    final rawName = uri.pathSegments.last;
    if (rawName.isEmpty) {
      return 'model.gguf';
    }

    return rawName;
  }
}

/// Chooses the best `.gguf` filename from repo file listings.
String selectBestGgufFile(List<String> files, {String? hint}) {
  final ggufFiles = files
      .where((name) => name.toLowerCase().endsWith('.gguf'))
      .toList(growable: false);

  if (ggufFiles.isEmpty) {
    throw const FormatException('No GGUF files found in Hugging Face repo.');
  }

  if (hint == null || hint.trim().isEmpty) {
    final sorted = ggufFiles.toList()..sort();
    return sorted.first;
  }

  final normalizedHint = _normalizeHint(hint);
  final exactNeedle = hint.toLowerCase().endsWith('.gguf')
      ? hint.toLowerCase()
      : '${hint.toLowerCase()}.gguf';

  final exactMatches = ggufFiles
      .where((file) => file.toLowerCase() == exactNeedle)
      .toList(growable: false);
  if (exactMatches.isNotEmpty) {
    final sorted = exactMatches.toList()..sort();
    return sorted.first;
  }

  final normalizedMatches = ggufFiles
      .where((file) => _normalizeHint(file).contains(normalizedHint))
      .toList(growable: false);
  if (normalizedMatches.isEmpty) {
    throw FormatException(
      'No GGUF file matched "$hint". '
      'Available files: ${ggufFiles.join(', ')}',
    );
  }

  normalizedMatches.sort((a, b) {
    final byLength = a.length.compareTo(b.length);
    if (byLength != 0) {
      return byLength;
    }
    return a.compareTo(b);
  });
  return normalizedMatches.first;
}

String _normalizeHint(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
