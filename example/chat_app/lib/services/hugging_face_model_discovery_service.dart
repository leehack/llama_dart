import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/downloadable_model.dart';

class HfDiscoveryFilters {
  final String searchQuery;
  final HfDiscoverySort sort;
  final HfPipelineTagFilter pipelineTag;

  const HfDiscoveryFilters({
    this.searchQuery = '',
    this.sort = HfDiscoverySort.trending,
    this.pipelineTag = HfPipelineTagFilter.any,
  });
}

enum HfDiscoverySort { trending, downloads }

enum HfPipelineTagFilter {
  any,
  textGeneration,
  imageTextToText,
  audioTextToText,
}

class HfDiscoveredModel {
  final DownloadableModel model;
  final String repositoryId;
  final int downloads;
  final int likes;
  final bool hasLiveStats;
  final double? modelScaleB;

  const HfDiscoveredModel({
    required this.model,
    required this.repositoryId,
    required this.downloads,
    required this.likes,
    required this.hasLiveStats,
    required this.modelScaleB,
  });

  double get likesPerThousandDownloads {
    if (downloads <= 0) {
      return 0;
    }
    return (likes * 1000) / downloads;
  }

  String get modelScaleLabel {
    final scale = modelScaleB;
    if (scale == null) {
      return 'Scale n/a';
    }

    if (scale >= 1.0) {
      return '${scale.toStringAsFixed(scale >= 10 ? 0 : 1)}B';
    }
    return '${(scale * 1000).toStringAsFixed(0)}M';
  }
}

class HuggingFaceModelDiscoveryService {
  static const String _hfModelApiBase = 'https://huggingface.co/api/models';
  static const Duration _cacheTtl = Duration(minutes: 10);
  static const int _apiModelsLimit = 120;
  static const int _metadataEnrichmentLimit = 32;
  static const int _metadataBatchSize = 8;

  final Dio _dio;
  final Map<String, _DiscoveryCacheEntry> _cacheByKey =
      <String, _DiscoveryCacheEntry>{};
  final Map<String, _RepositoryTreeCacheEntry> _repositoryTreeCacheById =
      <String, _RepositoryTreeCacheEntry>{};

  void _logQuery(String message) {
    if (kDebugMode) {
      debugPrint('[HF Discovery] $message');
    }
  }

