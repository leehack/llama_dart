import 'package:relic/relic.dart';

import '../../../../server_engine/server_engine.dart';
import '../../../../shared/shared.dart';
import '../../docs/docs.dart';
import '../mappers/model_list_response_mapper.dart';
import '../support/generation_gate.dart';
import '../support/http_json.dart';

/// Handles non-chat HTTP endpoints for the OpenAI-compatible server.
class OpenAiSystemHandlers {
  /// The initialized inference engine.
  final EngineReadinessPort engine;

  /// Public model ID exposed in API responses.
  final String modelId;

  /// Model creation timestamp used in model list responses.
  final int modelCreated;

  /// Whether API-key auth is enabled.
  final bool apiKeyEnabled;

  /// Prebuilt Swagger UI page.
  final String swaggerUiHtml;

  final GenerationGate _generationGate;

  /// Creates system endpoint handlers.
  OpenAiSystemHandlers({
    required this.engine,
    required this.modelId,
    required this.modelCreated,
    required this.apiKeyEnabled,
    required this.swaggerUiHtml,
    required GenerationGate generationGate,
  }) : _generationGate = generationGate;

  /// Handles `GET /healthz`.
  Response handleHealth(Request _) {
    return jsonResponse(<String, dynamic>{
      'status': 'ok',
      'ready': engine.isReady,
      'model': modelId,
      'busy': _generationGate.isGenerating,
    });
  }

  /// Handles `GET /openapi.json`.
  Response handleOpenApi(Request req) {
    return jsonResponse(
      buildOpenApiSpec(
        modelId: modelId,
        apiKeyEnabled: apiKeyEnabled,
        serverUrl: req.url.origin,
      ),
    );
  }

  /// Handles `GET /docs`.
  Response handleDocsPage(Request _) {
    return Response.ok(
      body: Body.fromString(swaggerUiHtml, mimeType: MimeType.html),
    );
  }

  /// Handles `GET /v1/models`.
  Response handleModels(Request _) {
    return jsonResponse(
      toOpenAiModelListResponse(modelId: modelId, created: modelCreated),
    );
  }

  /// Handles unknown routes.
  Response handleFallback(Request req) {
    final message = 'No route for `${req.method.name} /${req.url.path}`.';

    return errorJsonResponse(
      OpenAiHttpException(
        statusCode: 404,
        type: 'invalid_request_error',
        message: message,
        code: 'not_found',
      ),
    );
  }
}
