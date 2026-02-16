import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import 'package:file_picker/file_picker.dart';

import '../models/chat_message.dart';
import '../models/chat_settings.dart';
import '../models/downloadable_model.dart';
import '../services/chat_service.dart';
import '../services/settings_service.dart';

class ChatProvider extends ChangeNotifier {
  static const String _postToolFollowupInstruction =
      'Use the tool result messages above as authoritative facts. '
      'Answer the user directly from those results. '
      'Do not say you lack real-time access when tool results are present.';
  static const int _maxToolExecutionsPerToolPerTurn = 2;

  final ChatService _chatService;
  final SettingsService _settingsService;

  final List<ChatMessage> _messages = [];
  final List<LlamaContentPart> _stagedParts = [];
  ChatSettings _settings = const ChatSettings();

  // Chat session for stateful conversation
  ChatSession? _session;

  // Tool definitions and handlers
  final List<ToolDefinition> _tools = [];
  final Map<String, Future<String> Function(Map<String, dynamic>)>
  _toolHandlers = {};

  String _activeBackend = "Unknown";
  bool _gpuSupported = false;
  bool _isInitializing = false;
  double _loadingProgress = 0.0;
  bool _isLoaded = false;
  bool _isGenerating = false;
  bool _isShuttingDown = false;
  bool _supportsVision = false;
  bool _supportsAudio = false;
  bool _templateSupportsTools = true;
  ChatFormat? _detectedChatFormat;
  String? _error;

  // Telemetry
  int _contextLimit = 2048;
  int _currentTokens = 0;
  bool _isPruning = false;
  String _runtimeBackendRaw = '';
  bool _runtimeGpuActive = false;
  int? _runtimeGpuLayers;
  int? _runtimeThreads;
  String? _runtimeModelArchitecture;
  String? _runtimeModelSource;
  String? _runtimeModelCacheState;
  String? _runtimeBridgeNotes;
  int? _lastFirstTokenLatencyMs;
  int? _lastGenerationLatencyMs;

  List<String> _availableDevices = [];

  // Getters
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<LlamaContentPart> get stagedParts => List.unmodifiable(_stagedParts);
  ChatSettings get settings => _settings;
  String? get modelPath => _settings.modelPath;
  GpuBackend get preferredBackend => _settings.preferredBackend;
  String get activeBackend => _activeBackend;
  bool get gpuSupported => _gpuSupported;
  bool get isInitializing => _isInitializing;
  double get loadingProgress => _loadingProgress;
  bool get isLoaded => _isLoaded;
  bool get isGenerating => _isGenerating;
  bool get supportsVision => _supportsVision;
  bool get supportsAudio => _supportsAudio;
  bool get templateSupportsTools => _templateSupportsTools;
  ChatFormat? get detectedChatFormat => _detectedChatFormat;
  String? get error => _error;
  double get temperature => _settings.temperature;
  int get topK => _settings.topK;
  double get topP => _settings.topP;
  int get contextSize => _settings.contextSize;
  int get gpuLayers => _settings.gpuLayers;
  LlamaLogLevel get dartLogLevel => _settings.logLevel;
  LlamaLogLevel get nativeLogLevel => _settings.nativeLogLevel;
  int get contextLimit => _contextLimit; // Renamed from maxTokens
  int get maxGenerationTokens => _settings.maxTokens;
  int get currentTokens => _currentTokens;
  bool get isPruning => _isPruning;
  List<String> get availableDevices => _availableDevices;
  String get runtimeBackendRaw => _runtimeBackendRaw;
  bool get runtimeGpuActive => _runtimeGpuActive;
  int? get runtimeGpuLayers => _runtimeGpuLayers;
  int? get runtimeThreads => _runtimeThreads;
  String? get runtimeModelArchitecture => _runtimeModelArchitecture;
  String? get runtimeModelSource => _runtimeModelSource;
  String? get runtimeModelCacheState => _runtimeModelCacheState;
  String? get runtimeBridgeNotes => _runtimeBridgeNotes;
  int? get lastFirstTokenLatencyMs => _lastFirstTokenLatencyMs;
  int? get lastGenerationLatencyMs => _lastGenerationLatencyMs;
  bool get usingWebGpu =>
      _runtimeBackendRaw.toLowerCase().contains('webgpu') ||
      _activeBackend == 'WEBGPU';
  bool get toolsEnabled => _settings.toolsEnabled;
  bool get forceToolCall => _settings.forceToolCall;

  bool get isReady => _error == null && !_isInitializing && _isLoaded;

  ChatProvider({
    ChatService? chatService,
    SettingsService? settingsService,
    ChatSettings? initialSettings,
  }) : _chatService = chatService ?? ChatService(),
       _settingsService = settingsService ?? SettingsService(),
       _settings = initialSettings ?? const ChatSettings() {
    _initTools();
    if (chatService == null && settingsService == null) {
      _init();
    }
  }