  HuggingFaceModelDiscoveryService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
            ),
          );

  Future<List<HfDiscoveredModel>> discoverPopularModels({
    required HfDiscoveryFilters filters,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final cacheKey = _cacheKeyForFilters(filters);
    final cached = _cacheByKey[cacheKey];
    final normalizedQuery = filters.searchQuery.trim();

    _logQuery(
      'Discover request q="${normalizedQuery.isEmpty ? '*' : normalizedQuery}", '
      'sort=${filters.sort.name}, pipeline=${filters.pipelineTag.name}, '
      'forceRefresh=$forceRefresh',
    );

    if (!forceRefresh &&
        cached != null &&
        now.difference(cached.createdAt) <= _cacheTtl) {
      _logQuery('Cache hit key=$cacheKey (${cached.models.length} models)');
      return cached.models;
    }

    final repositorySummaries = await _discoverRepositories(filters: filters);
    if (repositorySummaries.isEmpty) {
      const empty = <HfDiscoveredModel>[];
      _cacheByKey[cacheKey] = _DiscoveryCacheEntry(
        models: empty,
        createdAt: now,
      );
      return empty;
    }

    final discovered = repositorySummaries
        .map((summary) => _buildDiscoveredModel(summary: summary))
        .whereType<HfDiscoveredModel>()
        .toList(growable: false);
    _cacheByKey[cacheKey] = _DiscoveryCacheEntry(
      models: discovered,
      createdAt: now,
    );
    return discovered;
  }

  String _cacheKeyForFilters(HfDiscoveryFilters filters) {
    return <String>[
      filters.sort.name,
      filters.pipelineTag.name,
      filters.searchQuery.trim().toLowerCase(),
    ].join('|');
  }

  Future<List<_HfRepositorySummary>> _discoverRepositories({
    required HfDiscoveryFilters filters,
  }) async {
    final request = _buildSearchRequest(filters);
    final repositories = await _fetchRepositorySearch(request);
    if (repositories.isEmpty) {
      return repositories;
    }
    return _enrichRepositoryFiles(repositories);
  }

  Future<List<_HfRepositorySummary>> _enrichRepositoryFiles(
    List<_HfRepositorySummary> repositories,
  ) async {
    final enriched = List<_HfRepositorySummary>.from(repositories);
    final totalToEnrich = math.min(_metadataEnrichmentLimit, enriched.length);

    for (var start = 0; start < totalToEnrich; start += _metadataBatchSize) {
      final end = math.min(start + _metadataBatchSize, totalToEnrich);
      final batchFutures = <Future<_HfRepositorySummary>>[];

      for (var index = start; index < end; index++) {
        batchFutures.add(_enrichRepositoryFileMetadata(enriched[index]));
      }

      final batch = await Future.wait<_HfRepositorySummary>(batchFutures);
      for (var index = 0; index < batch.length; index++) {
        enriched[start + index] = batch[index];
      }
    }

    return enriched;
  }

  Future<_HfRepositorySummary> _enrichRepositoryFileMetadata(
    _HfRepositorySummary summary,
  ) async {
    final files = await _fetchRepositoryTreeFiles(summary.id);
    if (files.isEmpty) {
      return summary;
    }

    return _HfRepositorySummary(
      id: summary.id,
      downloads: summary.downloads,
      likes: summary.likes,
      tags: summary.tags,
      files: files,
      pipelineTag: summary.pipelineTag,
      numParameters: summary.numParameters,
    );
  }

  _SearchRequest _buildSearchRequest(HfDiscoveryFilters filters) {
    final String? search = filters.searchQuery.trim().isEmpty
        ? null
        : filters.searchQuery.trim();

    final String? pipelineTag = switch (filters.pipelineTag) {
      HfPipelineTagFilter.any => null,
      HfPipelineTagFilter.textGeneration => 'text-generation',
      HfPipelineTagFilter.imageTextToText => 'image-text-to-text',
      HfPipelineTagFilter.audioTextToText => 'audio-text-to-text',
    };

    final sort = filters.sort == HfDiscoverySort.trending
        ? 'trendingScore'
        : 'downloads';

    return _SearchRequest(
      search: search,
      library: 'gguf',
      pipelineTag: pipelineTag,
      sort: sort,
    );
  }

  Future<List<_HfRepositorySummary>> _fetchRepositorySearch(
    _SearchRequest request,
  ) async {
    try {
      final queryParameters = <String, dynamic>{
        'sort': request.sort,
        'direction': -1,
        'limit': _apiModelsLimit,
        'full': true,
      };

      if (request.search != null && request.search!.trim().isNotEmpty) {
        queryParameters['search'] = request.search;
      }
      if (request.library != null && request.library!.trim().isNotEmpty) {
        queryParameters['filter'] = request.library;
      }
      if (request.pipelineTag != null &&
          request.pipelineTag!.trim().isNotEmpty) {
        queryParameters['pipeline_tag'] = request.pipelineTag;
      }

      final requestUri = Uri.parse(_hfModelApiBase).replace(
        queryParameters: queryParameters.map(
          (key, value) => MapEntry(key, value.toString()),
        ),
      );

      _logQuery('GET $requestUri');

      final response = await _dio.get<List<dynamic>>(
        _hfModelApiBase,
        queryParameters: queryParameters,
      );
      final rows = response.data ?? const <dynamic>[];
      _logQuery(
        'GET $requestUri -> ${response.statusCode ?? 200} (${rows.length} rows)',
      );
      final mergedById = <String, _HfRepositorySummary>{};
      for (final raw in rows) {
        final summary = _parseRepositorySummary(raw);
        if (summary == null) {
          continue;
        }

        final previous = mergedById[summary.id];
        if (previous == null) {
          mergedById[summary.id] = summary;
          continue;
        }

        mergedById[summary.id] = _HfRepositorySummary(
          id: summary.id,
          downloads: math.max(previous.downloads, summary.downloads),
          likes: math.max(previous.likes, summary.likes),
          tags: previous.tags.union(summary.tags),
          files: summary.files.length >= previous.files.length
              ? summary.files
              : previous.files,
          pipelineTag: summary.pipelineTag ?? previous.pipelineTag,
          numParameters: summary.numParameters ?? previous.numParameters,
        );
      }

      return mergedById.values.toList(growable: false);
    } on DioException catch (e) {
      final requestUri = Uri.parse(_hfModelApiBase).replace(
        queryParameters: <String, String>{
          if (request.search != null && request.search!.trim().isNotEmpty)
            'search': request.search!,
          if (request.library != null && request.library!.trim().isNotEmpty)
            'filter': request.library!,
          if (request.pipelineTag != null &&
              request.pipelineTag!.trim().isNotEmpty)
            'pipeline_tag': request.pipelineTag!,
          'sort': request.sort,
          'direction': '-1',
          'limit': _apiModelsLimit.toString(),
          'full': 'true',
        },
      );
      _logQuery(
        'GET $requestUri -> ERROR ${e.response?.statusCode ?? 'network'}: ${e.message}',
      );
      return const <_HfRepositorySummary>[];
    } catch (e) {
      _logQuery('GET /api/models request failed: $e');
      return const <_HfRepositorySummary>[];
    }
  }

  Future<List<_HfTreeFile>> _fetchRepositoryTreeFiles(
    String repositoryId,
  ) async {
    final now = DateTime.now();
    final cached = _repositoryTreeCacheById[repositoryId];
    if (cached != null && now.difference(cached.createdAt) <= _cacheTtl) {
      return cached.files;
    }

    final repositoryPath = _encodeRepositoryPath(repositoryId);
    final queryParameters = <String, dynamic>{
      'recursive': true,
      'expand': true,
    };
    final requestUri = Uri.parse('$_hfModelApiBase/$repositoryPath/tree/main')
        .replace(
          queryParameters: queryParameters.map(
            (key, value) => MapEntry(key, value.toString()),
          ),
        );

    try {
      _logQuery('GET $requestUri');
      final response = await _dio.get<List<dynamic>>(
        '$_hfModelApiBase/$repositoryPath/tree/main',
        queryParameters: queryParameters,
      );
      final rows = response.data ?? const <dynamic>[];
      _logQuery(
        'GET $requestUri -> ${response.statusCode ?? 200} (${rows.length} rows)',
      );

      final files = <_HfTreeFile>[];
      for (final raw in rows) {
        if (raw is! Map) {
          continue;
        }

        final type = (raw['type'] as String?)?.trim().toLowerCase();
        if (type != null && type.isNotEmpty && type != 'file') {
          continue;
        }

        final path = ((raw['path'] as String?) ?? (raw['rfilename'] as String?))
            ?.trim();
        if (path == null || path.isEmpty) {
          continue;
        }

        if (!path.toLowerCase().endsWith('.gguf')) {
          continue;
        }

        files.add(_HfTreeFile(path: path, size: _asInt(raw['size'])));
      }

      _repositoryTreeCacheById[repositoryId] = _RepositoryTreeCacheEntry(
        files: files,
        createdAt: now,
      );
      return files;
    } on DioException catch (e) {
      _logQuery(
        'GET $requestUri -> ERROR ${e.response?.statusCode ?? 'network'}: ${e.message}',
      );
      return const <_HfTreeFile>[];
    } catch (e) {
      _logQuery('GET $requestUri failed: $e');
      return const <_HfTreeFile>[];
    }
  }

  String _encodeRepositoryPath(String repositoryId) {
    final parts = repositoryId.split('/');
    if (parts.length < 2) {
      return Uri.encodeComponent(repositoryId);
    }

    final namespace = Uri.encodeComponent(parts.first);
    final repoName = Uri.encodeComponent(parts.sublist(1).join('/'));
    return '$namespace/$repoName';
  }

  _HfRepositorySummary? _parseRepositorySummary(dynamic raw) {
    if (raw is! Map) {
      return null;
    }

    final id = (raw['id'] as String?)?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }

    final tags = <String>{};
    final tagsRaw = raw['tags'];
    if (tagsRaw is List) {
      for (final value in tagsRaw) {
        if (value is String && value.trim().isNotEmpty) {
          tags.add(value.trim().toLowerCase());
        }
      }
    }

    final files = <_HfTreeFile>[];
    final siblingsRaw = raw['siblings'];
    if (siblingsRaw is List) {
      for (final sibling in siblingsRaw) {
        if (sibling is! Map) {
          continue;
        }
        final path = (sibling['rfilename'] as String?)?.trim();
        if (path == null || path.isEmpty) {
          continue;
        }
        files.add(_HfTreeFile(path: path, size: _asInt(sibling['size'])));
      }
    }

    final pipelineTag = (raw['pipeline_tag'] as String?)?.trim();

    int? numParameters;
    final numParametersRaw = raw['numParameters'];
    if (numParametersRaw is num && numParametersRaw > 0) {
      numParameters = numParametersRaw.toInt();
    }

    return _HfRepositorySummary(
      id: id,
      downloads: _asInt(raw['downloads']),
      likes: _asInt(raw['likes']),
      tags: tags,
      files: files,
      pipelineTag: pipelineTag,
      numParameters: numParameters,
    );
  }

  HfDiscoveredModel? _buildDiscoveredModel({
    required _HfRepositorySummary summary,
  }) {
    final files = summary.files;
    if (files.isEmpty) {
      return null;
    }

    final modelFile = _pickPrimaryModelFile(files);
    if (modelFile == null) {
      return null;
    }

    final projectorFile = _pickProjectorFile(files);

    final supportsAudio = _inferAudioSupport(
      tags: summary.tags,
      pipelineTag: summary.pipelineTag,
    );
    final supportsVision = _inferVisionSupport(
      tags: summary.tags,
      pipelineTag: summary.pipelineTag,
      hasProjector: projectorFile != null,
      supportsAudio: supportsAudio,
    );

    final modelScaleB = summary.numParameters == null
        ? null
        : summary.numParameters! / 1e9;

    const supportsThinking = false;
    const supportsToolCalling = false;

    final hasModelSize = modelFile.size > 0;
    final hasProjectorSize = projectorFile == null || projectorFile.size > 0;
    final hasExactBundleSize = hasModelSize && hasProjectorSize;
    final totalBytes = hasExactBundleSize
        ? modelFile.size + (projectorFile?.size ?? 0)
        : 0;
    final minRamGb = totalBytes > 0 ? _estimateMinRamGb(totalBytes) : 0;
    final modelName = _buildDisplayName(summary.id);
    final defaultContext = supportsAudio
        ? 4096
        : (modelScaleB != null && modelScaleB <= 1.0)
        ? 4096
        : 8192;
    final maxTokens = (supportsVision || supportsAudio) ? 1024 : 2048;

    final model = DownloadableModel(
      name: modelName,
      description: _buildDescription(
        supportsVision: supportsVision,
        supportsAudio: supportsAudio,
        supportsToolCalling: supportsToolCalling,
        supportsThinking: supportsThinking,
        modelScaleB: modelScaleB,
      ),
      url: _buildResolveUrl(summary.id, modelFile.path),
      filename: modelFile.filename,
      mmprojUrl: projectorFile == null
          ? null
          : _buildResolveUrl(summary.id, projectorFile.path),
      mmprojFilename: projectorFile?.filename,
      sizeBytes: totalBytes,
      supportsVision: supportsVision,
      supportsAudio: supportsAudio,
      supportsToolCalling: supportsToolCalling,
      supportsThinking: supportsThinking,
      minRamGb: minRamGb,
      preset: ModelPreset(
        temperature: 0.2,
        topK: 40,
        topP: 0.9,
        contextSize: defaultContext,
        maxTokens: maxTokens,
        thinkingEnabled: false,
      ),
    );

    return HfDiscoveredModel(
      model: model,
      repositoryId: summary.id,
      downloads: summary.downloads,
      likes: summary.likes,
      hasLiveStats: true,
      modelScaleB: modelScaleB,
    );
  }

  _HfTreeFile? _pickPrimaryModelFile(List<_HfTreeFile> files) {
    final candidates = files
        .where((file) {
          final lower = file.path.toLowerCase();
          if (!lower.endsWith('.gguf')) {
            return false;
          }
          if (lower.contains('mmproj') || lower.contains('projector')) {
            return false;
          }
          if (lower.contains('vocoder') || lower.contains('tokenizer')) {
            return false;
          }
          if (lower.contains('-00001-of-') || lower.contains('-0001-of-')) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) {
      final scoreA = _modelFileScore(a.path);
      final scoreB = _modelFileScore(b.path);
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA);
      }
      return a.size.compareTo(b.size);
    });
    return candidates.first;
  }

  _HfTreeFile? _pickProjectorFile(List<_HfTreeFile> files) {
    final candidates = files
        .where((file) {
          final lower = file.path.toLowerCase();
          if (!lower.endsWith('.gguf')) {
            return false;
          }
          return lower.contains('mmproj') || lower.contains('projector');
        })
        .toList(growable: false);

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) {
      final scoreA = _projectorFileScore(a.path);
      final scoreB = _projectorFileScore(b.path);
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA);
      }
      return a.size.compareTo(b.size);
    });
    return candidates.first;
  }

  int _modelFileScore(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('q4_k_m')) return 120;
    if (lower.contains('q4_0')) return 116;
    if (lower.contains('q4_1')) return 114;
    if (lower.contains('q5_k_m')) return 110;
    if (lower.contains('q5_0')) return 106;
    if (lower.contains('q6_k')) return 102;
    if (lower.contains('q8_0')) return 96;
    if (lower.contains('q3_k_m')) return 92;
    if (lower.contains('q3')) return 88;
    if (lower.contains('q2_k')) return 84;
    if (lower.contains('f16') ||
        lower.contains('bf16') ||
        lower.contains('fp16')) {
      return 72;
    }
    return 60;
  }

  int _projectorFileScore(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('q8_0')) return 120;
    if (lower.contains('q6')) return 112;
    if (lower.contains('q5')) return 108;
    if (lower.contains('q4')) return 104;
    if (lower.contains('f16') ||
        lower.contains('bf16') ||
        lower.contains('fp16')) {
      return 100;
    }
    return 90;
  }

  bool _inferVisionSupport({
    required Set<String> tags,
    required String? pipelineTag,
    required bool hasProjector,
    required bool supportsAudio,
  }) {
    final hasVisionSignal =
        pipelineTag == 'image-text-to-text' ||
        tags.contains('image-text-to-text');

    if (hasVisionSignal) {
      return true;
    }
    if (hasProjector && !supportsAudio) {
      return true;
    }
    return false;
  }

  bool _inferAudioSupport({
    required Set<String> tags,
    required String? pipelineTag,
  }) {
    return pipelineTag == 'audio-text-to-text' ||
        tags.contains('audio-text-to-text');
  }

  int _estimateMinRamGb(int totalBytes) {
    final gib = totalBytes / (1024 * 1024 * 1024);
    return math.max(2, (gib * 1.8).ceil());
  }

  String _buildDisplayName(String repositoryId) {
    final repoName = repositoryId.split('/').last;
    var cleaned = repoName
        .replaceAll(RegExp(r'-?gguf$', caseSensitive: false), '')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) {
      cleaned = repoName;
    }

    return cleaned
        .split(' ')
        .map((token) {
          if (token.isEmpty) {
            return token;
          }
          if (RegExp(r'^[A-Z0-9.]+$').hasMatch(token)) {
            return token;
          }
          return token[0].toUpperCase() + token.substring(1);
        })
        .join(' ');
  }

  String _buildDescription({
    required bool supportsVision,
    required bool supportsAudio,
    required bool supportsToolCalling,
    required bool supportsThinking,
    required double? modelScaleB,
  }) {
    final capability = <String>[];
    if (supportsThinking) capability.add('thinking');
    if (supportsToolCalling) capability.add('tools');
    if (supportsVision) capability.add('vision');
    if (supportsAudio) capability.add('audio');

    final scaleLabel = modelScaleB == null
        ? 'unknown scale'
        : modelScaleB >= 1.0
        ? '${modelScaleB.toStringAsFixed(modelScaleB >= 10 ? 0 : 1)}B'
        : '${(modelScaleB * 1000).toStringAsFixed(0)}M';

    if (capability.isEmpty) {
      return 'Popular GGUF model ($scaleLabel).';
    }

    return 'Popular GGUF model ($scaleLabel) with ${capability.join(', ')}.';
  }

  String _buildResolveUrl(String repositoryId, String filePath) {
    final encodedPath = filePath.split('/').map(Uri.encodeComponent).join('/');
    return 'https://huggingface.co/$repositoryId/resolve/main/$encodedPath?download=true';
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

class _DiscoveryCacheEntry {
  final List<HfDiscoveredModel> models;
  final DateTime createdAt;

  const _DiscoveryCacheEntry({required this.models, required this.createdAt});
}

class _RepositoryTreeCacheEntry {
  final List<_HfTreeFile> files;
  final DateTime createdAt;

  const _RepositoryTreeCacheEntry({
    required this.files,
    required this.createdAt,
  });
}

class _SearchRequest {
  final String? search;
  final String? library;
  final String? pipelineTag;
  final String sort;

  const _SearchRequest({
    this.search,
    this.library,
    this.pipelineTag,
    required this.sort,
  });
}

class _HfRepositorySummary {
  final String id;
  final int downloads;
  final int likes;
  final Set<String> tags;
  final List<_HfTreeFile> files;
  final String? pipelineTag;
  final int? numParameters;

  const _HfRepositorySummary({
    required this.id,
    required this.downloads,
    required this.likes,
    required this.tags,
    required this.files,
    required this.pipelineTag,
    required this.numParameters,
  });
}

class _HfTreeFile {
  final String path;
  final int size;

  const _HfTreeFile({required this.path, required this.size});

  String get filename {
    final parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }
}
