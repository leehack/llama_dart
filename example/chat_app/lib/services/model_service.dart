import 'dart:io' if (dart.library.js_interop) '../stub/io_stub.dart';
import 'package:dio/dio.dart';
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
      bool exists = file.existsSync() && file.lengthSync() > 0;

      if (exists && model.isMultimodal && model.mmprojFilename != null) {
        final mmFile = File(p.join(modelsDirPath, model.mmprojFilename!));
        exists = mmFile.existsSync() && mmFile.lengthSync() > 0;
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
  }) async {
    final savePath = p.join(modelsDir, model.filename);

    try {
      // 1. Download base model
      await _dio.download(
        model.url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            // If multimodal, this is 70% of progress
            double baseProgress = received / total;
            if (model.isMultimodal) {
              onProgress(baseProgress * 0.7);
            } else {
              onProgress(baseProgress);
            }
          }
        },
      );

      // 2. Download mmproj if needed
      if (model.isMultimodal &&
          model.mmprojUrl != null &&
          model.mmprojFilename != null) {
        final mmSavePath = p.join(modelsDir, model.mmprojFilename!);
        await _dio.download(
          model.mmprojUrl!,
          mmSavePath,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              // Remaining 30%
              onProgress(0.7 + (received / total * 0.3));
            }
          },
        );
      }

      onSuccess(model.filename);
    } catch (e) {
      final file = File(savePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
      if (model.mmprojFilename != null) {
        final mmFile = File(p.join(modelsDir, model.mmprojFilename!));
        if (mmFile.existsSync()) {
          mmFile.deleteSync();
        }
      }
      onError(e);
    }
  }

  Future<void> deleteModel(String modelsDir, DownloadableModel model) async {
    final path = p.join(modelsDir, model.filename);
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }

    if (model.mmprojFilename != null) {
      final mmPath = p.join(modelsDir, model.mmprojFilename!);
      final mmFile = File(mmPath);
      if (mmFile.existsSync()) {
        await mmFile.delete();
      }
    }
  }
}
