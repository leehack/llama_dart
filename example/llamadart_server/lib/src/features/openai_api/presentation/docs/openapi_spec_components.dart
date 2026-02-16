import 'openapi_components/responses.dart';
import 'openapi_components/schemas_chat.dart';
import 'openapi_components/schemas_error.dart';
import 'openapi_components/schemas_system.dart';
import 'openapi_components/security_schemes.dart';

Map<String, dynamic> buildOpenApiComponents({required String modelId}) {
  return <String, dynamic>{
    'securitySchemes': buildOpenApiSecuritySchemes(),
    'responses': buildOpenApiResponses(),
    'schemas': <String, dynamic>{
      ...buildSystemSchemas(modelId: modelId),
      ...buildChatSchemas(modelId: modelId),
      ...buildErrorSchemas(),
    },
  };
}