  /// Initialize tool definitions with inline handlers.
  void _initTools() {
    // Time tool - no parameters
    _toolHandlers['get_current_time'] = (args) async {
      return DateTime.now().toIso8601String();
    };
    _tools.add(
      ToolDefinition(
        name: 'get_current_time',
        description: 'Get the current date and time',
        parameters: [],
        handler: (params) async => DateTime.now().toIso8601String(),
      ),
    );

    // Weather tool - with typed parameters
    _toolHandlers['get_current_weather'] = (args) async {
      final location =
          args['location'] as String? ??
          args['city'] as String? ??
          args['place'] as String? ??
          args['query'] as String? ??
          'Unknown';
      final unit = args['unit'] as String? ?? 'celsius';

      // Mock weather response
      final random = Random();
      final temp = 15 + random.nextInt(20);
      final conditions = [
        'Sunny',
        'Cloudy',
        'Rainy',
        'Clear',
      ][random.nextInt(4)];

      final unitSymbol = unit == 'fahrenheit' ? '°F' : '°C';
      final displayTemp = unit == 'fahrenheit'
          ? (temp * 9 / 5 + 32).round()
          : temp;

      return 'The weather in $location is $displayTemp$unitSymbol and $conditions.';
    };
    _tools.add(
      ToolDefinition(
        name: 'get_current_weather',
        description: 'Get the current weather for a location',
        parameters: [
          ToolParam.string(
            'location',
            description: 'The city and state, e.g. San Francisco, CA',
            required: true,
          ),
          ToolParam.enumType(
            'unit',
            values: ['celsius', 'fahrenheit'],
            description: 'Temperature unit',
          ),
        ],
        handler: (params) async => '', // Not used, we use _toolHandlers instead
      ),
    );
  }

  Future<void> _init() async {
    _settings = await _settingsService.loadSettings();
    try {
      final backendInfo = await _chatService.engine.getBackendName();
      _availableDevices = _parseBackendDevices(backendInfo);
      _activeBackend = _deriveActiveBackendLabel(
        backendInfo,
        preferredBackend: _settings.preferredBackend,
        gpuLayers: _settings.gpuLayers,
      );
    } catch (e) {
      debugPrint("Error fetching devices: $e");
    }
    notifyListeners();
  }

