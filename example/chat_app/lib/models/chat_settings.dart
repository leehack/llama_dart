import 'package:llamadart/llamadart.dart';

class ChatSettings {
  final String? modelPath;
  final String? mmprojPath;
  final GpuBackend preferredBackend;
  final double temperature;
  final int topK;
  final double topP;
  final int contextSize;
  final int maxTokens;
  final int gpuLayers;

  /// Dart-side logger verbosity (llamadart logger).
  final LlamaLogLevel logLevel;

  /// Native llama.cpp backend logger verbosity.
  final LlamaLogLevel nativeLogLevel;
  final bool toolsEnabled;
  final bool forceToolCall;

  const ChatSettings({
    this.modelPath,
    this.mmprojPath,
    this.preferredBackend = GpuBackend.auto,
    this.temperature = 0.7,
    this.topK = 40,
    this.topP = 0.9,
    this.contextSize = 4096,
    this.maxTokens = 4096,
    this.gpuLayers = 32,
    this.logLevel = LlamaLogLevel.none,
    this.nativeLogLevel = LlamaLogLevel.warn,
    this.toolsEnabled = true,
    this.forceToolCall = false,
  });

  ChatSettings copyWith({
    String? modelPath,
    String? mmprojPath,
    GpuBackend? preferredBackend,
    double? temperature,
    int? topK,
    double? topP,
    int? contextSize,
    int? maxTokens,
    int? gpuLayers,
    LlamaLogLevel? logLevel,
    LlamaLogLevel? nativeLogLevel,
    bool? toolsEnabled,
    bool? forceToolCall,
  }) {
    return ChatSettings(
      modelPath: modelPath ?? this.modelPath,
      mmprojPath: mmprojPath ?? this.mmprojPath,
      preferredBackend: preferredBackend ?? this.preferredBackend,
      temperature: temperature ?? this.temperature,
      topK: topK ?? this.topK,
      topP: topP ?? this.topP,
      contextSize: contextSize ?? this.contextSize,
      maxTokens: maxTokens ?? this.maxTokens,
      gpuLayers: gpuLayers ?? this.gpuLayers,
      logLevel: logLevel ?? this.logLevel,
      nativeLogLevel: nativeLogLevel ?? this.nativeLogLevel,
      toolsEnabled: toolsEnabled ?? this.toolsEnabled,
      forceToolCall: forceToolCall ?? this.forceToolCall,
    );
  }
}
