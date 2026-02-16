import 'path_security.dart';

Map<String, dynamic> buildChatPaths({
  required bool apiKeyEnabled,
  required String modelId,
}) {
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
              'examples': _buildChatRequestExamples(modelId),
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

Map<String, dynamic> _buildChatRequestExamples(String modelId) {
  return <String, dynamic>{
    'basic': <String, dynamic>{
      'summary': 'Basic non-streaming request',
      'value': <String, dynamic>{
        'model': modelId,
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{'role': 'system', 'content': 'You are concise.'},
          <String, dynamic>{
            'role': 'user',
            'content': 'Give one sentence about Seoul.',
          },
        ],
        'max_tokens': 128,
      },
    },
    'streaming': <String, dynamic>{
      'summary': 'Streaming request (SSE)',
      'value': <String, dynamic>{
        'model': modelId,
        'stream': true,
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{'role': 'user', 'content': 'Write a short poem.'},
        ],
      },
    },
    'with_tools': <String, dynamic>{
      'summary': 'Tool-calling request',
      'value': <String, dynamic>{
        'model': modelId,
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'user',
            'content': 'What is weather in Seoul?',
          },
        ],
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'function',
            'function': <String, dynamic>{
              'name': 'get_weather',
              'description': 'Get weather by city.',
              'parameters': <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'city': <String, dynamic>{'type': 'string'},
                },
                'required': <String>['city'],
              },
            },
          },
        ],
        'tool_choice': 'auto',
      },
    },
  };
}