  Future<void> loadModel() async {
    if (_isInitializing) return;
    if (_settings.modelPath == null || _settings.modelPath!.isEmpty) {
      _error = 'Model path not set. Please configure in settings.';
      notifyListeners();
      return;
    }

    _isInitializing = true;
    _isLoaded = false;
    _error = null;
    _loadingProgress = 0.0;
    _activeBackend = "Refreshing...";
    notifyListeners();

    // Estimate dynamic settings if we have a model path but no custom settings yet
    // or if we're reloading and want to be safe.
    if (_settings.gpuLayers == 32 || _settings.gpuLayers == 99) {
      try {
        await estimateDynamicSettings();
      } catch (e) {
        debugPrint("Dynamic estimation failed: $e");
      }
    }

    try {
      await _chatService.engine.setDartLogLevel(_settings.logLevel);
      await _chatService.engine.setNativeLogLevel(_settings.nativeLogLevel);
      await _chatService.init(
        _settings,
        onProgress: (progress) {
          _loadingProgress = progress;
          _activeBackend =
              "Loading Model: ${(progress * 100).toStringAsFixed(0)}%";
          notifyListeners();
        },
      );

      if (!_chatService.engine.isReady) {
        throw Exception('Engine initialization did not complete.');
      }

      // Create chat session
      _session = ChatSession(
        _chatService.engine,
        maxContextTokens: _settings.contextSize > 0
            ? _settings.contextSize
            : null,
      );

      final rawBackend = await _chatService.engine.getBackendName();
      _availableDevices = _parseBackendDevices(rawBackend);
      _activeBackend = _deriveActiveBackendLabel(
        rawBackend,
        preferredBackend: _settings.preferredBackend,
        gpuLayers: _settings.gpuLayers,
      );

      _contextLimit = await _chatService.engine.getContextSize();
      _supportsVision = await _chatService.engine.supportsVision;
      _supportsAudio = await _chatService.engine.supportsAudio;
      final metadata = await _chatService.engine.getMetadata();
      _updateToolTemplateSupport(metadata);

      final libSupported = await _chatService.engine.isGpuSupported();
      _updateRuntimeDiagnostics(
        backendInfo: rawBackend,
        metadata: metadata,
        gpuActive: libSupported,
      );

      _gpuSupported =
          libSupported ||
          _availableDevices.any(
            (d) =>
                !d.toLowerCase().contains("cpu") &&
                !d.toLowerCase().contains("llvm"),
          );

      _addInfoMessage('Model loaded successfully! Ready to chat.');
      _isLoaded = true;
    } catch (e, stackTrace) {
      debugPrint('Error loading model: $e');
      debugPrint(stackTrace.toString());
      _error = e.toString();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void clearConversation() {
    _messages.clear();
    _session?.reset();
    _currentTokens = 0;
    _isPruning = false;
    _isGenerating = false;
    _stagedParts.clear();
    _messages.add(
      ChatMessage(
        text: 'Conversation cleared. Ready for a new topic!',
        isUser: false,
        isInfo: true,
      ),
    );
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (_isGenerating || _session == null) return;

    if (!_chatService.engine.isReady) {
      _messages.add(
        ChatMessage(
          text: 'Model is not ready yet. Please reload and try again.',
          isUser: false,
          isInfo: true,
        ),
      );
      notifyListeners();
      return;
    }

    final parts = List<LlamaContentPart>.from(_stagedParts);
    // Don't add text here - ChatSession.chat will handle it

    if (parts.isEmpty && text.isEmpty) return;

    // For UI display, include text in parts
    final displayParts = [
      ...parts,
      if (text.isNotEmpty) LlamaTextContent(text),
    ];
    final userMsg = ChatMessage(text: text, isUser: true, parts: displayParts);
    _messages.add(userMsg);
    _stagedParts.clear();
    _isGenerating = true;
    notifyListeners();

    await _generateResponse(
      text,
      parts: parts.isEmpty ? null : parts,
      toolChoiceForTurn: _settings.forceToolCall
          ? ToolChoice.required
          : ToolChoice.auto,
    );
  }

  /// Maximum number of tool call iterations per user message.
  static const int _maxToolIterations = 5;

  Future<void> _generateResponse(
    String text, {
    List<LlamaContentPart>? parts,
    int remainingToolIterations = _maxToolIterations,
    ToolChoice? toolChoiceForTurn,
  }) async {
    final generationStopwatch = Stopwatch()..start();
    var sawFirstToken = false;
    String fullResponse = "";
    String fullThinking = "";
    _lastFirstTokenLatencyMs = null;

    try {
      _messages.add(ChatMessage(text: "...", isUser: false));
      notifyListeners();

      DateTime lastUpdate = DateTime.now();

      // Use ChatSession for generation
      final params = GenerationParams(
        maxTokens: _settings.maxTokens,
        temp: _settings.temperature,
        topK: _settings.topK,
        topP: _settings.topP,
        penalty: 1.1,
      );

      // Build parts list with text
      final chatParts = <LlamaContentPart>[
        ...?parts,
        if (text.isNotEmpty) LlamaTextContent(text),
      ];

      // Tools passed per-request now (caller-managed pattern)
      final tools = _settings.toolsEnabled ? _tools : null;

      await for (final chunk in _session!.create(
        chatParts,
        params: params,
        tools: tools,
        toolChoice: tools != null ? toolChoiceForTurn : null,
      )) {
        if (!_isGenerating) {
          break;
        }

        final delta = chunk.choices.first.delta;

        // Accumulate both content and thinking
        final content = delta.content ?? '';
        final thinking = delta.thinking ?? '';

        if (!sawFirstToken &&
            (content.isNotEmpty ||
                thinking.isNotEmpty ||
                (delta.toolCalls?.isNotEmpty ?? false))) {
          _lastFirstTokenLatencyMs = generationStopwatch.elapsedMilliseconds;
          sawFirstToken = true;
        }

        fullResponse += content;

        // Unescape literal newlines/returns if they appear in thinking content
        // This handles cases where the model outputs escaped strings
        final unescapedThinking = thinking
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\r', '\r');
        fullThinking += unescapedThinking;

        _currentTokens++;

        final cleanText = _chatService.cleanResponse(fullResponse);

        // Find the "current" assistant message (should be the last one)
        if (_messages.isNotEmpty && !_messages.last.isUser) {
          final parts = <LlamaContentPart>[];
          if (fullThinking.isNotEmpty) {
            parts.add(LlamaThinkingContent(fullThinking));
          }
          if (cleanText.isNotEmpty) {
            parts.add(LlamaTextContent(cleanText));
          }

          _messages[_messages.length - 1] = _messages.last.copyWith(
            text: cleanText,
            parts: parts,
          );

          if (DateTime.now().difference(lastUpdate).inMilliseconds > 50) {
            notifyListeners();
            lastUpdate = DateTime.now();
          }
        }
      }

      // Final update
      if (_messages.isNotEmpty && !_messages.last.isUser) {
        final lastSessionMessage = _session!.history.isNotEmpty
            ? _session!.history.last
            : null;
        final hasToolCallOnlyTurn =
            (lastSessionMessage?.parts
                    .whereType<LlamaToolCallContent>()
                    .isNotEmpty ??
                false) &&
            fullResponse.trim().isEmpty &&
            fullThinking.trim().isEmpty;

        if (hasToolCallOnlyTurn) {
          _messages.removeLast();
        }

        final hadRawThinkingTags = _containsReasoningTag(fullResponse);
        final hadThinkingStream = fullThinking.trim().isNotEmpty;
        final normalized = _normalizeAssistantOutput(
          streamedContent: fullResponse,
          streamedThinking: fullThinking,
        );
        var finalText = normalized.text;
        final finalThinking = normalized.thinking;
        final debugBadges = kDebugMode
            ? _buildAssistantDebugBadges(
                hadRawThinkingTags: hadRawThinkingTags,
                hadThinkingStream: hadThinkingStream,
                finalThinking: finalThinking,
                finalText: finalText,
              )
            : <String>[];

        if (_settings.toolsEnabled &&
            _looksLikeToolResultDisclaimer(finalText)) {
          final fallback = _buildRecentToolResultSummary();
          if (fallback != null && fallback.isNotEmpty) {
            finalText = fallback;
            if (kDebugMode) {
              debugBadges.add('fallback:tool-result');
            }
          }
        }

        if (_messages.isNotEmpty && !_messages.last.isUser) {
          final parts = <LlamaContentPart>[];
          if (finalThinking.isNotEmpty) {
            parts.add(LlamaThinkingContent(finalThinking));
          }
          if (finalText.isNotEmpty) {
            parts.add(LlamaTextContent(finalText));
          }

          _messages[_messages.length - 1] = _messages.last.copyWith(
            text: finalText,
            parts: parts,
            debugBadges: debugBadges,
          );
          _messages.last.tokenCount = await _chatService.engine.getTokenCount(
            finalText,
          );
        }
      }

      // Check for tool calls in the session history and execute them
      if (_settings.toolsEnabled && _session!.history.isNotEmpty) {
        final lastMsg = _session!.history.last;
        final toolCalls = lastMsg.parts
            .whereType<LlamaToolCallContent>()
            .toList();

        if (toolCalls.isNotEmpty) {
          if (remainingToolIterations > 0) {
            await _executeToolCalls(toolCalls, remainingToolIterations - 1);
            return; // _executeToolCalls handles the rest
          }

          _addInfoMessage(
            'Stopped after $_maxToolIterations tool-call rounds to prevent an infinite loop.',
          );
        }
      }
    } catch (e) {
      final errorText = e.toString();
      if (errorText.contains('mtmd_tokenize failed')) {
        _messages.add(
          ChatMessage(
            text:
                'Vision processing failed for this prompt. Try reloading the '
                'model, using the bundled mmproj, or reducing image size.',
            isUser: false,
            isInfo: true,
          ),
        );
      } else {
        _messages.add(ChatMessage(text: 'Error: $e', isUser: false));
      }
    } finally {
      generationStopwatch.stop();
      if (sawFirstToken || fullResponse.isNotEmpty || fullThinking.isNotEmpty) {
        _lastGenerationLatencyMs = generationStopwatch.elapsedMilliseconds;
      }
      _isGenerating = false;
      notifyListeners();
    }
  }

  ({String text, String thinking}) _normalizeAssistantOutput({
    required String streamedContent,
    required String streamedThinking,
  }) {
    var normalizedText = _chatService.cleanResponse(streamedContent);
    var normalizedThinking = streamedThinking;

    final shouldParseForNormalization =
        _settings.toolsEnabled ||
        normalizedText.contains('<think>') ||
        normalizedText.contains('</think>') ||
        normalizedText.trimLeft().startsWith('{');

    if (!shouldParseForNormalization) {
      return (text: normalizedText, thinking: normalizedThinking);
    }

    final parseFormat = _detectedChatFormat == ChatFormat.contentOnly
        ? ChatFormat.generic
        : (_detectedChatFormat ?? ChatFormat.generic);

    try {
      final parsed = ChatTemplateEngine.parse(
        parseFormat.index,
        streamedContent,
        parseToolCalls: true,
      );

      final parsedText = _chatService.cleanResponse(parsed.content);
      if (parsed.hasToolCalls) {
        normalizedText = '';
      } else if (parsedText.isNotEmpty) {
        normalizedText = parsedText;
      }

      final parsedReasoning = parsed.reasoningContent?.trim();
      if (normalizedThinking.isEmpty &&
          parsedReasoning != null &&
          parsedReasoning.isNotEmpty) {
        normalizedThinking = parsedReasoning;
      }
    } catch (_) {
      // Keep streamed values when parsing fails.
    }

    if (normalizedThinking.isEmpty) {
      final extracted = _extractMinistralReasoningHeuristic(normalizedText);
      if (extracted != null) {
        normalizedThinking = extracted.reasoning;
        normalizedText = extracted.answer;
      }
    }

    return (text: normalizedText, thinking: normalizedThinking);
  }

  ({String reasoning, String answer})? _extractMinistralReasoningHeuristic(
    String text,
  ) {
    final trimmed = text.trim();
    if (trimmed.length < 64) {
      return null;
    }

    final repeatedQuotedAnswer = RegExp(
      r'^(.*?)(?:\n+\s*(?:Response|Final answer|Answer)\s*:\s*)?"([^"\n]{4,})"\s*(?:\2)?\s*$',
      dotAll: true,
    ).firstMatch(trimmed);

    if (repeatedQuotedAnswer != null) {
      final reasoning = repeatedQuotedAnswer.group(1)?.trim() ?? '';
      final answer = repeatedQuotedAnswer.group(2)?.trim() ?? '';
      if (reasoning.length >= 24 && answer.isNotEmpty) {
        return (reasoning: reasoning, answer: answer);
      }
    }

    final plainTailAnswer = RegExp(
      r'^(.*?)(?:\n+\s*(?:Response|Final answer|Answer)\s*:\s*)([^\n]{4,})\s*$',
      dotAll: true,
    ).firstMatch(trimmed);

    if (plainTailAnswer != null) {
      final reasoning = plainTailAnswer.group(1)?.trim() ?? '';
      final answer = plainTailAnswer.group(2)?.trim() ?? '';
      if (reasoning.length >= 24 && answer.isNotEmpty) {
        return (reasoning: reasoning, answer: answer);
      }
    }

    return null;
  }

  bool _containsReasoningTag(String text) {
    return text.contains('<think>') ||
        text.contains('</think>') ||
        text.contains('[THINK]') ||
        text.contains('[/THINK]');
  }

  List<String> _buildAssistantDebugBadges({
    required bool hadRawThinkingTags,
    required bool hadThinkingStream,
    required String finalThinking,
    required String finalText,
  }) {
    final badges = <String>[];
    final formatName = (_detectedChatFormat ?? ChatFormat.generic).name;
    badges.add('fmt:$formatName');

    final hasFinalThinking = finalThinking.trim().isNotEmpty;
    final thinkingSource = hadThinkingStream
        ? 'stream'
        : hasFinalThinking && hadRawThinkingTags
        ? 'tag-parse'
        : hasFinalThinking
        ? 'parse'
        : 'none';
    badges.add('think:$thinkingSource');

    final trimmed = finalText.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      badges.add('content:json');
    }

    return badges;
  }

  bool _looksLikeToolResultDisclaimer(String text) {
    final lower = text.toLowerCase();
    return lower.contains("don't have real-time access") ||
        lower.contains('do not have real-time access') ||
        lower.contains("can't access real-time") ||
        lower.contains('cannot access real-time') ||
        lower.contains('no real-time access') ||
        lower.contains('fictional response') ||
        lower.contains('as an ai') && lower.contains('real-time');
  }

  String? _buildRecentToolResultSummary() {
    final start = _indexAfterLastUserMessage();
    final seen = <String>{};
    final summaries = <MapEntry<String, String>>[];

    for (int i = start; i < _messages.length; i++) {
      final message = _messages[i];
      final results = message.parts?.whereType<LlamaToolResultContent>();
      if (results == null) {
        continue;
      }

      for (final result in results) {
        final raw = result.result;
        final rendered = raw is String ? raw.trim() : jsonEncode(raw).trim();
        if (rendered.isEmpty) {
          continue;
        }

        final key = '${result.id ?? result.name}:$rendered';
        if (!seen.add(key)) {
          continue;
        }

        summaries.add(MapEntry(result.name, rendered));
      }
    }

    if (summaries.isEmpty) {
      return null;
    }
    if (summaries.length == 1) {
      return summaries.first.value;
    }
    return summaries
        .map((entry) {
          final prefix = entry.key.isNotEmpty ? '${entry.key}: ' : '';
          return '- $prefix${entry.value}';
        })
        .join('\n');
  }

  void _updateRuntimeDiagnostics({
    required String backendInfo,
    required Map<String, String> metadata,
    required bool gpuActive,
  }) {
    _runtimeBackendRaw = backendInfo;
    _runtimeGpuLayers = int.tryParse(
      metadata['llamadart.webgpu.n_gpu_layers'] ?? '',
    );
    _runtimeThreads = int.tryParse(
      metadata['llamadart.webgpu.n_threads'] ?? '',
    );
    _runtimeModelArchitecture = metadata['general.architecture'];
    final modelSource = metadata['llamadart.webgpu.model_source']?.trim();
    _runtimeModelSource = modelSource == null || modelSource.isEmpty
        ? null
        : modelSource.toUpperCase();
    final cacheState = metadata['llamadart.webgpu.model_cache_state']?.trim();
    _runtimeModelCacheState = cacheState == null || cacheState.isEmpty
        ? null
        : cacheState;
    final runtimeNotes = metadata['llamadart.webgpu.runtime_notes']?.trim();
    _runtimeBridgeNotes = runtimeNotes == null || runtimeNotes.isEmpty
        ? null
        : runtimeNotes;

    final lower = backendInfo.toLowerCase();
    final likelyGpuBackend =
        lower.contains('webgpu') ||
        _containsBackendMarker(backendInfo, GpuBackend.metal) ||
        _containsBackendMarker(backendInfo, GpuBackend.vulkan) ||
        _containsBackendMarker(backendInfo, GpuBackend.cuda) ||
        _containsBackendMarker(backendInfo, GpuBackend.blas);

    final forcedCpu =
        _settings.preferredBackend == GpuBackend.cpu ||
        _settings.gpuLayers == 0;
    if (forcedCpu) {
      _runtimeGpuActive = false;
      return;
    }

    if (_runtimeGpuLayers != null) {
      _runtimeGpuActive =
          _runtimeGpuLayers! > 0 && (gpuActive || likelyGpuBackend);
      return;
    }

    if (_settings.preferredBackend != GpuBackend.auto) {
      _runtimeGpuActive = _containsBackendMarker(
        backendInfo,
        _settings.preferredBackend,
      );
      return;
    }

    _runtimeGpuActive = gpuActive || likelyGpuBackend;
  }

  /// Execute tool calls and continue the conversation with results.
  Future<void> _executeToolCalls(
    List<LlamaToolCallContent> toolCalls,
    int remainingIterations,
  ) async {
    _removeRawToolCallPlaceholderMessages(toolCalls);

    final freshToolCalls = toolCalls
        .where((call) => !_hasCompletedEquivalentToolCall(call))
        .toList(growable: false);

    final budgetedToolCalls = freshToolCalls
        .where((call) {
          final completedForName = _completedToolCountForName(call.name);
          return completedForName < _maxToolExecutionsPerToolPerTurn;
        })
        .toList(growable: false);

    if (freshToolCalls.isEmpty || budgetedToolCalls.isEmpty) {
      _addInfoMessage(
        'Model repeated tool calls. Requesting a direct answer without tools.',
      );
      notifyListeners();
      await _generateResponse(
        '',
        parts: [],
        remainingToolIterations: 0,
        toolChoiceForTurn: ToolChoice.none,
      );
      return;
    }

    if (budgetedToolCalls.length < freshToolCalls.length) {
      _addInfoMessage(
        'Skipping repeated tool calls for the same function to avoid loops.',
      );
      notifyListeners();
    }

    for (final tc in budgetedToolCalls) {
      final toolMessageIndex = _ensureToolCallMessage(tc);
      final handler = _toolHandlers[tc.name];
      if (handler == null) {
        final errorResult = 'Unknown tool: ${tc.name}';
        _appendToolResultToMessage(
          toolMessageIndex,
          LlamaToolResultContent(id: tc.id, name: tc.name, result: errorResult),
        );

        _session!.addMessage(
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: tc.id,
                name: tc.name,
                result: errorResult,
              ),
            ],
          ),
        );

        notifyListeners();
        continue;
      }

