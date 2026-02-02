import 'package:dio/dio.dart';
import '../models/downloadable_model.dart';
import 'model_service_base.dart';

class ModelServiceWeb implements ModelService {
  @override
  Future<String> getModelsDirectory() async => '';

  @override
  Future<Set<String>> getDownloadedModels(
    List<DownloadableModel> models,
  ) async => {};

  @override
  Future<void> downloadModel({
    required DownloadableModel model,
    required String modelsDir,
    required CancelToken cancelToken,
    required Function(double progress) onProgress,
    required Function(String filename) onSuccess,
    required Function(dynamic error) onError,
  }) async {
    // Web doesn't support local model storage in this way
    onError(
      UnsupportedError(
        'Model downloading is not supported on Web. Use URLs directly.',
      ),
    );
  }

  @override
  Future<void> deleteModel(String modelsDir, DownloadableModel model) async {
    // No-op on web
  }
}

ModelService createModelService() => ModelServiceWeb();
