Map<String, dynamic> buildSystemPaths() {
  return <String, dynamic>{
    '/healthz': <String, dynamic>{
      'get': <String, dynamic>{
        'tags': <String>['System'],
        'summary': 'Health check',
        'operationId': 'getHealth',
        'responses': <String, dynamic>{
          '200': <String, dynamic>{
            'description': 'Server health',
            'content': <String, dynamic>{
              'application/json': <String, dynamic>{
                'schema': <String, dynamic>{
                  r'$ref': '#/components/schemas/HealthResponse',
                },
              },
            },
          },
        },
      },
    },
  };
}
