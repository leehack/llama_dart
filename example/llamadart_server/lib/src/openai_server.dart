import 'dart:convert';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:relic/relic.dart';

import 'server_engine.dart';
import 'middleware.dart';
import 'openai_error.dart';
import 'openai_mapper.dart';
import 'openapi_spec.dart';
import 'swagger_ui.dart';

/// OpenAI-compatible HTTP server wrapper for a single loaded model.
class OpenAiApiServer {
  /// The initialized inference engine.
  final ApiServerEngine engine;

  /// Public model ID exposed in API responses.
  final String modelId;

  /// Optional API key required for `/v1/*` endpoints.
  final String? apiKey;

  /// Optional server-side tool invoker.
  final OpenAiToolInvoker? toolInvoker;

  /// Maximum server-side tool-call rounds per request.
  final int maxToolRounds;

  /// Whether request logs should be emitted.
  final bool enableRequestLogs;

  /// Model creation timestamp used in model listing responses.
  final int modelCreated;

  bool _isGenerating = false;

  /// Creates a server wrapper around [engine].
  OpenAiApiServer({
    required this.engine,
    required this.modelId,
    this.apiKey,
    this.toolInvoker,
    this.maxToolRounds = 5,
    this.enableRequestLogs = false,
    int? modelCreated,
  }) : modelCreated =
           modelCreated ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Builds and configures a [RelicApp] instance.
  RelicApp buildApp() {
    final app = RelicApp();

    if (enableRequestLogs) {
      app.use('/', logRequests());
    }

    app
      ..use('/', createCorsMiddleware())
      ..use('/v1', createApiKeyMiddleware(apiKey))
      ..get('/healthz', _handleHealth)
      ..get('/openapi.json', _handleOpenApi)
      ..get('/docs', _handleDocsPage)
      ..get('/v1/models', _handleModels)
      ..post('/v1/chat/completions', _handleChatCompletions)
      ..fallback = _handleFallback;

    return app;
  }

  Response _handleHealth(Request _) {
    return _jsonResponse(<String, dynamic>{
      'status': 'ok',
      'ready': engine.isReady,
      'model': modelId,
      'busy': _isGenerating,
    });
  }

  Response _handleOpenApi(Request req) {
    return _jsonResponse(
      buildOpenApiSpec(
        modelId: modelId,
        apiKeyEnabled: apiKey != null && apiKey!.isNotEmpty,
        serverUrl: req.url.origin,
      ),
    );
  }

  Response _handleDocsPage(Request _) {
    return Response.ok(
      body: Body.fromString(
        buildSwaggerUiHtml(
          specUrl: '/openapi.json',
          title: 'llamadart OpenAI-compatible API Docs',
        ),
        mimeType: MimeType.html,
      ),
    );
  }

  Response _handleModels(Request _) {
    return _jsonResponse(
      toOpenAiModelListResponse(modelId: modelId, created: modelCreated),
    );
  }

