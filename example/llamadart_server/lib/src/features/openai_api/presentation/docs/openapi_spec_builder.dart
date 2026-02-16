import 'openapi_spec_components.dart';
import 'openapi_spec_paths.dart';

const _openApiTags = <Map<String, String>>[
  <String, String>{'name': 'System'},
  <String, String>{'name': 'Models'},
  <String, String>{'name': 'Chat'},
  <String, String>{'name': 'Docs'},
];

/// Builds OpenAPI schema for the API server example.
Map<String, dynamic> buildOpenApiSpec({
  required String modelId,
  required bool apiKeyEnabled,
  required String serverUrl,
}) {
  return <String, dynamic>{
    'openapi': '3.1.0',
    'info': <String, dynamic>{
      'title': 'llamadart OpenAI-compatible API',
      'version': '1.0.0',
      'description':
          'Local OpenAI-compatible API powered by llamadart and Relic.',
    },
    'servers': <Map<String, dynamic>>[
      <String, dynamic>{'url': serverUrl, 'description': 'Current server URL'},
    ],
    'tags': _openApiTags,
    'paths': buildOpenApiPaths(apiKeyEnabled: apiKeyEnabled, modelId: modelId),
    'components': buildOpenApiComponents(modelId: modelId),
  };
}
