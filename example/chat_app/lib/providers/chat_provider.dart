import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../models/chat_settings.dart';
import '../models/downloadable_model.dart';
import '../services/assistant_output_service.dart';
import '../services/chat_service.dart';
import '../services/chat_generation_service.dart';
import '../services/chat_session_service.dart';
import '../services/conversation_state_service.dart';
import '../services/runtime_profile_service.dart';
import '../services/settings_service.dart';
import '../services/tool_declaration_service.dart';
import '../utils/backend_utils.dart';

class ChatProvider extends ChangeNotifier {
  static const String _defaultToolDeclarationsJson = '''
[
  {
    "name": "getWeather",
    "description": "gets the weather for a requested city",
    "parameters": {
      "type": "object",
      "properties": {
        "city": {
          "type": "string"
        }
      },
      "required": ["city"]
    }
  }
]
''';

  final ChatService _chatService;
  final ChatGenerationService _chatGenerationService;
  final ChatSessionService _chatSessionService;
  final ConversationStateService _conversationStateService;
  final RuntimeProfileService _runtimeProfileService;
  final SettingsService _settingsService;
  final AssistantOutputService _assistantOutputService;
  final ToolDeclarationService _toolDeclarationService;

  final List<ChatMessage> _messages = [];
  final List<LlamaContentPart> _stagedParts = [];
  final List<ChatConversation> _conversations = [];
  ChatSettings _settings = const ChatSettings();
  String _activeConversationId = '';
  String? _loadedModelPath;
  String? _loadedMmprojPath;

  // Chat session for stateful conversation
  ChatSession? _session;

  // Tool declarations supplied by the user (schema only; no local execution).
  List<ToolDefinition> _declaredTools = const <ToolDefinition>[];
  String? _toolDeclarationsError;

  String _activeBackend = "Unknown";
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
  int? _runtimeGpuLayers;
  int? _runtimeThreads;
  int? _lastFirstTokenLatencyMs;
  int? _lastGenerationLatencyMs;
  double? _lastTokensPerSecond;

  List<String> _availableDevices = [];

  // Getters
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<LlamaContentPart> get stagedParts => List.unmodifiable(_stagedParts);
  List<ChatConversation> get conversations {
    final sorted = List<ChatConversation>.from(_conversations)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(sorted);
  }

  String get activeConversationId => _activeConversationId;
  ChatSettings get settings => _settings;
  String? get modelPath => _settings.modelPath;
  GpuBackend get preferredBackend => _settings.preferredBackend;
  String get activeBackend => _activeBackend;
  bool get isInitializing => _isInitializing;
  double get loadingProgress => _loadingProgress;
  bool get isLoaded => _isLoaded;
  bool get isGenerating => _isGenerating;
  bool get supportsVision => _supportsVision;
  bool get supportsAudio => _supportsAudio;
  bool get templateSupportsTools => _templateSupportsTools;
  String? get error => _error;
  double get temperature => _settings.temperature;
  int get topK => _settings.topK;
  double get topP => _settings.topP;
  double get minP => _settings.minP;
  double get penalty => _settings.penalty;
  int get contextSize => _settings.contextSize;
  int get gpuLayers => _settings.gpuLayers;
  int get numberOfThreads => _settings.numberOfThreads;
  int get numberOfThreadsBatch => _settings.numberOfThreadsBatch;
  LlamaLogLevel get dartLogLevel => _settings.logLevel;
  LlamaLogLevel get nativeLogLevel => _settings.nativeLogLevel;
  int get contextLimit => _contextLimit; // Renamed from maxTokens
  int get maxGenerationTokens => _settings.maxTokens;
  int get currentTokens => _currentTokens;
  bool get isPruning => _isPruning;
  List<String> get availableDevices => _availableDevices;
  int? get runtimeGpuLayers => _runtimeGpuLayers;
  int? get runtimeThreads => _runtimeThreads;
  int? get lastFirstTokenLatencyMs => _lastFirstTokenLatencyMs;
  int? get lastGenerationLatencyMs => _lastGenerationLatencyMs;
  double? get lastTokensPerSecond => _lastTokensPerSecond;
  String get activeModelName {
    final modelPath = _settings.modelPath;
    if (modelPath == null || modelPath.isEmpty) {
      return 'No model';
    }
    final normalized = modelPath.replaceAll('\\', '/');
    final pieces = normalized.split('/');
    final file = pieces.isNotEmpty ? pieces.last : modelPath;
    return file.split('?').first;
  }

