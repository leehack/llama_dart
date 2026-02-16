Map<String, dynamic> buildErrorSchemas() {
  return <String, dynamic>{
    'OpenAiError': <String, dynamic>{
      'type': 'object',
      'required': <String>['message', 'type', 'param', 'code'],
      'properties': <String, dynamic>{
        'message': <String, dynamic>{'type': 'string'},
        'type': <String, dynamic>{'type': 'string'},
        'param': <String, dynamic>{
          'oneOf': <dynamic>[
            <String, dynamic>{'type': 'string'},
            <String, dynamic>{'type': 'null'},
          ],
        },
        'code': <String, dynamic>{
          'oneOf': <dynamic>[
            <String, dynamic>{'type': 'string'},
            <String, dynamic>{'type': 'null'},
          ],
        },
      },
    },
    'ErrorResponse': <String, dynamic>{
      'type': 'object',
      'required': <String>['error'],
      'properties': <String, dynamic>{
        'error': <String, dynamic>{r'$ref': '#/components/schemas/OpenAiError'},
      },
    },
  };
}
