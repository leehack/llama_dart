import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import 'package:file_picker/file_picker.dart';

import '../models/chat_message.dart';
import '../models/chat_settings.dart';
import '../services/chat_service.dart';
import '../services/settings_service.dart';

class ChatProvider extends ChangeNotifier {
  final ChatService _chatService;
  final SettingsService _settingsService;

  final List<ChatMessage> _messages = [];
  final List<LlamaContentPart> _stagedParts = [];
  ChatSettings _settings = const ChatSettings();

  String _activeBackend = "Unknown";
  bool _gpuSupported = false;
  bool _isInitializing = false;
  double _loadingProgress = 0.0;
  bool _isLoaded = false;
  bool _isGenerating = false;
  bool _supportsVision = false;
  bool _supportsAudio = false;
  String? _error;

  // Telemetry
  int _maxTokens = 2048;
  int _currentTokens = 0;
  bool _isPruning = false;

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
  String? get error => _error;
  double get temperature => _settings.temperature;
  int get topK => _settings.topK;
  double get topP => _settings.topP;
  int get contextSize => _settings.contextSize;
  int get maxTokens => _maxTokens;
  int get currentTokens => _currentTokens;
  bool get isPruning => _isPruning;
  List<String> get availableDevices => _availableDevices;

  bool get isReady => _error == null && !_isInitializing && _isLoaded;

  ChatProvider({
    ChatService? chatService,
    SettingsService? settingsService,
    ChatSettings? initialSettings,
  }) : _chatService = chatService ?? ChatService(),
       _settingsService = settingsService ?? SettingsService(),
       _settings = initialSettings ?? const ChatSettings() {
    if (chatService == null && settingsService == null) {
      _init();
    }
  }

  Future<void> _init() async {
    _settings = await _settingsService.loadSettings();
    try {
      _availableDevices = [await _chatService.engine.getBackendName()];
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

    try {
      await _chatService.engine.setLogLevel(_settings.logLevel);
      await _chatService.init(
        _settings,
        onProgress: (progress) {
          _loadingProgress = progress;
          _activeBackend =
              "Loading Model: ${(progress * 100).toStringAsFixed(0)}%";
          notifyListeners();
        },
      );

      final rawBackend = await _chatService.engine.getBackendName();
      _activeBackend = rawBackend;

      _maxTokens = await _chatService.engine.getContextSize();
      _supportsVision = await _chatService.engine.supportsVision;
      _supportsAudio = await _chatService.engine.supportsAudio;

      final libSupported = await _chatService.engine.isGpuSupported();

      _gpuSupported =
          libSupported ||
          _availableDevices.any(
            (d) =>
                !d.toLowerCase().contains("cpu") &&
                !d.toLowerCase().contains("llvm"),
          );

      _messages.add(
        ChatMessage(
          text: 'Model loaded successfully! Ready to chat.',
          isUser: false,
          isInfo: true,
        ),
      );
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
    if (_isGenerating) return;

    final parts = List<LlamaContentPart>.from(_stagedParts);
    if (text.isNotEmpty) {
      parts.add(LlamaTextContent(text));
    }

    if (parts.isEmpty) return;

    final userMsg = ChatMessage(text: text, isUser: true, parts: parts);
    _messages.add(userMsg);
    _stagedParts.clear();
    _isGenerating = true;
    notifyListeners();

    try {
      final responseMessageIndex = _messages.length;
      _messages.add(ChatMessage(text: "...", isUser: false));
      notifyListeners();

      String fullResponse = "";
      DateTime lastUpdate = DateTime.now();

      // For multimodal, we need the conversation history with parts
      final List<LlamaChatMessage> conversationMessages = [];
      for (final m in _messages) {
        if (m.isInfo || m.text == '...') continue;

        if (m.parts != null && m.parts!.isNotEmpty) {
          conversationMessages.add(
            LlamaChatMessage.multimodal(
              role: m.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
              parts: m.parts!,
            ),
          );
        } else {
          conversationMessages.add(
            LlamaChatMessage.text(
              role: m.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
              content: m.text,
            ),
          );
        }
      }

      await for (final token in _chatService.generate(
        conversationMessages,
        _settings,
      )) {
        if (!_isGenerating) {
          break;
        }
        fullResponse += token;

        final cleanText = _chatService.cleanResponse(fullResponse);

        if (_messages.length > responseMessageIndex) {
          _messages[responseMessageIndex] = _messages[responseMessageIndex]
              .copyWith(text: cleanText);

          // UI Throttling: only notify listeners if 50ms have passed since last update
          if (DateTime.now().difference(lastUpdate).inMilliseconds > 50) {
            notifyListeners();
            lastUpdate = DateTime.now();
          }
        }
      }

      // Final update to ensure UI is in sync and token counts are refreshed for next turn
      if (_messages.length > responseMessageIndex) {
        _messages[responseMessageIndex].tokenCount = await _chatService.engine
            .getTokenCount(_messages[responseMessageIndex].text);
      }
    } catch (e) {
      _messages.add(ChatMessage(text: 'Error: $e', isUser: false));
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
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
      );
      if (result != null && result.files.single.path != null) {
        addStagedPart(LlamaImageContent(path: result.files.single.path));
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  Future<void> pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        addStagedPart(LlamaAudioContent(path: result.files.single.path));
      }
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
  void updateContextSize(int value) =>
      _updateSettings(_settings.copyWith(contextSize: value));
  void updateLogLevel(LlamaLogLevel value) {
    _updateSettings(_settings.copyWith(logLevel: value));
    _chatService.engine.setLogLevel(value);
  }

  void updateModelPath(String path) {
    _settings = _settings.copyWith(modelPath: path);
    _settingsService.saveSettings(_settings);
    notifyListeners();
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
    _chatService.dispose();
    super.dispose();
  }

  Future<void> shutdown() async {
    await _chatService.dispose();
  }
}
