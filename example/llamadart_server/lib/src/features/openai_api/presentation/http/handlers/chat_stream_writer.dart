import 'dart:convert';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:relic/relic.dart';

import '../../../../chat_completion/chat_completion.dart';
import '../../../../shared/shared.dart';
import '../support/generation_gate.dart';
import '../support/openai_error_mapper.dart';
import '../support/sse_response.dart';

/// Writes streaming chat-completion responses as SSE payloads.
class ChatStreamWriter {
  /// Chat completion use case service.
  final ChatCompletionService chatCompletionService;

  /// Public model id exposed in streamed payloads.
  final String modelId;

  final GenerationGate _generationGate;

  /// Creates a stream writer.
  ChatStreamWriter({
    required this.chatCompletionService,
    required this.modelId,
    required GenerationGate generationGate,
  }) : _generationGate = generationGate;

  /// Builds an SSE response for one streaming request.
  Response create(OpenAiChatCompletionRequest request) {
    return sseResponse(_buildStream(request));
  }

  Stream<Uint8List> _buildStream(OpenAiChatCompletionRequest request) async* {
    try {
      await for (final payload in chatCompletionService.stream(
        request,
        modelId: modelId,
      )) {
        yield utf8.encode(encodeSseData(payload));
      }

      yield utf8.encode(encodeSseDone());
    } on OpenAiHttpException catch (error) {
      yield utf8.encode(encodeSseData(error.toResponseBody()));
      yield utf8.encode(encodeSseDone());
    } on LlamaException catch (error) {
      final payload = toServerError(
        error,
        'Model generation failed',
      ).toResponseBody();
      yield utf8.encode(encodeSseData(payload));
      yield utf8.encode(encodeSseDone());
    } catch (error) {
      final payload = toServerError(error, 'Server error').toResponseBody();
      yield utf8.encode(encodeSseData(payload));
      yield utf8.encode(encodeSseDone());
    } finally {
      _generationGate.release();
    }
  }
}
