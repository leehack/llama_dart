Map<String, dynamic> buildOpenApiSecuritySchemes() {
  return <String, dynamic>{
    'bearerAuth': <String, dynamic>{
      'type': 'http',
      'scheme': 'bearer',
      'bearerFormat': 'API Key',
      'description': 'Send your API key as `Authorization: Bearer <key>`.',
    },
  };
}
