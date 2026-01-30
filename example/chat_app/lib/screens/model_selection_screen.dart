import 'dart:io' if (dart.library.js_interop) '../stub/io_stub.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import '../models/chat_model.dart';

class ModelSelectionScreen extends StatefulWidget {
  const ModelSelectionScreen({super.key});

  @override
  State<ModelSelectionScreen> createState() => _ModelSelectionScreenState();
}

class DownloadableModel {
  final String name;
  final String description;
  final String url;
  final String filename;
  final int sizeBytes;

  const DownloadableModel({
    required this.name,
    required this.description,
    required this.url,
    required this.filename,
    required this.sizeBytes,
  });

  String get sizeMb => (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
}

class _ModelSelectionScreenState extends State<ModelSelectionScreen> {
  // List of lightweight models suitable for mobile
  final List<DownloadableModel> _models = [
    const DownloadableModel(
      name: 'Qwen 2.5 0.5B (4bit)',
      description: 'Extremely small and fast. Good for basic tasks.',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true',
      filename: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      sizeBytes: 398000000, // Approx 400MB
    ),
    const DownloadableModel(
      name: 'LFM 2.5 1.2B (4bit)',
      description: 'LiquidAI\'s efficient 1.2B model. Fast edge inference.',
      url:
          'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      sizeBytes: 800000000, // Approx 800MB
    ),
    const DownloadableModel(
      name: 'Gemma 3 1B (4bit)',
      description:
          'Google\'s latest lightweight multimodal model. Fast and capable.',
      url:
          'https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/google_gemma-3-1b-it-Q4_K_M.gguf?download=true',
      filename: 'google_gemma-3-1b-it-Q4_K_M.gguf',
      sizeBytes: 850000000, // Approx 850MB
    ),
    const DownloadableModel(
      name: 'Llama 3.2 1B (4bit)',
      description: 'Meta\'s latest small model. Balanced performance.',
      url:
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true',
      filename: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      sizeBytes: 866000000, // Approx 866MB
    ),
    const DownloadableModel(
      name: 'TinyLlama 1.1B (Chat)',
      description: 'Classic tiny model.',
      url:
          'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf?download=true',
      filename: 'tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
      sizeBytes: 669000000, // Approx 670MB
    ),
  ];

  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};
  Set<String> _downloadedFiles = {};
  String? _modelsDir;

  @override
  void initState() {
    super.initState();
    // Only check local files if not on web
    if (!kIsWeb) {
      _checkDownloadedModels();
    }
  }

  Future<void> _checkDownloadedModels() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(dir.path, 'models'));
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    _modelsDir = modelsDir.path;
    final downloaded = <String>{};

    for (var model in _models) {
      final file = File(p.join(modelsDir.path, model.filename));
      if (file.existsSync() && file.lengthSync() > 0) {
        downloaded.add(model.filename);
      }
    }

    if (mounted) {
      setState(() {
        _downloadedFiles = downloaded;
      });
    }
  }

  Future<void> _downloadModelNative(DownloadableModel model) async {
    if (_modelsDir == null) return;

    final savePath = p.join(_modelsDir!, model.filename);
    final dio = Dio();

    setState(() {
      _isDownloading[model.filename] = true;
      _downloadProgress[model.filename] = 0.0;
    });

    try {
      await dio.download(
        model.url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _downloadProgress[model.filename] = received / total;
            });
          }
        },
      );

      setState(() {
        _downloadedFiles.add(model.filename);
        _isDownloading[model.filename] = false;
        _downloadProgress.remove(model.filename);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.name} downloaded successfully!')),
        );
      }
    } catch (e) {
      setState(() {
        _isDownloading[model.filename] = false;
        _downloadProgress.remove(model.filename);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }

      // Clean up partial file
      final file = File(savePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  void _selectModel(String pathOrUrl) {
    context.read<ChatProvider>().updateModelPath(pathOrUrl);
    // Auto load the model
    context.read<ChatProvider>().loadModel();
    // Navigate back to chat
    Navigator.of(context).pop();
  }

  Future<void> _deleteModel(String filename) async {
    if (_modelsDir == null) return;
    final path = p.join(_modelsDir!, filename);
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
      setState(() {
        _downloadedFiles.remove(filename);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Select Model',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: ListView.separated(
        itemCount: _models.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        padding: const EdgeInsets.all(24),
        itemBuilder: (context, index) {
          final model = _models[index];
          final isDownloaded = _downloadedFiles.contains(model.filename);
          final isDownloading = _isDownloading[model.filename] ?? false;
          final progress = _downloadProgress[model.filename] ?? 0.0;

          final colorScheme = Theme.of(context).colorScheme;

          return Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            model.name,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withValues(
                                alpha: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${model.sizeMb} MB',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isDownloaded && !kIsWeb)
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.error,
                        ),
                        onPressed: () => _deleteModel(model.filename),
                        tooltip: 'Delete Model',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  model.description,
                  style: GoogleFonts.outfit(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                if (isDownloading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Downloading...',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.primary,
                        ),
                      ),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: isDownloaded || kIsWeb
                        ? FilledButton.icon(
                            onPressed: () {
                              if (kIsWeb) {
                                _selectModel(model.url);
                              } else {
                                _selectModel(
                                  p.join(_modelsDir!, model.filename),
                                );
                              }
                            },
                            icon: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              kIsWeb ? 'Load Web Model' : 'Use this model',
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: () => _downloadModelNative(model),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Download to Device'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
