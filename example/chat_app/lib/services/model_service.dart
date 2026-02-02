import 'dart:io' if (dart.library.js_interop) '../stub/io_stub.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/downloadable_model.dart';

class ModelService {
  final Dio _dio = Dio();

  Future<String> getModelsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(dir.path, 'models'));
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }
    return modelsDir.path;
  }

  Future<Set<String>> getDownloadedModels(
    List<DownloadableModel> models,
  ) async {
    final modelsDirPath = await getModelsDirectory();
    final downloaded = <String>{};

    for (var model in models) {
      final file = File(p.join(modelsDirPath, model.filename));
      final metaFile = File('${file.path}.meta');
      bool exists =
          file.existsSync() && file.lengthSync() > 0 && !metaFile.existsSync();

      if (exists && model.isMultimodal && model.mmprojFilename != null) {
        final mmFile = File(p.join(modelsDirPath, model.mmprojFilename!));
        final mmMetaFile = File('${mmFile.path}.meta');
        exists =
            mmFile.existsSync() &&
            mmFile.lengthSync() > 0 &&
            !mmMetaFile.existsSync();
      }

      if (exists) {
        downloaded.add(model.filename);
      }
    }
    return downloaded;
  }

  Future<void> downloadModel({
    required DownloadableModel model,
    required String modelsDir,
    required Function(double) onProgress,
    required Function(String) onSuccess,
    required Function(dynamic) onError,
    CancelToken? cancelToken,
  }) async {
    final savePath = p.join(modelsDir, model.filename);

    try {
      // 1. Download base model (Parallel with fallback)
      await _downloadFile(
        url: model.url,
        savePath: savePath,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (total != -1) {
            double baseProgress = received / total;
            if (model.isMultimodal && model.supportsVision) {
              onProgress(baseProgress * 0.7);
            } else {
              onProgress(baseProgress);
            }
          }
        },
      );

      // 2. Download mmproj if needed (Parallel with fallback)
      if (model.isMultimodal &&
          model.mmprojUrl != null &&
          model.mmprojFilename != null) {
        final mmSavePath = p.join(modelsDir, model.mmprojFilename!);
        await _downloadFile(
          url: model.mmprojUrl!,
          savePath: mmSavePath,
          cancelToken: cancelToken,
          onProgress: (received, total) {
            if (total != -1) {
              onProgress(0.7 + (received / total * 0.3));
            }
          },
        );
      }

      onSuccess(model.filename);
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        debugPrint('Download canceled: ${model.filename}');
      }
      // No cleanup on error to allow resuming
      onError(e);
    }
  }

  Future<void> _downloadFile({
    required String url,
    required String savePath,
    required Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      await _downloadFileParallel(url, savePath, onProgress, cancelToken);
    } on _ParallelNotSupportedException catch (e) {
      debugPrint(
        'Parallel download not supported: $e. Falling back to serial download.',
      );
      await _downloadFileSerial(url, savePath, onProgress, cancelToken);
    } catch (e) {
      // For other errors (network interrupted, disk full), we rethrow
      // to preserve the partial state for resuming later.
      rethrow;
    }
  }

  Future<void> _downloadFileSerial(
    String url,
    String savePath,
    Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  ) async {
    try {
      await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received, total);
          }
        },
        deleteOnError: true,
      );
    } catch (e) {
      // Double check cleanup
      final f = File(savePath);
      if (f.existsSync()) f.deleteSync();
      rethrow;
    }
  }

  Future<void> _downloadFileParallel(
    String url,
    String savePath,
    Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  ) async {
    // Sanitize URL for HEAD request
    final uri = Uri.parse(url);
    final headUrl = uri.replace(queryParameters: {}).toString();

    Response<dynamic> headResponse;
    try {
      headResponse = await _dio.head(headUrl, cancelToken: cancelToken);
    } catch (e) {
      try {
        headResponse = await _dio.head(url, cancelToken: cancelToken);
      } catch (_) {
        if (CancelToken.isCancel(e as dynamic)) rethrow;
        throw _ParallelNotSupportedException(
          "HEAD request failed for $url: $e",
        );
      }
    }

    final totalBytes = int.parse(
      headResponse.headers.value('content-length') ?? '0',
    );

    if (totalBytes == 0) {
      throw _ParallelNotSupportedException('Failed to get content length');
    }

    // Initialize or load state
    final metaFile = File('$savePath.meta');
    final file = File(savePath);
    List<_Chunk> chunks;

    if (metaFile.existsSync() && file.existsSync()) {
      try {
        final lines = await metaFile.readAsLines();
        chunks = lines.map((line) {
          final parts = line.split(',');
          return _Chunk(
            start: int.parse(parts[0]),
            end: int.parse(parts[1]),
            downloaded: int.parse(parts[2]),
          );
        }).toList();

        // Verify validity
        final expectedSize = chunks.fold<int>(
          0,
          (sum, chunk) => sum + (chunk.end - chunk.start + 1),
        );
        if (expectedSize != totalBytes) {
          throw Exception('Metadata size mismatch');
        }
      } catch (e) {
        debugPrint('Resume failed ($e), starting fresh.');
        chunks = _createChunks(totalBytes);
        await _saveMetadata(metaFile, chunks);
        if (file.existsSync()) await file.delete();
        await file.create(recursive: true);
        final raf = await file.open(mode: FileMode.write);
        await raf.truncate(totalBytes);
        await raf.close();
      }
    } else {
      chunks = _createChunks(totalBytes);
      await _saveMetadata(metaFile, chunks);
      if (!file.existsSync()) {
        await file.create(recursive: true);
      }
      final raf = await file.open(mode: FileMode.write);
      await raf.truncate(totalBytes);
      await raf.close();
    }

    int receivedBytes = chunks.fold(0, (sum, chunk) => sum + chunk.downloaded);
    // Initial progress update
    onProgress(receivedBytes, totalBytes);

    final futures = <Future>[];
    // Track update frequency for metadata
    DateTime lastSave = DateTime.now();

    void updateProgress(int chunkIndex, int bytes) {
      chunks[chunkIndex].downloaded += bytes;
      receivedBytes += bytes;
      onProgress(receivedBytes, totalBytes);

      // Throttle metadata saves to once per second
      final now = DateTime.now();
      if (now.difference(lastSave) > const Duration(seconds: 1)) {
        lastSave = now;
        _saveMetadata(metaFile, chunks);
      }
    }

    for (int i = 0; i < chunks.length; i++) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.cancel,
        );
      }

      final chunk = chunks[i];
      if (chunk.downloaded < (chunk.end - chunk.start + 1)) {
        futures.add(
          _downloadChunk(
            url: url,
            start: chunk.start,
            end: chunk.end,
            file: file,
            initialOffset: chunk.downloaded,
            onChunkProgress: (bytes) => updateProgress(i, bytes),
            cancelToken: cancelToken,
          ),
        );
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    // Final clean up
    if (metaFile.existsSync()) {
      await metaFile.delete();
    }
  }

  List<_Chunk> _createChunks(int totalBytes) {
    const int chunksCount = 4;
    final int chunkSize = (totalBytes / chunksCount).ceil();
    final chunks = <_Chunk>[];

    for (int i = 0; i < chunksCount; i++) {
      final start = i * chunkSize;
      final end = (i == chunksCount - 1)
          ? totalBytes - 1
          : (start + chunkSize - 1);
      chunks.add(_Chunk(start: start, end: end, downloaded: 0));
    }
    return chunks;
  }

  Future<void> _saveMetadata(File metaFile, List<_Chunk> chunks) async {
    // Simple CSV format: start,end,downloaded
    final content = chunks
        .map((c) => '${c.start},${c.end},${c.downloaded}')
        .join('\n');
    await metaFile.writeAsString(content, flush: true);
  }

  Future<void> _downloadChunk({
    required String url,
    required int start,
    required int end,
    required File file,
    required int initialOffset,
    required Function(int) onChunkProgress,
    CancelToken? cancelToken,
  }) async {
    final raf = await file.open(mode: FileMode.append);

    try {
      final requestStart = start + initialOffset;
      if (requestStart > end) return; // Already done

      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: {'range': 'bytes=$requestStart-$end'},
          responseType: ResponseType.stream,
        ),
      );

      final stream = response.data!.stream;
      int currentOffset = requestStart;

      await for (final chunk in stream) {
        if (cancelToken?.isCancelled ?? false) {
          throw DioException(
            requestOptions: RequestOptions(path: url),
            type: DioExceptionType.cancel,
          );
        }
        await raf.setPosition(currentOffset);
        await raf.writeFrom(chunk);
        currentOffset += chunk.length;
        onChunkProgress(chunk.length);
      }
    } finally {
      await raf.close();
    }
  }

  Future<void> deleteModel(String modelsDir, DownloadableModel model) async {
    final path = p.join(modelsDir, model.filename);
    final file = File(path);
    if (file.existsSync()) await file.delete();
    final meta = File('$path.meta');
    if (meta.existsSync()) await meta.delete();

    if (model.mmprojFilename != null) {
      final mmPath = p.join(modelsDir, model.mmprojFilename!);
      final mmFile = File(mmPath);
      if (mmFile.existsSync()) await mmFile.delete();
      final mmMeta = File('$mmPath.meta');
      if (mmMeta.existsSync()) await mmMeta.delete();
    }
  }
}

class _ParallelNotSupportedException implements Exception {
  final String message;
  _ParallelNotSupportedException(this.message);
  @override
  String toString() => 'ParallelNotSupportedException: $message';
}

class _Chunk {
  final int start;
  final int end;
  int downloaded;

  _Chunk({required this.start, required this.end, required this.downloaded});
}
