Map<String, dynamic> buildChatRequestSchemas({required String modelId}) {
  return <String, dynamic>{
    'ChatCompletionRequest': <String, dynamic>{
      'type': 'object',
      'required': <String>['model', 'messages'],
      'properties': <String, dynamic>{
        'model': <String, dynamic>{'type': 'string', 'example': modelId},
        'messages': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{
            r'$ref': '#/components/schemas/ChatMessage',
          },
        },
        'stream': <String, dynamic>{'type': 'boolean', 'default': false},
        'max_tokens': <String, dynamic>{'type': 'integer', 'minimum': 1},
        'temperature': <String, dynamic>{'type': 'number'},
        'top_p': <String, dynamic>{'type': 'number'},
        'seed': <String, dynamic>{'type': 'integer'},
        'n': <String, dynamic>{
          'type': 'integer',
          'enum': <int>[1],
          'description': 'This example currently supports only `n = 1`.',
        },
        'stop': <String, dynamic>{
          'oneOf': <dynamic>[
            <String, dynamic>{'type': 'string'},
            <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'string'},
            },
          ],
        },
        'tools': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{
            r'$ref': '#/components/schemas/ToolDefinition',
          },
        },
        'tool_choice': <String, dynamic>{
          'oneOf': <dynamic>[
            <String, dynamic>{
              'type': 'string',
              'enum': <String>['none', 'auto', 'required'],
            },
            <String, dynamic>{'type': 'object'},
          ],
        },
      },
      'additionalProperties': true,
    },
  };
}
