Map<String, dynamic> buildChatResponseSchemas({required String modelId}) {
  return <String, dynamic>{
    'ChatCompletionMessage': <String, dynamic>{
      'type': 'object',
      'required': <String>['role'],
      'properties': <String, dynamic>{
        'role': <String, dynamic>{'type': 'string', 'example': 'assistant'},
        'content': <String, dynamic>{
          'oneOf': <dynamic>[
            <String, dynamic>{'type': 'string'},
            <String, dynamic>{'type': 'null'},
          ],
        },
        'reasoning_content': <String, dynamic>{
          'oneOf': <dynamic>[
            <String, dynamic>{'type': 'string'},
            <String, dynamic>{'type': 'null'},
          ],
        },
        'tool_calls': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{r'$ref': '#/components/schemas/ToolCall'},
        },
      },
      'additionalProperties': true,
    },
    'ChatCompletionChoice': <String, dynamic>{
      'type': 'object',
      'required': <String>['index', 'message', 'finish_reason'],
      'properties': <String, dynamic>{
        'index': <String, dynamic>{'type': 'integer'},
        'message': <String, dynamic>{
          r'$ref': '#/components/schemas/ChatCompletionMessage',
        },
        'finish_reason': <String, dynamic>{
          'oneOf': <dynamic>[
            <String, dynamic>{'type': 'string'},
            <String, dynamic>{'type': 'null'},
          ],
        },
      },
    },
    'Usage': <String, dynamic>{
      'type': 'object',
      'required': <String>[
        'prompt_tokens',
        'completion_tokens',
        'total_tokens',
      ],
      'properties': <String, dynamic>{
        'prompt_tokens': <String, dynamic>{'type': 'integer'},
        'completion_tokens': <String, dynamic>{'type': 'integer'},
        'total_tokens': <String, dynamic>{'type': 'integer'},
      },
    },
    'ChatCompletionResponse': <String, dynamic>{
      'type': 'object',
      'required': <String>[
        'id',
        'object',
        'created',
        'model',
        'choices',
        'usage',
      ],
      'properties': <String, dynamic>{
        'id': <String, dynamic>{'type': 'string'},
        'object': <String, dynamic>{
          'type': 'string',
          'example': 'chat.completion',
        },
        'created': <String, dynamic>{'type': 'integer'},
        'model': <String, dynamic>{'type': 'string', 'example': modelId},
        'choices': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{
            r'$ref': '#/components/schemas/ChatCompletionChoice',
          },
        },
        'usage': <String, dynamic>{r'$ref': '#/components/schemas/Usage'},
      },
    },
  };
}
