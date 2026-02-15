/// Builds OpenAPI schema for the API server example.
Map<String, dynamic> buildOpenApiSpec({
  required String modelId,
  required bool apiKeyEnabled,
  required String serverUrl,
}) {
  return <String, dynamic>{
    'openapi': '3.1.0',
    'info': <String, dynamic>{
      'title': 'llamadart OpenAI-compatible API',
      'version': '1.0.0',
      'description':
          'Local OpenAI-compatible API powered by llamadart and Relic.',
    },
    'servers': <Map<String, dynamic>>[
      <String, dynamic>{'url': serverUrl, 'description': 'Current server URL'},
    ],
    'tags': <Map<String, dynamic>>[
      <String, dynamic>{'name': 'System'},
      <String, dynamic>{'name': 'Models'},
      <String, dynamic>{'name': 'Chat'},
      <String, dynamic>{'name': 'Docs'},
    ],
    'paths': <String, dynamic>{
      '/healthz': <String, dynamic>{
        'get': <String, dynamic>{
          'tags': <String>['System'],
          'summary': 'Health check',
          'operationId': 'getHealth',
          'responses': <String, dynamic>{
            '200': <String, dynamic>{
              'description': 'Server health',
              'content': <String, dynamic>{
                'application/json': <String, dynamic>{
                  'schema': <String, dynamic>{
                    r'$ref': '#/components/schemas/HealthResponse',
                  },
                },
              },
            },
          },
        },
      },
      '/v1/models': <String, dynamic>{
        'get': <String, dynamic>{
          'tags': <String>['Models'],
          'summary': 'List available models',
          'operationId': 'listModels',
          'security': _operationSecurity(apiKeyEnabled),
          'responses': <String, dynamic>{
            '200': <String, dynamic>{
              'description': 'Model list',
              'content': <String, dynamic>{
                'application/json': <String, dynamic>{
                  'schema': <String, dynamic>{
                    r'$ref': '#/components/schemas/ModelListResponse',
                  },
                },
              },
            },
            '401': <String, dynamic>{
              r'$ref': '#/components/responses/UnauthorizedError',
            },
          },
        },
      },
      '/v1/chat/completions': <String, dynamic>{
        'post': <String, dynamic>{
          'tags': <String>['Chat'],
          'summary': 'Create chat completion',
          'operationId': 'createChatCompletion',
          'security': _operationSecurity(apiKeyEnabled),
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
      '/openapi.json': <String, dynamic>{
        'get': <String, dynamic>{
          'tags': <String>['Docs'],
          'summary': 'Get OpenAPI specification',
          'operationId': 'getOpenApiSpec',
          'responses': <String, dynamic>{
            '200': <String, dynamic>{
              'description': 'OpenAPI document',
              'content': <String, dynamic>{
                'application/json': <String, dynamic>{
                  'schema': <String, dynamic>{'type': 'object'},
                },
              },
            },
          },
        },
      },
      '/docs': <String, dynamic>{
        'get': <String, dynamic>{
          'tags': <String>['Docs'],
          'summary': 'Swagger UI page',
          'operationId': 'getSwaggerUi',
          'responses': <String, dynamic>{
            '200': <String, dynamic>{
              'description': 'Swagger UI HTML',
              'content': <String, dynamic>{
                'text/html': <String, dynamic>{
                  'schema': <String, dynamic>{'type': 'string'},
                },
              },
            },
          },
        },
      },
    },
    'components': <String, dynamic>{
      'securitySchemes': <String, dynamic>{
        'bearerAuth': <String, dynamic>{
          'type': 'http',
          'scheme': 'bearer',
          'bearerFormat': 'API Key',
          'description': 'Send your API key as `Authorization: Bearer <key>`.',
        },
      },
      'responses': <String, dynamic>{
        'BadRequestError': _errorResponse('Bad request'),
        'UnauthorizedError': _errorResponse('Unauthorized'),
        'RateLimitError': _errorResponse('Busy'),
        'ServerError': _errorResponse('Server error'),
      },
      'schemas': <String, dynamic>{
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
            'owned_by': <String, dynamic>{
              'type': 'string',
              'example': 'llamadart',
            },
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
              'enum': <String>[
                'system',
                'developer',
                'user',
                'assistant',
                'tool',
              ],
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
            'tool_call_id': <String, dynamic>{'type': 'string'},
            'tool_calls': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{
                r'$ref': '#/components/schemas/ToolCall',
              },
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
            'tool_calls': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{
                r'$ref': '#/components/schemas/ToolCall',
              },
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
            'error': <String, dynamic>{
              r'$ref': '#/components/schemas/OpenAiError',
            },
          },
        },
      },
    },
  };
}

List<Map<String, List<String>>> _operationSecurity(bool apiKeyEnabled) {
  if (!apiKeyEnabled) {
    return const <Map<String, List<String>>>[];
  }

  return <Map<String, List<String>>>[
    <String, List<String>>{'bearerAuth': <String>[]},
  ];
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
