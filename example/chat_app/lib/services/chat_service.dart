import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import '../models/chat_message.dart';
import '../models/chat_settings.dart';

class ChatService {
  final LlamaEngine _engine;

  ChatService({LlamaEngine? engine})
    : _engine = engine ?? LlamaEngine(LlamaBackend());

  LlamaEngine get engine => _engine;

  // For backward compatibility with example code
  LlamaEngine get llama => _engine;

  Future<void> init(
    ChatSettings settings, {
    Function(double progress)? onProgress,
  }) async {
    if (settings.modelPath == null) throw Exception("Model path is null");

    if (settings.modelPath!.startsWith('http')) {
      await _engine.loadModelFromUrl(
        settings.modelPath!,
        modelParams: ModelParams(
          gpuLayers: 99,
          preferredBackend: settings.preferredBackend,
          contextSize: settings.contextSize,
          logLevel: settings.logLevel,
        ),
        onProgress: onProgress,
      );
    } else {
      await _engine.loadModel(
        settings.modelPath!,
        modelParams: ModelParams(
          gpuLayers: 99,
          preferredBackend: settings.preferredBackend,
          contextSize: settings.contextSize,
          logLevel: settings.logLevel,
        ),
      );
    }

    if (settings.mmprojPath != null && settings.mmprojPath!.isNotEmpty) {
      try {
        await _engine.loadMultimodalProjector(settings.mmprojPath!);
        debugPrint("Loaded multimodal projector from ${settings.mmprojPath}");
      } catch (e) {
        debugPrint("Warning: Failed to load multimodal projector: $e");
        // Do not rethrow; proceed without vision if projector fails
      }
    }
  }

  Future<LlamaChatTemplateResult> buildPrompt(
    List<ChatMessage> messages,
    int maxTokens, {
    int safetyMargin = 1024,
  }) async {
    final conversationMessages = messages
        .where(
          (m) =>
              m.text != 'Model loaded successfully! Ready to chat.' &&
              m.text != '...',
        )
        .toList();

    final List<LlamaChatMessage> finalMessages = [];
    int totalTokens = 0;

    for (int i = conversationMessages.length - 1; i >= 0; i--) {
      final m = conversationMessages[i];
      m.tokenCount ??= await _engine.getTokenCount(m.text);
      final tokens = m.tokenCount!;

      if (totalTokens + tokens > (maxTokens - safetyMargin)) {
        break;
      }

      totalTokens += tokens;

      if (m.parts != null && m.parts!.isNotEmpty) {
        finalMessages.insert(
          0,
          LlamaChatMessage.multimodal(
            role: m.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
            parts: m.parts!,
          ),
        );
      } else {
        finalMessages.insert(
          0,
          LlamaChatMessage.text(
            role: m.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
            content: m.text,
          ),
        );
      }
    }

    return await _engine.chatTemplate(finalMessages);
  }

  Stream<String> generate(
    List<LlamaChatMessage> messages,
    ChatSettings settings,
  ) {
    return _engine.chat(
      messages,
      params: GenerationParams(
        temp: settings.temperature,
        topK: settings.topK,
        topP: settings.topP,
        penalty: 1.1,
      ),
    );
  }

  String cleanResponse(String response) {
    return response.trim();
  }

  Future<void> dispose() async {
    await _engine.dispose();
  }

  void cancelGeneration() {
    _engine.cancelGeneration();
  }
}