  bool get toolsEnabled => _settings.toolsEnabled;
  String get toolDeclarations => _settings.toolDeclarations;
  String get defaultToolDeclarations => _defaultToolDeclarationsJson;
  String? get toolDeclarationsError => _toolDeclarationsError;
  int get declaredToolCount => _declaredTools.length;
  bool get thinkingEnabled => _settings.thinkingEnabled;
  int get thinkingBudgetTokens => _settings.thinkingBudgetTokens;
  bool get singleTurnMode => _settings.singleTurnMode;

  bool get isReady => _error == null && !_isInitializing && _isLoaded;

  ChatProvider({
    ChatService? chatService,
    ChatGenerationService? chatGenerationService,
    ChatSessionService? chatSessionService,
    ConversationStateService? conversationStateService,
    RuntimeProfileService? runtimeProfileService,
    SettingsService? settingsService,
    AssistantOutputService? assistantOutputService,
    ToolDeclarationService? toolDeclarationService,
    ChatSettings? initialSettings,
  }) : _chatService = chatService ?? ChatService(),
       _chatGenerationService =
           chatGenerationService ?? const ChatGenerationService(),
       _chatSessionService = chatSessionService ?? const ChatSessionService(),
       _conversationStateService =
           conversationStateService ?? const ConversationStateService(),
       _runtimeProfileService =
           runtimeProfileService ?? const RuntimeProfileService(),
       _settingsService = settingsService ?? SettingsService(),
       _assistantOutputService =
           assistantOutputService ?? const AssistantOutputService(),
       _toolDeclarationService =
           toolDeclarationService ?? const ToolDeclarationService(),
       _settings = initialSettings ?? const ChatSettings() {
    _createInitialConversation();
    _rebuildDeclaredToolsFromSettings();
    if (chatService == null && settingsService == null) {
      _init();
    }
  }

  void _createInitialConversation() {
    final id = _conversationStateService.newConversationId();
    _activeConversationId = id;
    _conversations.add(
      _conversationStateService.createEmptyConversation(
        id: id,
        settings: _settings,
      ),
    );
  }

  void _syncActiveConversationSnapshot({bool touchUpdatedAt = true}) {
    final index = _conversationStateService.activeConversationIndex(
      conversations: _conversations,
      activeConversationId: _activeConversationId,
    );
    if (index < 0) {
      return;
    }

    final existing = _conversations[index];
    _conversations[index] = _conversationStateService.buildSnapshot(
      existing: existing,
      messages: _messages,
      settings: _settings,
      currentTokens: _currentTokens,
      isPruning: _isPruning,
      touchUpdatedAt: touchUpdatedAt,
    );
  }

  void _restoreSessionFromMessages() {
    if (!_chatService.engine.isReady || !_isLoaded) {
      _session = null;
      return;
    }

    _session?.reset();
    _session = _chatSessionService.rebuildFromMessages(
      engine: _chatService.engine,
      contextSize: _settings.contextSize,
      systemPrompt: _sessionSystemPrompt(),
      messages: _messages,
    );
  }

