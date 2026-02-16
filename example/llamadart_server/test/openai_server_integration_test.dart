import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_server/llamadart_server.dart';
import 'package:relic/relic.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAiApiServer', () {
    late _FakeApiServerEngine fakeEngine;
    late _RunningServer server;
    late http.Client client;

    setUp(() async {
      fakeEngine = _FakeApiServerEngine();
      server = await _startServer(fakeEngine);
      client = http.Client();
    });

    tearDown(() async {
      client.close();
      await server.close();
    });

    test('GET /v1/models returns configured model', () async {
      final response = await client.get(server.uri('/v1/models'));
      expect(response.statusCode, 200);

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['object'], 'list');

      final data = json['data'] as List<dynamic>;
      final first = data.first as Map<String, dynamic>;
      expect(first['id'], 'test-model');
      expect(first['object'], 'model');
    });

    test('GET /openapi.json returns expected spec paths', () async {
      final response = await client.get(server.uri('/openapi.json'));
      expect(response.statusCode, 200);

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['openapi'], '3.1.0');

      final servers = json['servers'] as List<dynamic>;
      final firstServer = servers.first as Map<String, dynamic>;
      expect(firstServer['url'], server.uri('/').origin);

      final paths = json['paths'] as Map<String, dynamic>;
      expect(paths.containsKey('/openapi.json'), isTrue);
      expect(paths.containsKey('/docs'), isTrue);
      expect(paths.containsKey('/v1/models'), isTrue);
      expect(paths.containsKey('/v1/chat/completions'), isTrue);
    });

    test('GET /docs serves Swagger UI HTML', () async {
      final response = await client.get(server.uri('/docs'));
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], startsWith('text/html'));
      expect(response.body, contains('SwaggerUIBundle'));
      expect(response.body, contains('/openapi.json'));
    });

    test('POST /v1/chat/completions returns OpenAI-shaped response', () async {
      final response = await client.post(
        server.uri('/v1/chat/completions'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'model': 'test-model',
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{'role': 'user', 'content': 'Say hi'},
          ],
        }),
      );

      expect(response.statusCode, 200);
      final json = jsonDecode(response.body) as Map<String, dynamic>;

      expect(json['object'], 'chat.completion');
      expect(json['model'], 'test-model');

      final choices = json['choices'] as List<dynamic>;
      final choice = choices.first as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>;

      expect(message['role'], 'assistant');
      expect(message['content'], 'Hello world');
      expect(choice['finish_reason'], 'stop');

      final usage = json['usage'] as Map<String, dynamic>;
      expect(usage['prompt_tokens'], 7);
      expect(usage['completion_tokens'], 2);
      expect(usage['total_tokens'], 9);
      expect(fakeEngine.cancelCount, greaterThan(0));
    });

    test(
      'POST /v1/chat/completions stream mode returns SSE and DONE',
      () async {
        final request = http.Request('POST', server.uri('/v1/chat/completions'))
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(<String, dynamic>{
            'model': 'test-model',
            'stream': true,
            'messages': <Map<String, dynamic>>[
              <String, dynamic>{'role': 'user', 'content': 'stream please'},
            ],
          });

        final streamed = await client.send(request);
        expect(streamed.statusCode, 200);
        expect(
          streamed.headers['content-type'],
          startsWith('text/event-stream'),
        );

        final body = await streamed.stream.bytesToString();
        expect(body, contains('data: [DONE]\n\n'));
        expect(body, contains('"object":"chat.completion.chunk"'));
        expect(body, contains('"role":"assistant"'));
      },
    );
  });

  group('OpenAiApiServer auth', () {
    late _RunningServer server;
    late http.Client client;

    setUp(() async {
      server = await _startServer(_FakeApiServerEngine(), apiKey: 'dev-key');
      client = http.Client();
    });

    tearDown(() async {
      client.close();
      await server.close();
    });

    test('requires bearer token for /v1 routes when api key is set', () async {
      final unauthorized = await client.get(server.uri('/v1/models'));
      expect(unauthorized.statusCode, 401);

      final unauthorizedJson =
          jsonDecode(unauthorized.body) as Map<String, dynamic>;
      final error = unauthorizedJson['error'] as Map<String, dynamic>;
      expect(error['type'], 'authentication_error');

      final authorized = await client.get(
        server.uri('/v1/models'),
        headers: <String, String>{'Authorization': 'Bearer dev-key'},
      );
      expect(authorized.statusCode, 200);
    });

    test('OpenAPI marks secured operations when api key is enabled', () async {
      final response = await client.get(server.uri('/openapi.json'));
      expect(response.statusCode, 200);

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final paths = json['paths'] as Map<String, dynamic>;

      final modelsPath = paths['/v1/models'] as Map<String, dynamic>;
      final modelsGet = modelsPath['get'] as Map<String, dynamic>;
      final modelsSecurity = modelsGet['security'] as List<dynamic>;
      expect(modelsSecurity, isNotEmpty);

      final chatPath = paths['/v1/chat/completions'] as Map<String, dynamic>;
      final chatPost = chatPath['post'] as Map<String, dynamic>;
      final chatSecurity = chatPost['security'] as List<dynamic>;
      expect(chatSecurity, isNotEmpty);
    });
  });

  group('OpenAiApiServer busy state', () {
    late _BlockingApiServerEngine blockingEngine;
    late _RunningServer server;
    late http.Client client;

    setUp(() async {
      blockingEngine = _BlockingApiServerEngine();
      server = await _startServer(blockingEngine);
      client = http.Client();
    });

    tearDown(() async {
      blockingEngine.release();
      client.close();
      await server.close();
    });

    test('returns 429 while another generation is in progress', () async {
      final firstFuture = client.post(
        server.uri('/v1/chat/completions'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'model': 'test-model',
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{'role': 'user', 'content': 'first'},
          ],
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final second = await client.post(
        server.uri('/v1/chat/completions'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'model': 'test-model',
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{'role': 'user', 'content': 'second'},
          ],
        }),
      );

      expect(second.statusCode, 429);
      final json = jsonDecode(second.body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>;
      expect(error['type'], 'rate_limit_error');
      expect(error['code'], 'server_busy');

      blockingEngine.release();
      final first = await firstFuture;
      expect(first.statusCode, 200);
    });
  });

  group('OpenAiApiServer server tool loop', () {
    late _ToolLoopApiServerEngine toolEngine;
    late _RunningServer server;
    late http.Client client;

    setUp(() async {
      toolEngine = _ToolLoopApiServerEngine();
      server = await _startServer(
        toolEngine,
        toolInvoker: _exampleToolInvoker,
        maxToolRounds: 3,
      );
      client = http.Client();
    });

    tearDown(() async {
      client.close();
      await server.close();
    });

    test('executes tool calls and returns final assistant answer', () async {
      final response = await client.post(
        server.uri('/v1/chat/completions'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'model': 'test-model',
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{
              'role': 'user',
              'content': 'Call get_weather for Seoul.',
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
          'tool_choice': 'required',
        }),
      );

      expect(response.statusCode, 200);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>;
      final choice = choices.first as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>;

      expect(choice['finish_reason'], 'stop');
      expect(message['content'], 'The weather in Seoul is sunny.');

      expect(toolEngine.createCalls, hasLength(2));
      expect(
        toolEngine.createCalls[1].any(
          (message) => message.role == LlamaChatRole.tool,
        ),
        isTrue,
      );
    });
  });
}

