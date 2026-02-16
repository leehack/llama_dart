import 'package:llamadart/llamadart.dart';

import '../../server_engine/domain/chat_completion_engine_port.dart';
import '../../shared/openai_http_exception.dart';
import '../domain/openai_chat_completion_request.dart';
import 'openai_response_mapper.dart';
import 'services/support/completion_round_runner.dart';
import 'services/support/tool_execution_transcript.dart';

/// Use case service for chat completion generation.
class ChatCompletionService {
  /// Engine used for template + completion generation.
  final ChatCompletionEnginePort engine;

  /// Optional server-side tool invoker.
  final OpenAiToolInvoker? toolInvoker;

  /// Maximum server-side tool-call rounds per request.
  final int maxToolRounds;

  /// Creates a chat completion use case service.
  ChatCompletionService({
    required this.engine,
    this.toolInvoker,
    this.maxToolRounds = 5,
  }) : _roundRunner = CompletionRoundRunner(engine);

  final CompletionRoundRunner _roundRunner;

  /// Generates a non-streaming OpenAI-compatible response body.
  Future<Map<String, dynamic>> generate(
    OpenAiChatCompletionRequest request, {
    required String modelId,
  }) async {
    final conversation = List<LlamaChatMessage>.from(request.messages);
    final tools = request.tools;

    var roundToolChoice = request.toolChoice;
    var totalPromptTokens = 0;
    var totalCompletionTokens = 0;

    CompletionRoundResult? finalRound;
    final maxRounds = maxToolRounds < 1 ? 1 : maxToolRounds;

    for (var round = 0; round < maxRounds; round++) {
      final currentRound = await _roundRunner.run(
        messages: conversation,
        params: request.params,
        tools: tools,
        toolChoice: roundToolChoice,
      );

      finalRound = currentRound;
      totalPromptTokens += currentRound.promptTokens;
      totalCompletionTokens += currentRound.completionTokens;

      final emittedToolCalls = currentRound.accumulator.toolCalls;
      final canExecuteTools =
          toolInvoker != null && tools != null && tools.isNotEmpty;
      final hasToolCalls = emittedToolCalls.isNotEmpty;
      final hasRemainingRounds = round + 1 < maxRounds;

      if (!(canExecuteTools && hasToolCalls && hasRemainingRounds)) {
        break;
      }

      await appendToolExecutionMessages(
        conversation: conversation,
        tools: tools,
        toolCalls: emittedToolCalls,
      );

      roundToolChoice = ToolChoice.auto;
    }

    final round = finalRound;
    if (round == null) {
      throw OpenAiHttpException.server('No completion output generated.');
    }

    return round.accumulator.toResponseJson(
      id: round.completionId,
      created: round.created,
      model: modelId,
      promptTokens: totalPromptTokens,
      completionTokens: totalCompletionTokens,
    );
  }

  /// Generates streaming OpenAI-compatible chunk payloads.
  Stream<Map<String, dynamic>> stream(
    OpenAiChatCompletionRequest request, {
    required String modelId,
  }) async* {
    var emittedRole = false;

    await for (final chunk in engine.create(
      request.messages,
      params: request.params,
      tools: request.tools,
      toolChoice: request.toolChoice,
    )) {
      final payload = toOpenAiChatCompletionChunk(
        chunk,
        model: modelId,
        includeRole: !emittedRole,
      );
      emittedRole = true;
      yield payload;
    }
  }
}
