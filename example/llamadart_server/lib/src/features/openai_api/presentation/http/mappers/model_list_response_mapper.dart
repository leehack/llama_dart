/// Creates a response payload for `GET /v1/models`.
Map<String, dynamic> toOpenAiModelListResponse({
  required String modelId,
  required int created,
  String ownedBy = 'llamadart',
}) {
  return {
    'object': 'list',
    'data': [
      {
        'id': modelId,
        'object': 'model',
        'created': created,
        'owned_by': ownedBy,
      },
    ],
  };
}