  void createConversation() {
    _syncActiveConversationSnapshot();

    final id = _conversationStateService.newConversationId();
    final copiedSettings = _settings.copyWith();

    _messages.clear();
    _stagedParts.clear();
    _currentTokens = 0;
    _isPruning = false;
    _error = null;
    _isGenerating = false;
    _settings = copiedSettings;
    _rebuildDeclaredToolsFromSettings();

    _conversations.insert(
      0,
      _conversationStateService.createEmptyConversation(
        id: id,
        settings: copiedSettings,
      ),
    );
    _activeConversationId = id;

    if (_chatService.engine.isReady && _isLoaded) {
      _session?.reset();
      _session = _chatSessionService.createSession(
        engine: _chatService.engine,
        contextSize: _settings.contextSize,
        systemPrompt: _sessionSystemPrompt(),
      );
    } else {
      _session = null;
    }

    notifyListeners();
  }

  Future<void> switchConversation(String conversationId) async {
    if (conversationId == _activeConversationId) {
      return;
    }

    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index < 0) {
      return;
    }

    _syncActiveConversationSnapshot();
    final target = _conversations[index];

    _activeConversationId = target.id;
    _settings = target.settings;
    _rebuildDeclaredToolsFromSettings();
    _messages
      ..clear()
      ..addAll(target.messages);
    _currentTokens = target.currentTokens;
    _isPruning = target.isPruning;
    _stagedParts.clear();
    _error = null;
    _isGenerating = false;

    final targetModelPath = _settings.modelPath;
    final targetMmprojPath = _settings.mmprojPath;
    final requiresLoad =
        targetModelPath != null &&
        targetModelPath.isNotEmpty &&
        (!_isLoaded ||
            _loadedModelPath != targetModelPath ||
            (_loadedMmprojPath ?? '') != (targetMmprojPath ?? ''));

    if (requiresLoad) {
      await loadModel();
      return;
    }

    if (targetModelPath == null || targetModelPath.isEmpty) {
      _session = null;
      _isLoaded = false;
      notifyListeners();
      return;
    }