Future<_RunningServer> _startServer(
  ApiServerEngine engine, {
  String? apiKey,
  OpenAiToolInvoker? toolInvoker,
  int maxToolRounds = 5,
}) async {
  final app = OpenAiApiServer(
    engine: engine,
    modelId: 'test-model',
    apiKey: apiKey,
    toolInvoker: toolInvoker,
    maxToolRounds: maxToolRounds,
  ).buildApp();

  final relicServer = await app.serve(
    address: InternetAddress.loopbackIPv4,
    port: 0,
  );

  return _RunningServer(relicServer);
}

class _RunningServer {
  final RelicServer _server;

  _RunningServer(this._server);

  Uri uri(String path) {
    return Uri.parse('http://127.0.0.1:${_server.port}$path');
  }

  Future<void> close() {
    return _server.close();
  }
}

class _FakeApiServerEngine implements ApiServerEngine {
  int cancelCount = 0;

  @override
  bool get isReady => true;

  @override
  Future<LlamaChatTemplateResult> chatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
  }) async {
    return const LlamaChatTemplateResult(prompt: 'prompt', tokenCount: 7);
  }

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams params = const GenerationParams(),
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
  }) async* {
    yield LlamaCompletionChunk(
      id: 'chatcmpl-test',
      object: 'chat.completion.chunk',
      created: 1700000000,
      model: 'test-model',
      choices: <LlamaCompletionChunkChoice>[
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(content: 'Hello '),
        ),
      ],
    );

    yield LlamaCompletionChunk(
      id: 'chatcmpl-test',
      object: 'chat.completion.chunk',
      created: 1700000000,
      model: 'test-model',
      choices: <LlamaCompletionChunkChoice>[
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(content: 'world'),
          finishReason: 'stop',
        ),
      ],
    );
  }

  @override
  Future<int> getTokenCount(String text) async {
    return text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  @override
  void cancelGeneration() {
    cancelCount++;
  }
}