  Future<Response> _handleChatCompletions(Request req) async {
    try {
      final rawBody = await req.readAsString();
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map) {
        throw OpenAiHttpException.invalidRequest(
          'Request body must be a JSON object.',
        );
      }

      final request = parseChatCompletionRequest(
        Map<String, dynamic>.from(decoded),
        configuredModelId: modelId,
        toolInvoker: toolInvoker,
      );

      if (_isGenerating) {
        throw OpenAiHttpException.busy(
          'Another generation is already in progress. Retry shortly.',
        );
      }

      if (request.stream) {
        _isGenerating = true;
        return _streamingResponse(request);
      }

      _isGenerating = true;
      return _nonStreamingResponse(request);
    } on FormatException {
      return _errorResponse(
        OpenAiHttpException.invalidRequest('Request body is not valid JSON.'),
      );
    } on OpenAiHttpException catch (error) {
      return _errorResponse(error);
    } catch (error) {
      return _errorResponse(
        OpenAiHttpException.server('Unexpected server error: $error'),
      );
    }
  }

  Future<Response> _nonStreamingResponse(
    OpenAiChatCompletionRequest request,
  ) async {
    try {
      final conversation = List<LlamaChatMessage>.from(request.messages);
      final tools = request.tools;

      var roundToolChoice = request.toolChoice;
      var totalPromptTokens = 0;
      var totalCompletionTokens = 0;

      _CompletionRoundResult? finalRound;
      final maxRounds = maxToolRounds < 1 ? 1 : maxToolRounds;

      for (var round = 0; round < maxRounds; round++) {
        final currentRound = await _runCompletionRound(
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

        await _appendToolExecutionMessages(
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

      final responseBody = round.accumulator.toResponseJson(
        id: round.completionId,
        created: round.created,
        model: modelId,
        promptTokens: totalPromptTokens,
        completionTokens: totalCompletionTokens,
      );

      return _jsonResponse(responseBody);
    } on OpenAiHttpException catch (error) {
      return _errorResponse(error);
    } on LlamaException catch (error) {
      return _errorResponse(
        OpenAiHttpException.server('Model generation failed: $error'),
      );
    } catch (error) {
      return _errorResponse(OpenAiHttpException.server('Server error: $error'));
    } finally {
      engine.cancelGeneration();
      _isGenerating = false;
    }
  }

  Future<_CompletionRoundResult> _runCompletionRound({
    required List<LlamaChatMessage> messages,
    required GenerationParams params,
    required List<ToolDefinition>? tools,
    required ToolChoice? toolChoice,
  }) async {
    var promptTokens = 0;
    try {
      final templateResult = await engine.chatTemplate(
        messages,
        tools: tools,
        toolChoice: toolChoice ?? ToolChoice.auto,
      );
      promptTokens = templateResult.tokenCount ?? 0;
    } catch (_) {
      promptTokens = 0;
    }

    final accumulator = OpenAiChatCompletionAccumulator();
    var completionId = 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}';
    var created = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await for (final chunk in engine.create(
      messages,
      params: params,
      tools: tools,
      toolChoice: toolChoice,
    )) {
      completionId = chunk.id;
      created = chunk.created;
      accumulator.addChunk(chunk);
    }

    final completionTokenText = _completionTokenText(accumulator);
    final completionTokens = completionTokenText.isEmpty
        ? 0
        : await engine.getTokenCount(completionTokenText);

    return _CompletionRoundResult(
      accumulator: accumulator,
      completionId: completionId,
      created: created,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );
  }

  String _completionTokenText(OpenAiChatCompletionAccumulator accumulator) {
    final parts = <String>[];
    final reasoning = accumulator.reasoningContent;
    if (reasoning.isNotEmpty) {
      parts.add(reasoning);
    }

    final content = accumulator.content;
    if (content.isNotEmpty) {
      parts.add(content);
    }

    return parts.join('\n');
  }

  Future<void> _appendToolExecutionMessages({
    required List<LlamaChatMessage> conversation,
    required List<ToolDefinition> tools,
    required List<OpenAiToolCallRecord> toolCalls,
  }) async {
    if (toolCalls.isEmpty) {
      return;
    }

    final assistantParts = toolCalls
        .map(
          (call) => LlamaToolCallContent(
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            rawJson: call.argumentsRaw,
          ),
        )
        .toList(growable: false);

    conversation.add(
      LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: assistantParts,
      ),
    );

    final toolsByName = {
      for (final definition in tools) definition.name: definition,
    };

    for (final call in toolCalls) {
      final definition = toolsByName[call.name];
      Object? result;

      if (definition == null) {
        result = {'ok': false, 'error': 'Tool `${call.name}` was not found.'};
      } else {
        try {
          result = await definition.invoke(call.arguments);
        } catch (error) {
          result = {
            'ok': false,
            'error': 'Tool `${call.name}` execution failed.',
            'details': '$error',
          };
        }
      }

      conversation.add(
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: <LlamaContentPart>[
            LlamaToolResultContent(
              id: call.id,
              name: call.name,
              result: result,
            ),
          ],
        ),
      );
    }
  }

  Response _streamingResponse(OpenAiChatCompletionRequest request) {
    final stream = _buildSseStream(request);

    return Response.ok(
      headers: Headers.build((MutableHeaders headers) {
        headers['Cache-Control'] = ['no-cache'];
        headers['Connection'] = ['keep-alive'];
        headers['X-Accel-Buffering'] = ['no'];
      }),
      body: Body.fromDataStream(
        stream,
        mimeType: MimeType.parse('text/event-stream'),
      ),
    );
  }

  Stream<Uint8List> _buildSseStream(
    OpenAiChatCompletionRequest request,
  ) async* {
    var emittedRole = false;

    try {
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

        yield utf8.encode(encodeSseData(payload));
      }

      yield utf8.encode(encodeSseDone());
    } on OpenAiHttpException catch (error) {
      yield utf8.encode(encodeSseData(error.toResponseBody()));
      yield utf8.encode(encodeSseDone());
    } on LlamaException catch (error) {
      final payload = OpenAiHttpException.server(
        'Model generation failed: $error',
      ).toResponseBody();
      yield utf8.encode(encodeSseData(payload));
      yield utf8.encode(encodeSseDone());
    } catch (error) {
      final payload = OpenAiHttpException.server(
        'Server error: $error',
      ).toResponseBody();
      yield utf8.encode(encodeSseData(payload));
      yield utf8.encode(encodeSseDone());
    } finally {
      engine.cancelGeneration();
      _isGenerating = false;
    }
  }

  Response _handleFallback(Request req) {
    final message = 'No route for `${req.method.name} /${req.url.path}`.';

    return _errorResponse(
      OpenAiHttpException(
        statusCode: 404,
        type: 'invalid_request_error',
        message: message,
        code: 'not_found',
      ),
    );
  }

  Response _errorResponse(OpenAiHttpException error) {
    return _jsonResponse(error.toResponseBody(), statusCode: error.statusCode);
  }

  Response _jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: Body.fromString(jsonEncode(body), mimeType: MimeType.json),
    );
  }
}

class _CompletionRoundResult {
  final OpenAiChatCompletionAccumulator accumulator;
  final String completionId;
  final int created;
  final int promptTokens;
  final int completionTokens;

  const _CompletionRoundResult({
    required this.accumulator,
    required this.completionId,
    required this.created,
    required this.promptTokens,
    required this.completionTokens,
  });
}
