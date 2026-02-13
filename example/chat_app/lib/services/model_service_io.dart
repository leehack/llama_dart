import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/downloadable_model.dart';
import 'model_service_base.dart';

class ModelServiceIO implements ModelService {
  final Dio _dio = Dio();

  @override
  Future<String> getModelsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(dir.path, 'models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir.path;
  }

  @override
  Future<Set<String>> getDownloadedModels(
    List<DownloadableModel> models,
  ) async {
    final dirPath = await getModelsDirectory();
    final Set<String> downloaded = {};

    for (final model in models) {
      final modelFile = File(p.join(dirPath, model.filename));
      final partialFile = File(p.join(dirPath, '${model.filename}.download'));
      final legacyMeta = File(p.join(dirPath, '${model.filename}.meta'));
      final hasRequiredMmproj =
          model.mmprojFilename == null ||
          await File(p.join(dirPath, model.mmprojFilename!)).exists();

      if (await modelFile.exists() &&
          !await partialFile.exists() &&
          !await legacyMeta.exists() &&
          hasRequiredMmproj) {
        downloaded.add(model.filename);
      }
    }

    return downloaded;
  }

  @override
  Future<void> downloadModel({
    required DownloadableModel model,
    required String modelsDir,
    required CancelToken cancelToken,
    required Function(double progress) onProgress,
    required Function(String filename) onSuccess,
    required Function(dynamic error) onError,
  }) async {
    final savePath = p.join(modelsDir, model.filename);
    final tempPath = '$savePath.download';

    try {
      // Check if partial download exists to resume
      int startByte = 0;
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        startByte = await tempFile.length();
      }

      await _dio.download(
        model.url,
        tempPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress((received + startByte) / (total + startByte));
          }
        },
        options: Options(
          headers: startByte > 0 ? {'range': 'bytes=$startByte-'} : null,
          responseType: ResponseType.stream,
        ),
        deleteOnError: false,
      );

      // Successfully downloaded, rename temp file
      await tempFile.rename(savePath);

      // If it's a multimodal model, also download the mmproj file if it exists
      if (model.mmprojUrl != null && model.mmprojFilename != null) {
        final mmprojSavePath = p.join(modelsDir, model.mmprojFilename!);
        await _dio.download(model.mmprojUrl!, mmprojSavePath);
      }

      onSuccess(model.filename);
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        // Just paused, keep the temp file
      } else {
        // Actual error, maybe delete temp file or keep for next retry?
        // For now, let's keep it and see if Dio handles resume.
      }
      onError(e);
    }
  }

  @override
  Future<void> deleteModel(String modelsDir, DownloadableModel model) async {
    final file = File(p.join(modelsDir, model.filename));
    if (await file.exists()) {
      await file.delete();
    }

    final tempFile = File(p.join(modelsDir, '${model.filename}.download'));
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    if (model.mmprojFilename != null) {
      final mmprojFile = File(p.join(modelsDir, model.mmprojFilename!));
      if (await mmprojFile.exists()) {
        await mmprojFile.delete();
      }
    }
  }
}

ModelService createModelService() => ModelServiceIO();
