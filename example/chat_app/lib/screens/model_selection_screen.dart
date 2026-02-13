import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../models/downloadable_model.dart';
import '../widgets/model_card.dart';
import '../services/model_service.dart';

class ModelSelectionScreen extends StatefulWidget {
  const ModelSelectionScreen({super.key});

  @override
  State<ModelSelectionScreen> createState() => _ModelSelectionScreenState();
}

class _ModelSelectionScreenState extends State<ModelSelectionScreen> {
  final ModelService _modelService = ModelService();
  final List<DownloadableModel> _models = DownloadableModel.defaultModels;

  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};
  final Map<String, CancelToken> _cancelTokens = {};
  Set<String> _downloadedFiles = {};
  String? _modelsDir;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initModelService();
    }
  }

  Future<void> _initModelService() async {
    _modelsDir = await _modelService.getModelsDirectory();
    _downloadedFiles = await _modelService.getDownloadedModels(_models);
    if (mounted) setState(() {});
  }

  Future<void> _downloadModel(DownloadableModel model) async {
    if (_modelsDir == null) return;

    final cancelToken = CancelToken();
    setState(() {
      _isDownloading[model.filename] = true;
      _downloadProgress[model.filename] = 0.0;
      _cancelTokens[model.filename] = cancelToken;
    });

    await _modelService.downloadModel(
      model: model,
      modelsDir: _modelsDir!,
      cancelToken: cancelToken,
      onProgress: (p) {
        if (mounted) {
          setState(() => _downloadProgress[model.filename] = p);
        }
      },
      onSuccess: (filename) {
        if (mounted) {
          setState(() {
            _downloadedFiles.add(filename);
            _isDownloading[model.filename] = false;
            _downloadProgress.remove(model.filename);
            _cancelTokens.remove(model.filename);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${model.name} downloaded successfully!')),
          );
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _isDownloading[model.filename] = false;
            // Keep progress to show resume state visually if it was a cancellation
            if (!(e is DioException && e.type == DioExceptionType.cancel)) {
              _downloadProgress.remove(model.filename);
            }
            _cancelTokens.remove(model.filename);
          });

          if (e is DioException && e.type == DioExceptionType.cancel) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Download paused: ${model.name}')),
            );
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
          }
        }
      },
    );
  }

  void _cancelDownload(DownloadableModel model) {
    final token = _cancelTokens[model.filename];
    if (token != null && !token.isCancelled) {
      token.cancel();
    }
  }

  void _selectModel(DownloadableModel model) {
    final pathOrUrl = kIsWeb ? model.url : '${_modelsDir!}/${model.filename}';
    final provider = context.read<ChatProvider>();

    provider.updateModelPath(pathOrUrl);
    provider.applyModelPreset(model);

    if (model.isMultimodal) {
      if (kIsWeb) {
        if (model.mmprojUrl != null && model.mmprojUrl!.isNotEmpty) {
          provider.updateMmprojPath(model.mmprojUrl!);
        } else {
          provider.updateMmprojPath(pathOrUrl);
        }
      } else if (model.mmprojFilename != null) {
        provider.updateMmprojPath('${_modelsDir!}/${model.mmprojFilename}');
      } else if (model.supportsVision || model.supportsAudio) {
        provider.updateMmprojPath(pathOrUrl);
      } else {
        provider.updateMmprojPath('');
      }
    } else {
      provider.updateMmprojPath(''); // Clear if not multimodal
    }

    provider.loadModel();
    Navigator.of(context).pop();
  }

  Future<void> _deleteModel(DownloadableModel model) async {
    if (_modelsDir == null) return;

    // If downloading, cancel first
    if (_isDownloading[model.filename] == true) {
      _cancelDownload(model);
    }

    await _modelService.deleteModel(_modelsDir!, model);
    if (mounted) {
      setState(() {
        _downloadedFiles.remove(model.filename);
        _downloadProgress.remove(model.filename);
        _isDownloading[model.filename] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Model'), centerTitle: true),
      body: ListView.separated(
        itemCount: _models.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        padding: const EdgeInsets.all(24),
        itemBuilder: (context, index) {
          final model = _models[index];
          final provider = context.watch<ChatProvider>();
          final selectedPath = kIsWeb
              ? model.url
              : (_modelsDir != null ? '${_modelsDir!}/${model.filename}' : '');

          return ModelCard(
            model: model,
            isDownloaded: _downloadedFiles.contains(model.filename),
            isDownloading: _isDownloading[model.filename] ?? false,
            progress: _downloadProgress[model.filename] ?? 0.0,
            isWeb: kIsWeb,
            isSelected: provider.modelPath == selectedPath,
            gpuLayers: provider.gpuLayers,
            contextSize: provider.contextSize,
            onGpuLayersChanged: provider.updateGpuLayers,
            onContextSizeChanged: provider.updateContextSize,
            onSelect: () => _selectModel(model),
            onDownload: () => _downloadModel(model),
            onDelete: () => _deleteModel(model),
            onCancel: () => _cancelDownload(model),
          );
        },
      ),
    );
  }
}
