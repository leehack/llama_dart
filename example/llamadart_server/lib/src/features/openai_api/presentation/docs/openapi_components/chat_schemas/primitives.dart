Map<String, dynamic> buildChatPrimitiveSchemas() {
  return <String, dynamic>{
    'ChatContentPart': <String, dynamic>{
      'type': 'object',
      'required': <String>['type'],
      'properties': <String, dynamic>{
        'type': <String, dynamic>{
          'type': 'string',
          'enum': <String>['text', 'input_text'],
        },
        'text': <String, dynamic>{'type': 'string'},
      },
      'additionalProperties': true,
    },
    'ToolCallFunction': <String, dynamic>{
      'type': 'object',
      'required': <String>['name'],
      'properties': <String, dynamic>{
        'name': <String, dynamic>{'type': 'string'},
        'arguments': <String, dynamic>{
          'description':
              'JSON string or object depending on context and provider behavior.',
          'oneOf': <dynamic>[
            <String, dynamic>{'type': 'string'},
            <String, dynamic>{'type': 'object'},
          ],
        },
      },
      'additionalProperties': true,
    },
    'ToolCall': <String, dynamic>{
      'type': 'object',
      'required': <String>['type', 'function'],
      'properties': <String, dynamic>{
        'id': <String, dynamic>{'type': 'string'},
        'type': <String, dynamic>{'type': 'string', 'example': 'function'},
        'function': <String, dynamic>{
          r'$ref': '#/components/schemas/ToolCallFunction',
        },
      },
      'additionalProperties': true,
    },
    'ChatMessage': <String, dynamic>{
      'type': 'object',
      'required': <String>['role'],
      'properties': <String, dynamic>{
        'role': <String, dynamic>{
          'type': 'string',
          'enum': <String>['system', 'developer', 'user', 'assistant', 'tool'],
        },
        'content': <String, dynamic>{
          'oneOf': <dynamic>[
            <String, dynamic>{'type': 'string'},
            <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{
                r'$ref': '#/components/schemas/ChatContentPart',
              },
            },
            <String, dynamic>{'type': 'null'},
          ],
        },
        'reasoning_content': <String, dynamic>{
          'oneOf': <dynamic>[
            <String, dynamic>{'type': 'string'},
            <String, dynamic>{'type': 'null'},
          ],
        },
        'tool_call_id': <String, dynamic>{'type': 'string'},
        'tool_calls': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{r'$ref': '#/components/schemas/ToolCall'},
        },
        'name': <String, dynamic>{'type': 'string'},
      },
      'additionalProperties': true,
    },
    'ToolDefinition': <String, dynamic>{
      'type': 'object',
      'required': <String>['type', 'function'],
      'properties': <String, dynamic>{
        'type': <String, dynamic>{
          'type': 'string',
          'enum': <String>['function'],
        },
        'function': <String, dynamic>{
          'type': 'object',
          'required': <String>['name'],
          'properties': <String, dynamic>{
            'name': <String, dynamic>{'type': 'string'},
            'description': <String, dynamic>{'type': 'string'},
            'parameters': <String, dynamic>{'type': 'object'},
          },
          'additionalProperties': true,
        },
      },
      'additionalProperties': true,
    },
  };
}
