import 'path_security.dart';

Map<String, dynamic> buildModelPaths({required bool apiKeyEnabled}) {
  return <String, dynamic>{
    '/v1/models': <String, dynamic>{
      'get': <String, dynamic>{
        'tags': <String>['Models'],
        'summary': 'List available models',
        'operationId': 'listModels',
        'security': operationSecurity(apiKeyEnabled),
        'responses': <String, dynamic>{
          '200': <String, dynamic>{
            'description': 'Model list',
            'content': <String, dynamic>{
              'application/json': <String, dynamic>{
                'schema': <String, dynamic>{
                  r'$ref': '#/components/schemas/ModelListResponse',
                },
              },
            },
          },
          '401': <String, dynamic>{
            r'$ref': '#/components/responses/UnauthorizedError',
          },
        },
      },
    },
  };
}
