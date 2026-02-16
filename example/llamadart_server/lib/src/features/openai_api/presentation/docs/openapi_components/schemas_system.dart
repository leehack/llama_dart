Map<String, dynamic> buildSystemSchemas({required String modelId}) {
  return <String, dynamic>{
    'HealthResponse': <String, dynamic>{
      'type': 'object',
      'required': <String>['status', 'ready', 'model', 'busy'],
      'properties': <String, dynamic>{
        'status': <String, dynamic>{'type': 'string', 'example': 'ok'},
        'ready': <String, dynamic>{'type': 'boolean', 'example': true},
        'model': <String, dynamic>{'type': 'string', 'example': modelId},
        'busy': <String, dynamic>{'type': 'boolean', 'example': false},
      },
    },
    'Model': <String, dynamic>{
      'type': 'object',
      'required': <String>['id', 'object', 'created', 'owned_by'],
      'properties': <String, dynamic>{
        'id': <String, dynamic>{'type': 'string', 'example': modelId},
        'object': <String, dynamic>{'type': 'string', 'example': 'model'},
        'created': <String, dynamic>{'type': 'integer'},
        'owned_by': <String, dynamic>{'type': 'string', 'example': 'llamadart'},
      },
    },
    'ModelListResponse': <String, dynamic>{
      'type': 'object',
      'required': <String>['object', 'data'],
      'properties': <String, dynamic>{
        'object': <String, dynamic>{'type': 'string', 'example': 'list'},
        'data': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{r'$ref': '#/components/schemas/Model'},
        },
      },
    },
  };
}