class _BlockingApiServerEngine extends _FakeApiServerEngine {
  final Completer<void> _releaseCompleter = Completer<void>();

  void release() {
    if (!_releaseCompleter.isCompleted) {
      _releaseCompleter.complete();
    }
  }

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams params = const GenerationParams(),
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
  }) async* {
    await _releaseCompleter.future;
    yield LlamaCompletionChunk(
      id: 'chatcmpl-blocking',
      object: 'chat.completion.chunk',
      created: 1700000000,
      model: 'test-model',
      choices: <LlamaCompletionChunkChoice>[
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(content: 'released'),
          finishReason: 'stop',
        ),
      ],
    );
  }
}

class _ToolLoopApiServerEngine implements ApiServerEngine {
  final List<List<LlamaChatMessage>> createCalls = <List<LlamaChatMessage>>[];

  @override
  bool get isReady => true;

  @override
  Future<LlamaChatTemplateResult> chatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
  }) async {
    return LlamaChatTemplateResult(
      prompt: 'prompt',
      tokenCount: messages.length * 3,
    );
  }

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams params = const GenerationParams(),
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
  }) async* {
    createCalls.add(List<LlamaChatMessage>.from(messages));
    final hasToolResult = messages.any(
      (message) => message.role == LlamaChatRole.tool,
    );

    if (!hasToolResult) {
      yield LlamaCompletionChunk(
        id: 'chatcmpl-tool-round-1',
        object: 'chat.completion.chunk',
        created: 1700001000,
        model: 'test-model',
        choices: <LlamaCompletionChunkChoice>[
          LlamaCompletionChunkChoice(
            index: 0,
            delta: LlamaCompletionChunkDelta(
              toolCalls: <LlamaCompletionChunkToolCall>[
                LlamaCompletionChunkToolCall(
                  index: 0,
                  id: 'call_weather_1',
                  type: 'function',
                  function: LlamaCompletionChunkFunction(
                    name: 'get_weather',
                    arguments: '{"city":"Seoul"}',
                  ),
                ),
              ],
            ),
            finishReason: 'tool_calls',
          ),
        ],
      );
      return;
    }

    yield LlamaCompletionChunk(
      id: 'chatcmpl-tool-round-2',
      object: 'chat.completion.chunk',
      created: 1700001001,
      model: 'test-model',
      choices: <LlamaCompletionChunkChoice>[
        LlamaCompletionChunkChoice(
          index: 0,
          delta: LlamaCompletionChunkDelta(
            content: 'The weather in Seoul is sunny.',
          ),
          finishReason: 'stop',
        ),
      ],
    );
  }

  @override
  Future<int> getTokenCount(String text) async {
    return text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  @override
  void cancelGeneration() {}
}

Future<Object?> _exampleToolInvoker(
  String toolName,
  Map<String, dynamic> arguments,
) async {
  if (toolName != 'get_weather') {
    throw UnsupportedError('Unsupported tool: $toolName');
  }

  return <String, dynamic>{
    'ok': true,
    'city': arguments['city'] ?? 'unknown',
    'condition': 'sunny',
  };
}