      final args = tc.arguments;

      final result = await handler(args);

      _appendToolResultToMessage(
        toolMessageIndex,
        LlamaToolResultContent(id: tc.id, name: tc.name, result: result),
      );
      notifyListeners();

      // Add tool result to session
      _session!.addMessage(
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [
            LlamaToolResultContent(id: tc.id, name: tc.name, result: result),
          ],
        ),
      );
    }

    // Continue generation to get final response with tool results
    await _generateResponse(
      _postToolFollowupInstruction,
      parts: [],
      remainingToolIterations: remainingIterations,
      toolChoiceForTurn: null,
    );
  }

  bool _hasCompletedEquivalentToolCall(LlamaToolCallContent target) {
    final start = _indexAfterLastUserMessage();

    for (int i = _messages.length - 1; i >= start; i--) {
      final message = _messages[i];
      final calls = message.parts?.whereType<LlamaToolCallContent>().toList();
      final results = message.parts
          ?.whereType<LlamaToolResultContent>()
          .toList();

      if (calls == null ||
          calls.isEmpty ||
          results == null ||
          results.isEmpty) {
        continue;
      }

      for (final call in calls) {
        final sameId =
            call.id != null && target.id != null && call.id == target.id;
        final sameNameAndArgs =
            call.name == target.name &&
            mapEquals(call.arguments, target.arguments);
        if (!sameId && !sameNameAndArgs) {
          continue;
        }

        final hasMatchingResult = results.any((result) {
          if (result.id != null && call.id != null) {
            return result.id == call.id;
          }
          return result.name == call.name;
        });

        if (hasMatchingResult) {
          return true;
        }
      }
    }

    return false;
  }

  int _completedToolCountForName(String name) {
    if (name.isEmpty) {
      return 0;
    }

    final start = _indexAfterLastUserMessage();
    var count = 0;

    for (int i = start; i < _messages.length; i++) {
      final message = _messages[i];
      final results = message.parts?.whereType<LlamaToolResultContent>();
      if (results == null) {
        continue;
      }
      for (final result in results) {
        if (result.name == name) {
          count++;
        }
      }
    }

    return count;
  }

  int _ensureToolCallMessage(LlamaToolCallContent toolCall) {
    final existingIndex = _findToolCallMessageIndex(toolCall);
    if (existingIndex >= 0) {
      return existingIndex;
    }

    _messages.add(
      ChatMessage(
        text: toolCall.rawJson,
        isUser: false,
        role: LlamaChatRole.assistant,
        parts: [toolCall],
      ),
    );
    return _messages.length - 1;
  }

  int _findToolCallMessageIndex(LlamaToolCallContent target) {
    final start = _indexAfterLastUserMessage();
    for (int i = _messages.length - 1; i >= start; i--) {
      final message = _messages[i];
      final calls = message.parts?.whereType<LlamaToolCallContent>();
      if (calls == null) continue;

      for (final call in calls) {
        if (_isSameToolCall(call, target)) {
          return i;
        }
      }
    }
    return -1;
  }

  int _indexAfterLastUserMessage() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isUser) {
        return i + 1;
      }
    }
    return 0;
  }

  bool _isSameToolCall(LlamaToolCallContent a, LlamaToolCallContent b) {
    if (a.id != null && b.id != null) {
      return a.id == b.id;
    }
    return a.name == b.name && mapEquals(a.arguments, b.arguments);
  }

  void _removeRawToolCallPlaceholderMessages(List<LlamaToolCallContent> calls) {
    if (calls.isEmpty || _messages.isEmpty) {
      return;
    }

    final callNames = calls.map((c) => c.name).toSet();
    final start = _indexAfterLastUserMessage();

    for (int i = _messages.length - 1; i >= start; i--) {
      final msg = _messages[i];
      if (msg.isUser || msg.isInfo) {
        continue;
      }

      final hasToolParts =
          msg.parts?.any(
            (p) => p is LlamaToolCallContent || p is LlamaToolResultContent,
          ) ??
          false;
      if (hasToolParts) {
        continue;
      }

      if (_looksLikeToolCallPlaceholder(msg.text, callNames)) {
        _messages.removeAt(i);
      }
    }
  }

  bool _looksLikeToolCallPlaceholder(String text, Set<String> callNames) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final containsToolName = callNames.any((name) => trimmed.contains(name));
    if (!containsToolName) {
      return false;
    }

    final bracketCall = RegExp(r'^\[[^\]]+\(.*\)\]$').hasMatch(trimmed);
    if (bracketCall) {
      return true;
    }

    return trimmed.startsWith('{') ||
        trimmed.startsWith('<function') ||
        trimmed.startsWith('<start_function_call>') ||
        trimmed.startsWith('<start_function_response>') ||
        trimmed.startsWith('<tool_call') ||
        trimmed.contains('<end_function_call>') ||
        trimmed.contains('<end_function_response>') ||
        trimmed.contains('"arguments"') ||
        trimmed.contains('"tool_call"') ||
        trimmed.contains('tool_calls');
  }

  void _appendToolResultToMessage(
    int messageIndex,
    LlamaToolResultContent result,
  ) {
    if (messageIndex < 0 || messageIndex >= _messages.length) {
      return;
    }

    final message = _messages[messageIndex];
    final updatedParts = List<LlamaContentPart>.from(message.parts ?? const []);

    final hasExistingResult = updatedParts
        .whereType<LlamaToolResultContent>()
        .any((existing) {
          if (result.id != null && existing.id != null) {
            return existing.id == result.id;
          }
          return existing.name == result.name;
        });

    if (hasExistingResult) {
      return;
    }

    updatedParts.add(result);
    _messages[messageIndex] = message.copyWith(parts: updatedParts);
  }

  void _addInfoMessage(String text) {
    final last = _messages.isNotEmpty ? _messages.last : null;
    if (last != null && last.isInfo && last.text == text) {
      return;
    }

    _messages.add(ChatMessage(text: text, isUser: false, isInfo: true));
  }

  void addStagedPart(LlamaContentPart part) {
    _stagedParts.add(part);
    notifyListeners();
  }

  void removeStagedPart(int index) {
    if (index >= 0 && index < _stagedParts.length) {
      _stagedParts.removeAt(index);
      notifyListeners();
    }
  }

  Future<void> pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      if (kIsWeb) {
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          addStagedPart(LlamaImageContent(bytes: file.bytes!));
          return;
        }

        _addInfoMessage(
          'Could not read image bytes in browser. Try a different image file.',
        );
        notifyListeners();
        return;
      }

      if (file.path != null && file.path!.isNotEmpty) {
        addStagedPart(LlamaImageContent(path: file.path));
        return;
      }

      if (file.bytes != null && file.bytes!.isNotEmpty) {
        addStagedPart(LlamaImageContent(bytes: file.bytes!));
        return;
      }

      _addInfoMessage('Could not read selected image file.');
      notifyListeners();
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  Future<void> pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      if (kIsWeb) {
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          addStagedPart(LlamaAudioContent(bytes: file.bytes!));
          return;
        }

        _addInfoMessage(
          'Could not read audio bytes in browser. Try a different audio file.',
        );
        notifyListeners();
        return;
      }

      if (file.path != null && file.path!.isNotEmpty) {
        addStagedPart(LlamaAudioContent(path: file.path));
        return;
      }

      if (file.bytes != null && file.bytes!.isNotEmpty) {
        addStagedPart(LlamaAudioContent(bytes: file.bytes!));
        return;
      }

      _addInfoMessage('Could not read selected audio file.');
      notifyListeners();
    } catch (e) {
      debugPrint("Error picking audio: $e");
    }
  }

  void stopGeneration() {
    if (_isGenerating) {
      _chatService.cancelGeneration();
      _isGenerating = false;
      notifyListeners();
    }
  }

  void _updateSettings(ChatSettings newSettings) {
    _settings = newSettings;
    _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  void updateTemperature(double value) =>
      _updateSettings(_settings.copyWith(temperature: value));
  void updateTopK(int value) =>
      _updateSettings(_settings.copyWith(topK: value));
  void updateTopP(double value) =>
      _updateSettings(_settings.copyWith(topP: value));
  void updateContextSize(int value) {
    final effectiveContextSize = value == 0 ? 0 : value.clamp(512, 32768);
    _updateSettings(_settings.copyWith(contextSize: effectiveContextSize));
  }

  void updateMaxTokens(int value) =>
      _updateSettings(_settings.copyWith(maxTokens: value.clamp(512, 32768)));
  void updateGpuLayers(int value) =>
      _updateSettings(_settings.copyWith(gpuLayers: value));
  void updateLogLevel(LlamaLogLevel value) {
    _updateSettings(_settings.copyWith(logLevel: value));
    _chatService.engine.setDartLogLevel(value);
  }

  void updateNativeLogLevel(LlamaLogLevel value) {
    _updateSettings(_settings.copyWith(nativeLogLevel: value));
    _chatService.engine.setNativeLogLevel(value);
  }

  void updateToolsEnabled(bool value) {
    _updateSettings(_settings.copyWith(toolsEnabled: value));
  }

  void updateForceToolCall(bool value) {
    _updateSettings(_settings.copyWith(forceToolCall: value));
  }

  void updateModelPath(String path) {
    _settings = _settings.copyWith(modelPath: path);
    _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  /// Apply model-specific recommended generation and runtime parameters.
  void applyModelPreset(DownloadableModel model) {
    _updateSettings(
      _settings.copyWith(
        temperature: model.preset.temperature,
        topK: model.preset.topK,
        topP: model.preset.topP,
        contextSize: model.preset.contextSize,
        maxTokens: model.preset.maxTokens,
        gpuLayers: model.preset.gpuLayers,
        toolsEnabled: model.supportsToolCalling,
        forceToolCall: model.preset.forceToolCall && model.supportsToolCalling,
      ),
    );
  }

  void _updateToolTemplateSupport(Map<String, String> metadata) {
    final toolTemplate = metadata['tokenizer.chat_template.tool_use'];
    final defaultTemplate = metadata['tokenizer.chat_template'];

    final effectiveTemplate =
        (toolTemplate != null && toolTemplate.trim().isNotEmpty)
        ? toolTemplate
        : defaultTemplate;

    if (effectiveTemplate == null || effectiveTemplate.trim().isEmpty) {
      _detectedChatFormat = null;
      _templateSupportsTools = true;
      return;
    }

    final format = ChatTemplateEngine.detectFormat(effectiveTemplate);
    _detectedChatFormat = format;

    final hasDedicatedToolTemplate =
        toolTemplate != null && toolTemplate.trim().isNotEmpty;

    _templateSupportsTools =
        hasDedicatedToolTemplate || _formatCanUseTools(format);

    if (_settings.toolsEnabled && !_templateSupportsTools) {
      _settings = _settings.copyWith(toolsEnabled: false, forceToolCall: false);
      _settingsService.saveSettings(_settings);
      _messages.add(
        ChatMessage(
          text:
              'Tool calling disabled for this model: template is content-only.',
          isUser: false,
          isInfo: true,
        ),
      );
    }
  }

  bool _formatCanUseTools(ChatFormat format) {
    switch (format) {
      case ChatFormat.contentOnly:
        return false;
      default:
        return true;
    }
  }

  List<String> _parseBackendDevices(String backendInfo) {
    final parts = backendInfo
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (parts.isEmpty) {
      return [backendInfo];
    }
    return parts;
  }

  String _deriveActiveBackendLabel(
    String backendInfo, {
    required GpuBackend preferredBackend,
    required int gpuLayers,
  }) {
    if (preferredBackend == GpuBackend.cpu || gpuLayers == 0) {
      return 'CPU';
    }

    if (preferredBackend != GpuBackend.auto &&
        _containsBackendMarker(backendInfo, preferredBackend)) {
      return preferredBackend.name.toUpperCase();
    }

    final lower = backendInfo.toLowerCase();
    if (lower.contains('webgpu') || lower.contains('wgpu')) {
      return 'WEBGPU';
    }

    if (_containsBackendMarker(backendInfo, GpuBackend.metal)) {
      return 'METAL';
    }
    if (_containsBackendMarker(backendInfo, GpuBackend.vulkan)) {
      return 'VULKAN';
    }
    if (_containsBackendMarker(backendInfo, GpuBackend.cuda)) {
      return 'CUDA';
    }
    if (_containsBackendMarker(backendInfo, GpuBackend.blas)) {
      return 'BLAS';
    }
    if (_containsBackendMarker(backendInfo, GpuBackend.cpu)) {
      return 'CPU';
    }

    return backendInfo;
  }

  bool _containsBackendMarker(String value, GpuBackend backend) {
    final lower = value.toLowerCase();
    switch (backend) {
      case GpuBackend.metal:
        return lower.contains('metal') || lower.contains('mtl');
      case GpuBackend.vulkan:
        return lower.contains('vulkan');
      case GpuBackend.cuda:
        return lower.contains('cuda');
      case GpuBackend.blas:
        return lower.contains('blas');
      case GpuBackend.cpu:
        return lower.contains('cpu') || lower.contains('llvm');
      case GpuBackend.auto:
        return false;
    }
  }

  void updateMmprojPath(String path) {
    _settings = _settings.copyWith(mmprojPath: path);
    _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updatePreferredBackend(GpuBackend backend) async {
    _settings = _settings.copyWith(preferredBackend: backend);
    await _settingsService.saveSettings(_settings);
    _messages.add(
      ChatMessage(
        text: 'Switching backend to ${backend.name}...',
        isUser: false,
        isInfo: true,
      ),
    );
    notifyListeners();
    await loadModel();
  }

  Future<void> selectModelFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;

      final selectedPath = result.files.single.path;
      if (selectedPath == null) throw Exception('No file path');

      _settings = _settings.copyWith(modelPath: selectedPath);
      _error = null;
      await _settingsService.saveSettings(_settings);
      notifyListeners();
      await loadModel();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> selectMmprojFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;

      final selectedPath = result.files.single.path;
      if (selectedPath == null) throw Exception('No file path');

      _settings = _settings.copyWith(mmprojPath: selectedPath);
      await _settingsService.saveSettings(_settings);
      notifyListeners();
      await loadModel();
    } catch (e) {
      rethrow;
    }
  }

  @override
  void dispose() {
    stopGeneration();
    _session?.reset();
    _session = null;
    unawaited(_chatService.dispose());
    super.dispose();
  }

  Future<void> shutdown() async {
    if (_isShuttingDown) {
      return;
    }

    _isShuttingDown = true;
    try {
      stopGeneration();
      _session?.reset();
      _session = null;
      _isLoaded = false;
      await _chatService.dispose();
    } finally {
      _isShuttingDown = false;
    }
  }

  Future<void> estimateDynamicSettings() async {
    try {
      final vram = await _chatService.engine.getVramInfo();
      if (vram.total == 0) return;

      final freeVramGb = vram.free / (1024 * 1024 * 1024);

      // Heuristic: 1GB per 24 layers for a typical 7B model
      // Modern models have ~32 layers.
      // Small models (0.5B-1B) have ~24 layers.
      // Large models (7B-8B) have ~32 layers.
      // Very large models (70B) have ~80 layers.

      int recommendedLayers = (freeVramGb * 24).round();
      if (recommendedLayers > 100) recommendedLayers = 100;
      if (recommendedLayers < 0) recommendedLayers = 0;

      // Also set a conservative context size if VRAM is low
      int recommendedCtx = 4096;
      if (freeVramGb < 2.0) {
        recommendedCtx = 2048;
      }

      _settings = _settings.copyWith(
        gpuLayers: recommendedLayers,
        contextSize: recommendedCtx,
      );
      notifyListeners();
    } catch (e) {
      debugPrint("Error estimating dynamic settings: $e");
    }
  }
}
