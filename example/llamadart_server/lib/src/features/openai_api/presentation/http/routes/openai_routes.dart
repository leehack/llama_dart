import 'package:relic/relic.dart';

import '../handlers/chat_completions_handler.dart';
import '../handlers/system_handlers.dart';

/// Registers all OpenAI-compatible routes on the provided app.
void registerOpenAiRoutes(
  RelicApp app, {
  required OpenAiSystemHandlers systemHandlers,
  required ChatCompletionsHandler chatCompletionsHandler,
}) {
  app
    ..get('/healthz', systemHandlers.handleHealth)
    ..get('/openapi.json', systemHandlers.handleOpenApi)
    ..get('/docs', systemHandlers.handleDocsPage)
    ..get('/v1/models', systemHandlers.handleModels)
    ..post('/v1/chat/completions', chatCompletionsHandler.handle)
    ..fallback = systemHandlers.handleFallback;
}
