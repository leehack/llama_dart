import 'openapi_paths/chat_paths.dart';
import 'openapi_paths/docs_paths.dart';
import 'openapi_paths/model_paths.dart';
import 'openapi_paths/system_paths.dart';

Map<String, dynamic> buildOpenApiPaths({required bool apiKeyEnabled}) {
  return <String, dynamic>{
    ...buildSystemPaths(),
    ...buildModelPaths(apiKeyEnabled: apiKeyEnabled),
    ...buildChatPaths(apiKeyEnabled: apiKeyEnabled),
    ...buildDocsPaths(),
  };
}
