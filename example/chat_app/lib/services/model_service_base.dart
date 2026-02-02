import 'package:dio/dio.dart';
import '../models/downloadable_model.dart';
import 'model_service_io.dart'
    if (dart.library.js_interop) 'model_service_web.dart';

abstract class ModelService {
  factory ModelService() => createModelService();

  Future<String> getModelsDirectory();

  Future<Set<String>> getDownloadedModels(List<DownloadableModel> models);

  Future<void> downloadModel({
    required DownloadableModel model,
    required String modelsDir,
    required CancelToken cancelToken,
    required Function(double progress) onProgress,
    required Function(String filename) onSuccess,
    required Function(dynamic error) onError,
  });

  Future<void> deleteModel(String modelsDir, DownloadableModel model);
}
