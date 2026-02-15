import 'package:llamadart/llamadart.dart';
import 'package:llamadart_server/llamadart_server.dart';
import 'package:test/test.dart';

void main() {
  group('parseChatCompletionRequest', () {
    test('parses a simple non-stream request', () {
      final request = parseChatCompletionRequest(<String, dynamic>{
        'model': 'llamadart-local',
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{'role': 'system', 'content': 'You are concise.'},
          <String, dynamic>{'role': 'user', 'content': 'Say hello.'},
        ],
        'max_tokens': 64,
        'temperature': 0.2,
        'top_p': 0.8,
        'seed': 42,
        'stop': <String>['END'],
      }, configuredModelId: 'llamadart-local');

      expect(request.stream, isFalse);
      expect(request.messages, hasLength(2));
      expect(request.params.maxTokens, 64);
      expect(request.params.temp, 0.2);
      expect(request.params.topP, 0.8);
      expect(request.params.seed, 42);
      expect(request.params.stopSequences, <String>['END']);
    });

    test('parses tools and required tool choice', () {
      final request = parseChatCompletionRequest(<String, dynamic>{
        'model': 'llamadart-local',
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
              'description': 'Get weather by city',
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
      }, configuredModelId: 'llamadart-local');

      expect(request.tools, isNotNull);
      expect(request.tools, hasLength(1));
      expect(request.tools!.first.name, 'get_weather');
      expect(request.toolChoice, ToolChoice.required);
    });

    test('throws for n > 1', () {
      expect(
        () => parseChatCompletionRequest(<String, dynamic>{
          'model': 'llamadart-local',
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{'role': 'user', 'content': 'hi'},
          ],
          'n': 2,
        }, configuredModelId: 'llamadart-local'),
        throwsA(
          isA<OpenAiHttpException>().having(
            (OpenAiHttpException error) => error.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
    });
  });

  group('toOpenAiChatCompletionChunk', () {
    test('includes assistant role on first chunk', () {
      final chunk = LlamaCompletionChunk(
        id: 'chatcmpl-123',
        object: 'chat.completion.chunk',
        created: 123,
        model: 'ignored',
        choices: <LlamaCompletionChunkChoice>[
          LlamaCompletionChunkChoice(
            index: 0,
            delta: LlamaCompletionChunkDelta(content: 'Hello'),
          ),
        ],
      );

      final json = toOpenAiChatCompletionChunk(
        chunk,
        model: 'llamadart-local',
        includeRole: true,
      );

      final choices = json['choices'] as List<dynamic>;
      final choice = choices.first as Map<String, dynamic>;
      final delta = choice['delta'] as Map<String, dynamic>;

      expect(json['model'], 'llamadart-local');
      expect(delta['role'], 'assistant');
      expect(delta['content'], 'Hello');
      expect(choice['finish_reason'], isNull);
    });
  });

  group('OpenAiChatCompletionAccumulator', () {
    test('merges tool call argument fragments', () {
      final accumulator = OpenAiChatCompletionAccumulator();

      accumulator.addChunk(
        LlamaCompletionChunk(
          id: 'chatcmpl-123',
          object: 'chat.completion.chunk',
          created: 123,
          model: 'ignored',
          choices: <LlamaCompletionChunkChoice>[
            LlamaCompletionChunkChoice(
              index: 0,
              delta: LlamaCompletionChunkDelta(
                toolCalls: <LlamaCompletionChunkToolCall>[
                  LlamaCompletionChunkToolCall(
                    index: 0,
                    id: 'call_abc',
                    type: 'function',
                    function: LlamaCompletionChunkFunction(
                      name: 'get_weather',
                      arguments: '{"city":"Se',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      accumulator.addChunk(
        LlamaCompletionChunk(
          id: 'chatcmpl-123',
          object: 'chat.completion.chunk',
          created: 123,
          model: 'ignored',
          choices: <LlamaCompletionChunkChoice>[
            LlamaCompletionChunkChoice(
              index: 0,
              delta: LlamaCompletionChunkDelta(
                toolCalls: <LlamaCompletionChunkToolCall>[
                  LlamaCompletionChunkToolCall(
                    index: 0,
                    function: LlamaCompletionChunkFunction(arguments: 'oul"}'),
                  ),
                ],
              ),
              finishReason: 'tool_calls',
            ),
          ],
        ),
      );

      final response = accumulator.toResponseJson(
        id: 'chatcmpl-123',
        created: 123,
        model: 'llamadart-local',
        promptTokens: 10,
        completionTokens: 5,
      );

      final choices = response['choices'] as List<dynamic>;
      final choice = choices.first as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>;
      final toolCalls = message['tool_calls'] as List<dynamic>;
      final toolCall = toolCalls.first as Map<String, dynamic>;
      final function = toolCall['function'] as Map<String, dynamic>;

      expect(choice['finish_reason'], 'tool_calls');
      expect(function['name'], 'get_weather');
      expect(function['arguments'], '{"city":"Seoul"}');
      expect(message['content'], isNull);
    });
  });

  group('SSE helpers', () {
    test('encodes data and done markers', () {
      expect(encodeSseData(<String, dynamic>{'x': 1}), 'data: {"x":1}\n\n');
      expect(encodeSseDone(), 'data: [DONE]\n\n');
    });
  });
}
