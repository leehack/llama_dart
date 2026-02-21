import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/downloadable_model.dart';
import 'model_service_base.dart';

class ModelServiceWeb implements ModelService {
  static const String _downloadedModelsKey = 'web_cached_models';
  final Dio _dio = Dio();

  @override
  Future<String> getModelsDirectory() async => 'browser-cache';

  @override
  Future<Set<String>> getDownloadedModels(
    List<DownloadableModel> models,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final downloaded = prefs.getStringList(_downloadedModelsKey) ?? const [];
    final valid = models.map((m) => m.filename).toSet();
    return downloaded.where(valid.contains).toSet();
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
    try {
      await _dio.get<List<int>>(
        model.url,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress(received / total);
          }
        },
      );

      if (model.mmprojUrl != null && model.mmprojUrl!.isNotEmpty) {
        await _dio.get<List<int>>(
          model.mmprojUrl!,
          cancelToken: cancelToken,
          options: Options(responseType: ResponseType.bytes),
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final downloaded =
          prefs.getStringList(_downloadedModelsKey) ?? <String>[];
      if (!downloaded.contains(model.filename)) {
        downloaded.add(model.filename);
        await prefs.setStringList(_downloadedModelsKey, downloaded);
      }

      onSuccess(model.filename);
    } catch (error) {
      onError(error);
    }
  }

  @override
  Future<void> deleteModel(String modelsDir, DownloadableModel model) async {
    final prefs = await SharedPreferences.getInstance();
    final downloaded = prefs.getStringList(_downloadedModelsKey) ?? <String>[];
    downloaded.remove(model.filename);
    await prefs.setStringList(_downloadedModelsKey, downloaded);
  }
}

ModelService createModelService() => ModelServiceWeb();
