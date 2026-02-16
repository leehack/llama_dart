Map<String, dynamic> buildOpenApiResponses() {
  return <String, dynamic>{
    'BadRequestError': _errorResponse('Bad request'),
    'UnauthorizedError': _errorResponse('Unauthorized'),
    'RateLimitError': _errorResponse('Busy'),
    'ServerError': _errorResponse('Server error'),
  };
}

Map<String, dynamic> _errorResponse(String description) {
  return <String, dynamic>{
    'description': description,
    'content': <String, dynamic>{
      'application/json': <String, dynamic>{
        'schema': <String, dynamic>{
          r'$ref': '#/components/schemas/ErrorResponse',
        },
      },
    },
  };
}