    _isLoaded = _chatService.engine.isReady;
    _restoreSessionFromMessages();
    notifyListeners();
  }

  Future<void> deleteConversation(String conversationId) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index < 0) {
      return;
    }

    final wasActive = _activeConversationId == conversationId;
    _conversations.removeAt(index);

    if (_conversations.isEmpty) {
      createConversation();
      return;
    }

    if (!wasActive) {
      notifyListeners();
      return;
    }

    await switchConversation(_conversations.first.id);
  }

  void _rebuildDeclaredToolsFromSettings() {
    final raw = _toolDeclarationService.normalizeDeclarations(
      _settings.toolDeclarations,
    );
    try {
      _declaredTools = _toolDeclarationService.parseDefinitions(
        raw,
        handler: _declarationOnlyToolHandler,
      );
      _toolDeclarationsError = null;
    } catch (error) {
      _declaredTools = const <ToolDefinition>[];
      _toolDeclarationsError = _toolDeclarationService.formatError(
        error,
        fallback: 'Tool declarations are invalid.',
      );
    }
  }

  static Future<Object?> _declarationOnlyToolHandler(ToolParams _) async {
    return 'Tool execution is disabled in this chat app.';
  }

  Future<void> _init() async {
    _settings = await _settingsService.loadSettings();
    _rebuildDeclaredToolsFromSettings();
    final index = _conversationStateService.activeConversationIndex(
      conversations: _conversations,
      activeConversationId: _activeConversationId,
    );
    if (index >= 0) {
      _conversations[index] = _conversations[index].copyWith(
        settings: _settings,
      );
    }

    String? backendInfo;
    try {
      backendInfo = await _chatService.engine.getBackendName();
    } catch (e) {
      debugPrint("Error fetching devices: $e");
    }

    await _resolveAutoPreferredBackend(backendInfo: backendInfo);

    if (backendInfo != null) {
      _availableDevices = BackendUtils.parseBackendDevices(backendInfo);
      _activeBackend = BackendUtils.deriveActiveBackendLabel(
        backendInfo,
        preferredBackend: _settings.preferredBackend,
        gpuLayers: _settings.gpuLayers,
      );
    } else {
      _activeBackend = _settings.preferredBackend == GpuBackend.cpu
          ? 'CPU'
          : _settings.preferredBackend.name.toUpperCase();
    }
    _syncActiveConversationSnapshot(touchUpdatedAt: false);
    notifyListeners();
  }

  Future<void> loadModel() async {
    if (_isInitializing) return;
    if (_settings.modelPath == null || _settings.modelPath!.isEmpty) {
      _error = 'Model path not set. Please configure in settings.';
      _syncActiveConversationSnapshot(touchUpdatedAt: false);
      notifyListeners();
      return;
    }

    _isInitializing = true;
    _isLoaded = false;
    _error = null;
    _loadingProgress = 0.0;
    _activeBackend = 'Loading model...';
    notifyListeners();

    void setProgress(double value) {
      final clamped = value.clamp(0.0, 1.0);
      if (clamped <= _loadingProgress) {
        return;
      }
      _loadingProgress = clamped;
      notifyListeners();
    }

    setProgress(0.04);

    // Estimate dynamic settings if we have a model path but no custom settings yet
    // or if we're reloading and want to be safe.
    if (_settings.gpuLayers == 32 || _settings.gpuLayers == 99) {
      try {
        await estimateDynamicSettings();
      } catch (e) {
        debugPrint("Dynamic estimation failed: $e");
      }
    }

    setProgress(0.1);

    try {
      await _resolveAutoPreferredBackend();
      await _chatService.engine.setDartLogLevel(_settings.logLevel);
      await _chatService.engine.setNativeLogLevel(_settings.nativeLogLevel);
      setProgress(0.14);
      await _chatService.init(
        _settings,
        onProgress: (progress) {
          final normalized = progress.clamp(0.0, 1.0);
          final staged = 0.14 + (normalized * 0.7);
          if (staged > _loadingProgress) {
            _loadingProgress = staged;
          }
          _activeBackend =
              'Loading model ${(normalized * 100).toStringAsFixed(0)}%';
          notifyListeners();
        },
      );

      setProgress(0.72);

      if (!_chatService.engine.isReady) {
        throw Exception('Engine initialization did not complete.');
      }

      _session = _chatSessionService.createSession(
        engine: _chatService.engine,
        contextSize: _settings.contextSize,
        systemPrompt: _sessionSystemPrompt(),
      );
      setProgress(0.8);

      final rawBackend = await _chatService.engine.getBackendName();
      _availableDevices = BackendUtils.parseBackendDevices(rawBackend);
      _activeBackend = BackendUtils.deriveActiveBackendLabel(
        rawBackend,
        preferredBackend: _settings.preferredBackend,
        gpuLayers: _settings.gpuLayers,
      );

      _contextLimit = await _chatService.engine.getContextSize();
      _supportsVision = await _chatService.engine.supportsVision;
      _supportsAudio = await _chatService.engine.supportsAudio;
      final metadata = await _chatService.engine.getMetadata();
      _updateToolTemplateSupport(metadata);
      setProgress(0.9);

      final runtimeDiagnostics = _runtimeProfileService.buildDiagnostics(
        metadata: metadata,
      );
      _runtimeGpuLayers = runtimeDiagnostics.runtimeGpuLayers;
      _runtimeThreads = runtimeDiagnostics.runtimeThreads;

      _addInfoMessage('Model loaded successfully! Ready to chat.');
      _isLoaded = true;
      _loadedModelPath = _settings.modelPath;
      _loadedMmprojPath = _settings.mmprojPath;
      _restoreSessionFromMessages();
      _syncActiveConversationSnapshot(touchUpdatedAt: false);
      setProgress(1.0);
    } catch (e, stackTrace) {
      debugPrint('Error loading model: $e');
      debugPrint(stackTrace.toString());
      _error = e.toString();
      _loadedModelPath = null;
      _loadedMmprojPath = null;
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
    _lastTokensPerSecond = null;
    _messages.add(
      ChatMessage(
        text: 'Conversation cleared. Ready for a new topic!',
        isUser: false,
        isInfo: true,
      ),
    );
    _syncActiveConversationSnapshot();
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (_isGenerating || _session == null) return;

    if (_settings.singleTurnMode) {
      _session!.reset();
    }

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
    _syncActiveConversationSnapshot();
    notifyListeners();

    await _yieldUiFrame();

    await _generateResponse(text, parts: parts.isEmpty ? null : parts);
  }

  Map<String, dynamic>? _thinkingTemplateKwargs() {
    if (_settings.thinkingEnabled && _settings.thinkingBudgetTokens <= 0) {
      return null;
    }

    final kwargs = <String, dynamic>{
      'enable_thinking': _settings.thinkingEnabled,
      'thinking': _settings.thinkingEnabled,
      'reasoning': _settings.thinkingEnabled,
    };

    if (_settings.thinkingBudgetTokens > 0) {
      kwargs['thinking_budget'] = _settings.thinkingBudgetTokens;
      kwargs['reasoning_budget'] = _settings.thinkingBudgetTokens;
      kwargs['max_thinking_tokens'] = _settings.thinkingBudgetTokens;
    }

    return kwargs;
  }

  String? _sessionSystemPrompt() {
    if (!_settings.toolsEnabled) {
      return null;
    }

    return 'When function declarations are available, call tools only when '
        'they are needed. If no tool is needed, answer directly.';
  }

  List<ToolDefinition>? _toolsForTurn() {
    if (!_settings.toolsEnabled || !_templateSupportsTools) {
      return null;
    }
    if (_declaredTools.isEmpty) {
      return null;
    }
    return _declaredTools;
  }

  Future<void> _yieldUiFrame() async {
    await Future<void>.delayed(Duration.zero);
    if (kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _generateResponse(
    String text, {
    List<LlamaContentPart>? parts,
  }) async {
    var generationResult = const GenerationStreamResult(
      fullResponse: '',
      fullThinking: '',
      generatedTokens: 0,
      firstTokenLatencyMs: null,
      elapsedMs: 0,
    );
    _lastFirstTokenLatencyMs = null;
    final toolsForTurn = _toolsForTurn();

    try {
      _messages.add(ChatMessage(text: "...", isUser: false));
      notifyListeners();

      await _yieldUiFrame();

      final params = _chatGenerationService.buildParams(_settings);
      final chatParts = _chatGenerationService.buildChatParts(
        text: text,
        stagedParts: parts,
      );

      final templateKwargs = _thinkingTemplateKwargs();
      _session!.systemPrompt = _sessionSystemPrompt();

      generationResult = await _chatGenerationService.consumeStream(
        stream: _session!.create(
          chatParts,
          params: params,
          tools: toolsForTurn,
          toolChoice: toolsForTurn != null ? ToolChoice.auto : null,
          enableThinking: _settings.thinkingEnabled,
          chatTemplateKwargs: templateKwargs,
        ),
        thinkingEnabled: _settings.thinkingEnabled,
        uiNotifyIntervalMs: kIsWeb ? 120 : 50,
        cleanResponse: _chatService.cleanResponse,
        shouldContinue: () => _isGenerating,
        onUpdate: (update) {
          _currentTokens++;
          _updateStreamingAssistantMessage(
            cleanText: update.cleanText,
            fullThinking: update.fullThinking,
          );
          if (update.shouldNotify) {
            notifyListeners();
          }
        },
      );

      final fullResponse = generationResult.fullResponse;
      final fullThinking = generationResult.fullThinking;
      _lastFirstTokenLatencyMs = generationResult.firstTokenLatencyMs;

      // Final update
      if (_messages.isNotEmpty && !_messages.last.isUser) {
        final lastSessionMessage = _session!.history.isNotEmpty
            ? _session!.history.last
            : null;
        var toolCalls = lastSessionMessage == null
            ? const <LlamaToolCallContent>[]
            : lastSessionMessage.parts.whereType<LlamaToolCallContent>().toList(
                growable: false,
              );
        if (toolCalls.isEmpty) {
          toolCalls = _assistantOutputService.parseToolCallsForDisplay(
            streamedContent: fullResponse,
            detectedChatFormat: _detectedChatFormat,
          );
        }

        final hadRawThinkingTags = _assistantOutputService.containsReasoningTag(
          fullResponse,
        );
        final hadThinkingStream = fullThinking.trim().isNotEmpty;
        final normalized = _assistantOutputService.normalizeAssistantOutput(
          streamedContent: fullResponse,
          streamedThinking: fullThinking,
          toolsEnabled: _settings.toolsEnabled,
          detectedChatFormat: _detectedChatFormat,
          cleanResponse: _chatService.cleanResponse,
        );
        var finalText = normalized.text;
        var finalThinking = normalized.thinking;
        if (!_settings.thinkingEnabled) {
          finalThinking = '';
        }

        final debugBadges = kDebugMode
            ? _assistantOutputService.buildAssistantDebugBadges(
                detectedChatFormat: _detectedChatFormat,
                hadRawThinkingTags: hadRawThinkingTags,
                hadThinkingStream: hadThinkingStream,
                finalThinking: finalThinking,
                finalText: finalText,
              )
            : <String>[];

        if (_messages.isNotEmpty && !_messages.last.isUser) {
          final messageParts = <LlamaContentPart>[];
          if (finalThinking.isNotEmpty) {
            messageParts.add(LlamaThinkingContent(finalThinking));
          }
          if (toolCalls.isNotEmpty) {
            messageParts.addAll(toolCalls);
            if (finalText.isEmpty) {
              finalText = toolCalls.map((call) => call.rawJson).join('\n');
            }
          } else if (finalText.isNotEmpty) {
            messageParts.add(LlamaTextContent(finalText));
          }

          _messages[_messages.length - 1] = _messages.last.copyWith(
            text: finalText,
            parts: messageParts,
            debugBadges: debugBadges,
          );
          _messages.last.tokenCount = await _chatService.engine.getTokenCount(
            finalText,
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
      final generatedTokens = generationResult.generatedTokens;
      final elapsedMs = generationResult.elapsedMs;
      if (generatedTokens > 0 && elapsedMs > 0) {
        _lastTokensPerSecond = generatedTokens / (elapsedMs / 1000);
      } else {
        _lastTokensPerSecond = null;
      }

      if (generationResult.firstTokenLatencyMs != null ||
          generationResult.fullResponse.isNotEmpty ||
          generationResult.fullThinking.isNotEmpty) {
        _lastGenerationLatencyMs = elapsedMs;
      }
      _isGenerating = false;
      _syncActiveConversationSnapshot();
      notifyListeners();
    }
  }

  void _updateStreamingAssistantMessage({
    required String cleanText,
    required String fullThinking,
  }) {
    if (_messages.isEmpty || _messages.last.isUser) {
      return;
    }

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
  }

  void _addInfoMessage(String text) {
    final last = _messages.isNotEmpty ? _messages.last : null;
    if (last != null && last.isInfo && last.text == text) {
      return;
    }

    _messages.add(ChatMessage(text: text, isUser: false, isInfo: true));
    _syncActiveConversationSnapshot();
  }

  void _addStagedPart(LlamaContentPart part) {
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
    await _pickMediaPart(
      type: FileType.image,
      fromPath: (path) => LlamaImageContent(path: path),
      fromBytes: (bytes) => LlamaImageContent(bytes: bytes),
      browserReadError:
          'Could not read image bytes in browser. Try a different image file.',
      fileReadError: 'Could not read selected image file.',
      debugLabel: 'image',
    );
  }

  Future<void> pickAudio() async {
    await _pickMediaPart(
      type: FileType.audio,
      fromPath: (path) => LlamaAudioContent(path: path),
      fromBytes: (bytes) => LlamaAudioContent(bytes: bytes),
      browserReadError:
          'Could not read audio bytes in browser. Try a different audio file.',
      fileReadError: 'Could not read selected audio file.',
      debugLabel: 'audio',
    );
  }

  Future<void> _pickMediaPart({
    required FileType type,
    required LlamaContentPart Function(String path) fromPath,
    required LlamaContentPart Function(Uint8List bytes) fromBytes,
    required String browserReadError,
    required String fileReadError,
    required String debugLabel,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type,
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes != null && bytes.isNotEmpty) {
          _addStagedPart(fromBytes(bytes));
          return;
        }

        _addInfoMessage(browserReadError);
        notifyListeners();
        return;
      }

      final path = file.path;
      if (path != null && path.isNotEmpty) {
        _addStagedPart(fromPath(path));
        return;
      }

      final bytes = file.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        _addStagedPart(fromBytes(bytes));
        return;
      }

      _addInfoMessage(fileReadError);
      notifyListeners();
    } catch (error) {
      debugPrint('Error picking $debugLabel: $error');
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
    _rebuildDeclaredToolsFromSettings();
    _settingsService.saveSettings(_settings);
    _syncActiveConversationSnapshot(touchUpdatedAt: false);
    notifyListeners();
  }

  void updateTemperature(double value) =>
      _updateSettings(_settings.copyWith(temperature: value));
  void updateTopK(int value) =>
      _updateSettings(_settings.copyWith(topK: value));
  void updateTopP(double value) =>
      _updateSettings(_settings.copyWith(topP: value));
  void updateMinP(double value) =>
      _updateSettings(_settings.copyWith(minP: value.clamp(0.0, 1.0)));
  void updatePenalty(double value) =>
      _updateSettings(_settings.copyWith(penalty: value.clamp(0.8, 2.0)));
  void updateContextSize(int value) {
    final effectiveContextSize = value == 0 ? 0 : value.clamp(512, 32768);
    _updateSettings(_settings.copyWith(contextSize: effectiveContextSize));
  }

  void updateMaxTokens(int value) =>
      _updateSettings(_settings.copyWith(maxTokens: value.clamp(512, 32768)));
  void updateGpuLayers(int value) {
    final normalized = value >= 99 ? 99 : value.clamp(0, 98);
    _updateSettings(_settings.copyWith(gpuLayers: normalized));
  }

  void updateNumberOfThreads(int value) =>
      _updateSettings(_settings.copyWith(numberOfThreads: value.clamp(0, 64)));
  void updateNumberOfThreadsBatch(int value) => _updateSettings(
    _settings.copyWith(numberOfThreadsBatch: value.clamp(0, 128)),
  );
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

  bool updateToolDeclarations(String declarationsJson) {
    final normalized = _toolDeclarationService.normalizeDeclarations(
      declarationsJson,
    );
    try {
      final parsed = _toolDeclarationService.parseDefinitions(
        normalized,
        handler: _declarationOnlyToolHandler,
      );
      _declaredTools = parsed;
      _toolDeclarationsError = null;
      _updateSettings(_settings.copyWith(toolDeclarations: normalized));
      return true;
    } catch (error) {
      _toolDeclarationsError = _toolDeclarationService.formatError(
        error,
        fallback: 'Tool declarations are invalid.',
      );
      notifyListeners();
      return false;
    }
  }

  void resetToolDeclarations() {
    updateToolDeclarations(_defaultToolDeclarationsJson);
  }

  void updateThinkingEnabled(bool value) {
    _updateSettings(_settings.copyWith(thinkingEnabled: value));
  }

  void updateThinkingBudgetTokens(int value) {
    _updateSettings(
      _settings.copyWith(thinkingBudgetTokens: value.clamp(0, 8192)),
    );
  }

  void updateSingleTurnMode(bool value) {
    _updateSettings(_settings.copyWith(singleTurnMode: value));
  }

  Future<void> unloadModel() async {
    stopGeneration();
    _session?.reset();
    _session = null;
    await _chatService.unloadModel();

    _isInitializing = false;
    _loadingProgress = 0.0;
    _isLoaded = false;
    _error = null;
    _activeBackend = 'Unloaded';
    _contextLimit = 0;
    _loadedModelPath = null;
    _loadedMmprojPath = null;
    _syncActiveConversationSnapshot(touchUpdatedAt: false);
    notifyListeners();
  }

  void updateModelPath(String path) {
    _updateSettings(_settings.copyWith(modelPath: path));
  }

  /// Apply model-specific recommended generation and runtime parameters.
  void applyModelPreset(DownloadableModel model) {
    final shouldKeepToolsEnabled =
        model.supportsToolCalling && _settings.toolsEnabled;

    _updateSettings(
      _settings.copyWith(
        temperature: model.preset.temperature,
        topK: model.preset.topK,
        topP: model.preset.topP,
        minP: model.preset.minP,
        penalty: model.preset.penalty,
        contextSize: model.preset.contextSize,
        maxTokens: model.preset.maxTokens,
        gpuLayers: model.preset.gpuLayers,
        toolsEnabled: shouldKeepToolsEnabled,
        thinkingEnabled: model.preset.thinkingEnabled,
        thinkingBudgetTokens: model.preset.thinkingBudgetTokens,
        singleTurnMode: false,
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
        hasDedicatedToolTemplate || format != ChatFormat.contentOnly;

    if (_settings.toolsEnabled && !_templateSupportsTools) {
      _settings = _settings.copyWith(toolsEnabled: false);
      _settingsService.saveSettings(_settings);
      _messages.add(
        ChatMessage(
          text:
              'Tool calling disabled for this model: template is content-only.',
          isUser: false,
          isInfo: true,
        ),
      );
      _syncActiveConversationSnapshot();
    }
  }

  Future<void> _resolveAutoPreferredBackend({String? backendInfo}) async {
    if (_settings.preferredBackend != GpuBackend.auto) {
      return;
    }

    if (kIsWeb) {
      // Keep Auto on web: the bridge backend interprets non-CPU as WebGPU.
      return;
    }

    final info = backendInfo ?? await _getBackendInfoBestEffort();
    final resolved = info == null
        ? GpuBackend.cpu
        : BackendUtils.selectBestBackendFromInfo(info);

    _settings = _settings.copyWith(preferredBackend: resolved);
    await _settingsService.saveSettings(_settings);
    _syncActiveConversationSnapshot(touchUpdatedAt: false);
  }

  Future<String?> _getBackendInfoBestEffort() async {
    try {
      return await _chatService.engine.getBackendName();
    } catch (_) {
      return null;
    }
  }

  void updateMmprojPath(String path) {
    _updateSettings(_settings.copyWith(mmprojPath: path));
  }

  Future<void> updatePreferredBackend(GpuBackend backend) {
    _updateSettings(_settings.copyWith(preferredBackend: backend));
    _messages.add(
      ChatMessage(
        text:
            'Backend preference set to ${backend.name}. Reload model to apply.',
        isUser: false,
        isInfo: true,
      ),
    );
    _syncActiveConversationSnapshot();
    notifyListeners();
    return Future<void>.value();
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
      _loadedModelPath = null;
      _loadedMmprojPath = null;
      await _chatService.dispose();
    } finally {
      _isShuttingDown = false;
    }
  }

  Future<void> estimateDynamicSettings() async {
    try {
      final vram = await _chatService.engine.getVramInfo();
      final backendInfo = await _getBackendInfoBestEffort();
      final estimate = _runtimeProfileService.estimateDynamicSettings(
        totalVramBytes: vram.total,
        freeVramBytes: vram.free,
        isWeb: kIsWeb,
        preferredBackend: _settings.preferredBackend,
        currentContextSize: _settings.contextSize,
        backendInfo: backendInfo,
      );

      _updateSettings(
        _settings.copyWith(
          gpuLayers: estimate.gpuLayers,
          contextSize: estimate.contextSize,
        ),
      );
    } catch (e) {
      debugPrint("Error estimating dynamic settings: $e");
    }
  }
}
