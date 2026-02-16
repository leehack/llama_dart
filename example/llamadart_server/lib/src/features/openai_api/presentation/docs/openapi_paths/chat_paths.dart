import 'path_security.dart';

Map<String, dynamic> buildChatPaths({required bool apiKeyEnabled}) {
  return <String, dynamic>{
    '/v1/chat/completions': <String, dynamic>{
      'post': <String, dynamic>{
        'tags': <String>['Chat'],
        'summary': 'Create chat completion',
        'operationId': 'createChatCompletion',
        'security': operationSecurity(apiKeyEnabled),
        'requestBody': <String, dynamic>{
          'required': true,
          'content': <String, dynamic>{
            'application/json': <String, dynamic>{
              'schema': <String, dynamic>{
                r'$ref': '#/components/schemas/ChatCompletionRequest',
              },
            },
          },
        },
        'responses': <String, dynamic>{
          '200': <String, dynamic>{
            'description':
                'Chat completion response (JSON when `stream=false`, SSE when `stream=true`).',
            'content': <String, dynamic>{
              'application/json': <String, dynamic>{
                'schema': <String, dynamic>{
                  r'$ref': '#/components/schemas/ChatCompletionResponse',
                },
              },
              'text/event-stream': <String, dynamic>{
                'schema': <String, dynamic>{
                  'type': 'string',
                  'description':
                      'SSE stream of `chat.completion.chunk` payloads followed by `data: [DONE]`.',
                },
              },
            },
          },
          '400': <String, dynamic>{
            r'$ref': '#/components/responses/BadRequestError',
          },
          '401': <String, dynamic>{
            r'$ref': '#/components/responses/UnauthorizedError',
          },
          '429': <String, dynamic>{
            r'$ref': '#/components/responses/RateLimitError',
          },
          '500': <String, dynamic>{
            r'$ref': '#/components/responses/ServerError',
          },
        },
      },
    },
  };
}
