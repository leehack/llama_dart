import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/downloadable_model.dart';
import '../providers/chat_provider.dart';
import '../services/model_service.dart';
import '../widgets/model_card.dart';

class ManageModelsScreen extends StatefulWidget {
  final VoidCallback? onModelActivated;
  final bool embeddedPanel;

  const ManageModelsScreen({
    super.key,
    this.onModelActivated,
    this.embeddedPanel = false,
  });

  @override
  State<ManageModelsScreen> createState() => _ManageModelsScreenState();
}

class _ManageModelsScreenState extends State<ManageModelsScreen> {
  static const String _customModelsPrefsKey = 'custom_hf_models_v1';

  final ModelService _modelService = ModelService();
  final List<DownloadableModel> _models = List<DownloadableModel>.from(
    DownloadableModel.defaultModels,
  );
  final List<DownloadableModel> _customModels = <DownloadableModel>[];

  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};
  final Map<String, CancelToken> _cancelTokens = {};

  Set<String> _downloadedFiles = {};
  String? _modelsDir;
  String? _activatingModel;
  bool _showModelLibrary = true;

  @override
  void initState() {
    super.initState();
    _showModelLibrary = false;
    _initModelService();
  }

  Future<void> _initModelService() async {
    await _loadCustomModels();
    _modelsDir = await _modelService.getModelsDirectory();
    _downloadedFiles = await _modelService.getDownloadedModels(_models);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadCustomModels() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(_customModelsPrefsKey) ?? const [];

    _customModels.clear();
    for (final entry in entries) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        final model = DownloadableModel(
          name: (decoded['name'] as String?) ?? 'Custom GGUF',
          description:
              (decoded['description'] as String?) ??
              'Custom Hugging Face GGUF model.',
          url: (decoded['url'] as String?) ?? '',
          filename: (decoded['filename'] as String?) ?? '',
          mmprojUrl: decoded['mmprojUrl'] as String?,
          mmprojFilename: decoded['mmprojFilename'] as String?,
          sizeBytes: (decoded['sizeBytes'] as int?) ?? 0,
          supportsVision: (decoded['supportsVision'] as bool?) ?? false,
          supportsAudio: (decoded['supportsAudio'] as bool?) ?? false,
          supportsVideo: false,
          supportsToolCalling: false,
          supportsThinking: false,
          preset: const ModelPreset(),
          minRamGb: 2,
        );

        if (model.url.isEmpty || model.filename.isEmpty) {
          continue;
        }

        final exists = _models.any(
          (existing) =>
              existing.filename == model.filename || existing.url == model.url,
        );
        if (!exists) {
          _models.add(model);
          _customModels.add(model);
        }
      } catch (_) {
        // Ignore malformed persisted model entries.
      }
    }
  }

  Future<void> _saveCustomModels() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _customModels
        .map(
          (model) => jsonEncode({
            'name': model.name,
            'description': model.description,
            'url': model.url,
            'filename': model.filename,
            'mmprojUrl': model.mmprojUrl,
            'mmprojFilename': model.mmprojFilename,
            'sizeBytes': model.sizeBytes,
            'supportsVision': model.supportsVision,
            'supportsAudio': model.supportsAudio,
          }),
        )
        .toList(growable: false);
    await prefs.setStringList(_customModelsPrefsKey, payload);
  }

  String? _extractFilenameFromUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.pathSegments.isEmpty) {
      return null;
    }

    for (var i = uri.pathSegments.length - 1; i >= 0; i--) {
      final segment = Uri.decodeComponent(uri.pathSegments[i]).trim();
      if (segment.isNotEmpty) {
        return segment;
      }
    }
    return null;
  }

  Future<void> _showAddHuggingFaceDialog() async {
    final nameController = TextEditingController();
    final modelUrlController = TextEditingController();
    final mmprojUrlController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Hugging Face GGUF'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Display name (optional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: modelUrlController,
                      decoration: const InputDecoration(
                        labelText: 'GGUF URL (Hugging Face)',
                        hintText:
                            'https://huggingface.co/.../resolve/main/model.gguf?download=true',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: mmprojUrlController,
                      decoration: const InputDecoration(
                        labelText: 'MMProj URL (optional)',
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final url = modelUrlController.text.trim();
                    final mmprojUrl = mmprojUrlController.text.trim();
                    final uri = Uri.tryParse(url);
                    final modelFilename = _extractFilenameFromUrl(url);

                    if (uri == null ||
                        !uri.hasScheme ||
                        !uri.host.contains('huggingface.co') ||
                        modelFilename == null ||
                        !modelFilename.toLowerCase().endsWith('.gguf')) {
                      setDialogState(() {
                        errorText =
                            'Please enter a valid Hugging Face GGUF URL.';
                      });
                      return;
                    }

                    String? mmprojFilename;
                    if (mmprojUrl.isNotEmpty) {
                      mmprojFilename = _extractFilenameFromUrl(mmprojUrl);
                      if (mmprojFilename == null ||
                          !mmprojFilename.toLowerCase().endsWith('.gguf')) {
                        setDialogState(() {
                          errorText =
                              'Invalid MMProj URL. It must point to .gguf';
                        });
                        return;
                      }
                    }

                    final exists = _models.any(
                      (model) =>
                          model.url == url || model.filename == modelFilename,
                    );
                    if (exists) {
                      setDialogState(() {
                        errorText = 'This model is already in your list.';
                      });
                      return;
                    }

                    final displayName = nameController.text.trim().isEmpty
                        ? modelFilename
                        : nameController.text.trim();

                    final customModel = DownloadableModel(
                      name: displayName,
                      description: 'Custom Hugging Face GGUF model.',
                      url: url,
                      filename: modelFilename,
                      mmprojUrl: mmprojUrl.isEmpty ? null : mmprojUrl,
                      mmprojFilename: mmprojFilename,
                      sizeBytes: 0,
                      supportsVision: mmprojUrl.isNotEmpty,
                      supportsAudio: false,
                      supportsVideo: false,
                      supportsToolCalling: false,
                      supportsThinking: false,
                      minRamGb: 2,
                      preset: const ModelPreset(),
                    );

                    setState(() {
                      _models.insert(0, customModel);
                      _customModels.insert(0, customModel);
                      _showModelLibrary = true;
                    });
                    Navigator.of(dialogContext).pop();
                    await _saveCustomModels();

                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('Added ${customModel.name}')),
                    );
                  },
                  child: const Text('Add model'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _downloadModel(DownloadableModel model) async {
    if (!kIsWeb && _modelsDir == null) {
      return;
    }

    final cancelToken = CancelToken();
    setState(() {
      _isDownloading[model.filename] = true;
      _downloadProgress[model.filename] = 0.0;
      _cancelTokens[model.filename] = cancelToken;
    });

    await _modelService.downloadModel(
      model: model,
      modelsDir: _modelsDir ?? '',
      cancelToken: cancelToken,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _downloadProgress[model.filename] = progress;
        });
      },
      onSuccess: (filename) {
        if (!mounted) return;
        setState(() {
          _downloadedFiles.add(filename);
          _isDownloading[model.filename] = false;
          _downloadProgress.remove(model.filename);
          _cancelTokens.remove(model.filename);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.name} downloaded successfully.')),
        );
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isDownloading[model.filename] = false;
          if (!(error is DioException &&
              error.type == DioExceptionType.cancel)) {
            _downloadProgress.remove(model.filename);
          }
          _cancelTokens.remove(model.filename);
        });

        final isCancel =
            error is DioException && error.type == DioExceptionType.cancel;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCancel
                  ? 'Download paused: ${model.name}'
                  : 'Download failed: $error',
            ),
          ),
        );
      },
    );
  }

  void _cancelDownload(DownloadableModel model) {
    final token = _cancelTokens[model.filename];
    if (token != null && !token.isCancelled) {
      token.cancel();
    }
  }

  Future<void> _selectModel(DownloadableModel model) async {
    if (!kIsWeb && _modelsDir == null) {
      return;
    }

    final provider = context.read<ChatProvider>();
    final pathOrUrl = kIsWeb ? model.url : '${_modelsDir!}/${model.filename}';

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
      provider.updateMmprojPath('');
    }

    setState(() {
      _activatingModel = model.filename;
    });

    await provider.loadModel();

    if (!mounted) return;
    setState(() {
      _activatingModel = null;
      _showModelLibrary = false;
    });

    if (provider.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${model.name} loaded successfully.')),
      );
      widget.onModelActivated?.call();
    }
  }

  Future<void> _deleteModel(DownloadableModel model) async {
    if (_modelsDir == null) return;

    if (_isDownloading[model.filename] == true) {
      _cancelDownload(model);
    }

    await _modelService.deleteModel(_modelsDir!, model);
    if (!mounted) return;

    setState(() {
      _downloadedFiles.remove(model.filename);
      _downloadProgress.remove(model.filename);
      _isDownloading[model.filename] = false;
    });
  }

  void _resetParams(ChatProvider provider) {
    final selectedModel = _findSelectedModel(provider);
    if (selectedModel != null) {
      provider.applyModelPreset(selectedModel);
    } else {
      provider.updateContextSize(4096);
      provider.updateMaxTokens(4096);
      provider.updateTemperature(0.7);
      provider.updateTopK(40);
      provider.updateTopP(0.9);
      provider.updateMinP(0.0);
      provider.updatePenalty(1.1);
      provider.updateThinkingEnabled(true);
      provider.updateThinkingBudgetTokens(0);
    }

    provider.updateNumberOfThreads(0);
    provider.updateNumberOfThreadsBatch(0);
    provider.updateSingleTurnMode(false);
  }

  DownloadableModel? _findSelectedModel(ChatProvider provider) {
    final path = provider.modelPath;
    if (path == null || path.isEmpty) {
      return null;
    }

    for (final model in _models) {
      if (path == model.url || path.contains(model.filename)) {
        return model;
      }
    }
    return null;
  }

  Future<void> _loadConfiguredModel(ChatProvider provider) async {
    await provider.loadModel();
    if (!mounted) return;

    if (provider.error == null) {
      setState(() {
        _showModelLibrary = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model loaded successfully.')),
      );
      widget.onModelActivated?.call();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to load model: ${provider.error}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        final width = MediaQuery.sizeOf(context).width;
        final isEmbedded = widget.embeddedPanel;
        final isWide = width >= 980 && !isEmbedded;
        final horizontalPadding = isEmbedded ? 12.0 : (isWide ? 28.0 : 16.0);
        final selectedBackend = _resolveSelectedBackend(provider);
        final contextOptions = _buildContextSizeOptions(provider.contextSize);
        final hasModelPath =
            provider.modelPath != null && provider.modelPath!.isNotEmpty;
        final modelLabel = provider.activeModelName;
        final threadLabel = provider.numberOfThreads == 0
            ? '(auto detected)'
            : provider.numberOfThreads.toString();
        final threadBatchLabel = provider.numberOfThreadsBatch == 0
            ? '(auto detected)'
            : provider.numberOfThreadsBatch.toString();
        final hasLoadProgress =
            provider.loadingProgress > 0 && provider.loadingProgress < 1;
        final loadProgressLabel = hasLoadProgress
            ? '${(provider.loadingProgress * 100).toStringAsFixed(0)}%'
            : null;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            isEmbedded ? 14 : 24,
            horizontalPadding,
            isEmbedded ? 14 : 24,
          ),
          children: [
            Text(
              'Model',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              modelLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              provider.isLoaded
                                  ? 'Loaded'
                                  : (hasModelPath
                                        ? 'Configured (not loaded)'
                                        : 'No model selected'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (hasModelPath)
                        OutlinedButton.icon(
                          onPressed: provider.isInitializing
                              ? null
                              : () => unawaited(
                                  provider.isLoaded
                                      ? provider.unloadModel()
                                      : _loadConfiguredModel(provider),
                                ),
                          icon: Icon(
                            provider.isLoaded
                                ? Icons.eject_outlined
                                : Icons.play_arrow_rounded,
                          ),
                          label: Text(provider.isLoaded ? 'Unload' : 'Load'),
                        ),
                    ],
                  ),
                  if (provider.isInitializing) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: hasLoadProgress
                            ? provider.loadingProgress
                            : null,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      loadProgressLabel == null
                          ? 'Loading model...'
                          : 'Loading model... $loadProgressLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showModelLibrary = !_showModelLibrary;
                      });
                    },
                    icon: Icon(
                      _showModelLibrary
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    label: Text(
                      _showModelLibrary
                          ? 'Hide model library'
                          : 'Manage models',
                    ),
                  ),
                  if (_showModelLibrary) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: _showAddHuggingFaceDialog,
                        icon: const Icon(Icons.add_link_rounded),
                        label: const Text('Add GGUF (HF)'),
                      ),
                    ),
                    if (!kIsWeb && _modelsDir == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      ..._models.map((model) {
                        final selectedPath = kIsWeb
                            ? model.url
                            : (_modelsDir != null
                                  ? '${_modelsDir!}/${model.filename}'
                                  : '');
                        final isActivating = _activatingModel == model.filename;

                        final card = ModelCard(
                          model: model,
                          isDownloaded: _downloadedFiles.contains(
                            model.filename,
                          ),
                          isDownloading:
                              _isDownloading[model.filename] ?? false,
                          progress: _downloadProgress[model.filename] ?? 0.0,
                          isWeb: kIsWeb,
                          isSelected: provider.modelPath == selectedPath,
                          gpuLayers: provider.gpuLayers,
                          contextSize: provider.contextSize,
                          onGpuLayersChanged: provider.updateGpuLayers,
                          onContextSizeChanged: provider.updateContextSize,
                          onSelect: isActivating
                              ? () {}
                              : () => unawaited(_selectModel(model)),
                          onDownload: () => unawaited(_downloadModel(model)),
                          onDelete: () => unawaited(_deleteModel(model)),
                          onCancel: () => _cancelDownload(model),
                        );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Stack(
                            children: [
                              card,
                              if (isActivating)
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.35,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 210,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.45,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.16,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              hasLoadProgress
                                                  ? 'Loading ${loadProgressLabel!}'
                                                  : 'Loading model...',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            const SizedBox(height: 8),
                                            LinearProgressIndicator(
                                              value: hasLoadProgress
                                                  ? provider.loadingProgress
                                                  : null,
                                              minHeight: 6,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Inference parameters',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                children: [
                  _LabeledSlider(
                    label: '# threads',
                    valueLabel: threadLabel,
                    min: 0,
                    max: 32,
                    divisions: 32,
                    value: provider.numberOfThreads.toDouble(),
                    onChanged: (value) =>
                        provider.updateNumberOfThreads(value.toInt()),
                  ),
                  const SizedBox(height: 10),
                  _LabeledSlider(
                    label: '# batch threads',
                    valueLabel: threadBatchLabel,
                    min: 0,
                    max: 64,
                    divisions: 64,
                    value: provider.numberOfThreadsBatch.toDouble(),
                    onChanged: (value) =>
                        provider.updateNumberOfThreadsBatch(value.toInt()),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: provider.contextSize,
                    decoration: const InputDecoration(
                      labelText: 'Context size',
                    ),
                    items: contextOptions
                        .map(
                          (option) => DropdownMenuItem<int>(
                            value: option,
                            child: Text(
                              option == 0 ? 'Auto (Native)' : '$option',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        provider.updateContextSize(value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _LabeledSlider(
                    label: 'Max generated tokens',
                    valueLabel: provider.maxGenerationTokens.toString(),
                    min: 512,
                    max: 32768,
                    divisions: (32768 - 512) ~/ 512,
                    value: provider.maxGenerationTokens.toDouble(),
                    onChanged: (value) =>
                        provider.updateMaxTokens(value.toInt()),
                  ),
                  const SizedBox(height: 10),
                  _LabeledSlider(
                    label: 'Temperature',
                    valueLabel: provider.temperature.toStringAsFixed(2),
                    min: 0,
                    max: 2,
                    divisions: 40,
                    value: provider.temperature,
                    onChanged: provider.updateTemperature,
                  ),
                  const SizedBox(height: 10),
                  _LabeledSlider(
                    label: 'Top-K',
                    valueLabel: provider.topK.toString(),
                    min: 1,
                    max: 100,
                    divisions: 99,
                    value: provider.topK.toDouble(),
                    onChanged: (value) => provider.updateTopK(value.toInt()),
                  ),
                  const SizedBox(height: 10),
                  _LabeledSlider(
                    label: 'Top-P',
                    valueLabel: provider.topP.toStringAsFixed(2),
                    min: 0,
                    max: 1,
                    divisions: 50,
                    value: provider.topP,
                    onChanged: provider.updateTopP,
                  ),
                  const SizedBox(height: 10),
                  _LabeledSlider(
                    label: 'Min-P',
                    valueLabel: provider.minP.toStringAsFixed(2),
                    min: 0,
                    max: 1,
                    divisions: 100,
                    value: provider.minP,
                    onChanged: provider.updateMinP,
                  ),
                  const SizedBox(height: 10),
                  _LabeledSlider(
                    label: 'Repetition penalty',
                    valueLabel: provider.penalty.toStringAsFixed(2),
                    min: 0.8,
                    max: 2.0,
                    divisions: 60,
                    value: provider.penalty,
                    onChanged: provider.updatePenalty,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<GpuBackend>(
                    initialValue: selectedBackend,
                    decoration: const InputDecoration(
                      labelText: 'Preferred backend',
                    ),
                    items: _getAvailableBackends(provider)
                        .map(
                          (backend) => DropdownMenuItem<GpuBackend>(
                            value: backend,
                            child: Text(_backendLabel(backend)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(provider.updatePreferredBackend(value));
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<LlamaLogLevel>(
                    initialValue: provider.dartLogLevel,
                    decoration: const InputDecoration(
                      labelText: 'Dart log level',
                    ),
                    items: LlamaLogLevel.values
                        .map(
                          (level) => DropdownMenuItem<LlamaLogLevel>(
                            value: level,
                            child: Text(_logLevelLabel(level)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        provider.updateLogLevel(value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<LlamaLogLevel>(
                    initialValue: provider.nativeLogLevel,
                    decoration: const InputDecoration(
                      labelText: 'Native log level',
                    ),
                    items: LlamaLogLevel.values
                        .map(
                          (level) => DropdownMenuItem<LlamaLogLevel>(
                            value: level,
                            child: Text(_logLevelLabel(level)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        provider.updateNativeLogLevel(value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    value: provider.toolsEnabled,
                    title: const Text('Enable tools'),
                    subtitle: const Text(
                      'Allow the model to call tool functions.',
                    ),
                    contentPadding: EdgeInsets.zero,
                    onChanged: provider.updateToolsEnabled,
                  ),
                  SwitchListTile.adaptive(
                    value: provider.forceToolCall,
                    title: const Text('Force tool call'),
                    subtitle: const Text('Require tool output for each turn.'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: provider.toolsEnabled
                        ? provider.updateForceToolCall
                        : null,
                  ),
                  SwitchListTile.adaptive(
                    value: provider.thinkingEnabled,
                    title: const Text('Enable thinking output'),
                    subtitle: const Text(
                      'Sends thinking-disable hint to template handlers.',
                    ),
                    contentPadding: EdgeInsets.zero,
                    onChanged: provider.updateThinkingEnabled,
                  ),
                  const SizedBox(height: 10),
                  _LabeledSlider(
                    label: 'Thinking budget',
                    valueLabel: provider.thinkingBudgetTokens == 0
                        ? 'Auto'
                        : provider.thinkingBudgetTokens.toString(),
                    min: 0,
                    max: 4096,
                    divisions: 64,
                    value: provider.thinkingBudgetTokens.toDouble(),
                    onChanged: (value) =>
                        provider.updateThinkingBudgetTokens(value.toInt()),
                  ),
                  SwitchListTile.adaptive(
                    value: provider.singleTurnMode,
                    title: const Text('Single-turn mode'),
                    subtitle: const Text(
                      'Each prompt runs without previous turn context.',
                    ),
                    contentPadding: EdgeInsets.zero,
                    onChanged: provider.updateSingleTurnMode,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => _resetParams(provider),
                        child: const Text('Reset params'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<int> _buildContextSizeOptions(int current) {
    final values = <int>{0, 2048, 4096, 8192, 16384, 32768, current}.toList()
      ..sort();
    return values;
  }

  List<GpuBackend> _getAvailableBackends(ChatProvider provider) {
    final backends = <GpuBackend>{GpuBackend.cpu};
    if (kIsWeb) {
      backends.add(GpuBackend.auto);
    }

    for (final device in provider.availableDevices) {
      final d = device.toLowerCase();
      if (d.contains('metal') || d.contains('mtl')) {
        backends.add(GpuBackend.metal);
      }
      if (d.contains('vulkan')) backends.add(GpuBackend.vulkan);
      if (d.contains('opencl')) backends.add(GpuBackend.opencl);
      if (d.contains('hip')) backends.add(GpuBackend.hip);
      if (d.contains('cuda')) backends.add(GpuBackend.cuda);
      if (d.contains('blas')) backends.add(GpuBackend.blas);
      if (d.contains('cpu') || d.contains('llvm')) {
        backends.add(GpuBackend.cpu);
      }
    }

    final sorted = backends.toList(growable: false)
      ..sort((a, b) => a.index.compareTo(b.index));
    return sorted;
  }

  GpuBackend _resolveSelectedBackend(ChatProvider provider) {
    final available = _getAvailableBackends(provider);
    if (available.contains(provider.preferredBackend)) {
      return provider.preferredBackend;
    }
    if (available.contains(GpuBackend.cpu)) {
      return GpuBackend.cpu;
    }
    return available.first;
  }

  String _backendLabel(GpuBackend backend) {
    if (kIsWeb && backend == GpuBackend.auto) {
      return 'WEBGPU';
    }
    return backend.name.toUpperCase();
  }

  String _logLevelLabel(LlamaLogLevel level) {
    return switch (level) {
      LlamaLogLevel.none => 'None',
      LlamaLogLevel.error => 'Error',
      LlamaLogLevel.warn => 'Warn',
      LlamaLogLevel.info => 'Info',
      LlamaLogLevel.debug => 'Debug',
    };
  }
}

class _LabeledSlider extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double min;
  final double max;
  final int? divisions;
  final double value;
  final ValueChanged<double> onChanged;

  const _LabeledSlider({
    required this.label,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              valueLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value.clamp(min, max),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
