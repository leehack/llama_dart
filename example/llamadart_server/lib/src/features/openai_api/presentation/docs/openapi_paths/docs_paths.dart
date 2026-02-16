Map<String, dynamic> buildDocsPaths() {
  return <String, dynamic>{
    '/openapi.json': <String, dynamic>{
      'get': <String, dynamic>{
        'tags': <String>['Docs'],
        'summary': 'Get OpenAPI specification',
        'operationId': 'getOpenApiSpec',
        'responses': <String, dynamic>{
          '200': <String, dynamic>{
            'description': 'OpenAPI document',
            'content': <String, dynamic>{
              'application/json': <String, dynamic>{
                'schema': <String, dynamic>{'type': 'object'},
              },
            },
          },
        },
      },
    },
    '/docs': <String, dynamic>{
      'get': <String, dynamic>{
        'tags': <String>['Docs'],
        'summary': 'Swagger UI page',
        'operationId': 'getSwaggerUi',
        'responses': <String, dynamic>{
          '200': <String, dynamic>{
            'description': 'Swagger UI HTML',
            'content': <String, dynamic>{
              'text/html': <String, dynamic>{
                'schema': <String, dynamic>{'type': 'string'},
              },
            },
          },
        },
      },
    },
  };
}
