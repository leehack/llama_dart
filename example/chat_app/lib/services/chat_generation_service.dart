import 'package:llamadart/llamadart.dart';

import '../models/chat_settings.dart';

class GenerationStreamUpdate {
  final String cleanText;
  final String fullThinking;
  final bool shouldNotify;

  const GenerationStreamUpdate({
    required this.cleanText,
    required this.fullThinking,
    required this.shouldNotify,
  });
}

class GenerationStreamResult {
  final String fullResponse;
  final String fullThinking;
  final int generatedTokens;
  final int? firstTokenLatencyMs;
  final int elapsedMs;

  const GenerationStreamResult({
    required this.fullResponse,
    required this.fullThinking,
    required this.generatedTokens,
    required this.firstTokenLatencyMs,
    required this.elapsedMs,
  });
}

/// Handles streaming generation accumulation and timing metrics.
class ChatGenerationService {
  const ChatGenerationService();

  GenerationParams buildParams(ChatSettings settings) {
    return GenerationParams(
      maxTokens: settings.maxTokens,
      temp: settings.temperature,
      topK: settings.topK,
      topP: settings.topP,
      minP: settings.minP,
      penalty: settings.penalty,
      stopSequences: const <String>[],
    );
  }

  List<LlamaContentPart> buildChatParts({
    required String text,
    List<LlamaContentPart>? stagedParts,
  }) {
    return <LlamaContentPart>[
      ...?stagedParts,
      if (text.isNotEmpty) LlamaTextContent(text),
    ];
  }

  Future<GenerationStreamResult> consumeStream({
    required Stream<LlamaCompletionChunk> stream,
    required bool thinkingEnabled,
    required int uiNotifyIntervalMs,
    required String Function(String) cleanResponse,
    required bool Function() shouldContinue,
    required void Function(GenerationStreamUpdate update) onUpdate,
  }) async {
    final stopwatch = Stopwatch()..start();

    var fullResponse = '';
    var fullThinking = '';
    var generatedTokens = 0;
    var sawFirstToken = false;
    int? firstTokenLatencyMs;
    var lastUpdateAt = DateTime.now();

    await for (final chunk in stream) {
      if (!shouldContinue()) {
        break;
      }

      final delta = chunk.choices.first.delta;
      final content = delta.content ?? '';
      final thinking = thinkingEnabled ? (delta.thinking ?? '') : '';

      if (!sawFirstToken &&
          (content.isNotEmpty ||
              thinking.isNotEmpty ||
              (delta.toolCalls?.isNotEmpty ?? false))) {
        firstTokenLatencyMs = stopwatch.elapsedMilliseconds;
        sawFirstToken = true;
      }

      fullResponse += content;
      fullThinking += thinking.replaceAll(r'\n', '\n').replaceAll(r'\r', '\r');
      generatedTokens++;

      final now = DateTime.now();
      final shouldNotify =
          now.difference(lastUpdateAt).inMilliseconds > uiNotifyIntervalMs;
      if (shouldNotify) {
        lastUpdateAt = now;
      }

      onUpdate(
        GenerationStreamUpdate(
          cleanText: cleanResponse(fullResponse),
          fullThinking: fullThinking,
          shouldNotify: shouldNotify,
        ),
      );
    }

    stopwatch.stop();
    return GenerationStreamResult(
      fullResponse: fullResponse,
      fullThinking: fullThinking,
      generatedTokens: generatedTokens,
      firstTokenLatencyMs: firstTokenLatencyMs,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }
}
