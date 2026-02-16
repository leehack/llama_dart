import 'package:llamadart/llamadart.dart';

import '../../shared/openai_http_exception.dart';
import '../domain/openai_chat_completion_request.dart';
import 'parser_support/chat_completion_field_readers.dart';
import 'parser_support/chat_completion_message_parser.dart';
import 'parser_support/chat_completion_tool_parser.dart';

/// Parses and validates an OpenAI chat completion request body.
OpenAiChatCompletionRequest parseChatCompletionRequest(
  Map<String, dynamic> json, {
  required String configuredModelId,
  OpenAiToolInvoker? toolInvoker,
}) {
  final model = json['model'];
  if (model is! String || model.trim().isEmpty) {
    throw OpenAiHttpException.invalidRequest(
      'Missing required `model` field.',
      param: 'model',
    );
  }

  if (model != configuredModelId) {
    throw OpenAiHttpException.modelNotFound(model);
  }

  final n = readIntField(json['n'], 'n');
  if (n != null && n != 1) {
    throw OpenAiHttpException.invalidRequest(
      'Only `n = 1` is supported in this example server.',
      param: 'n',
    );
  }

  final stream = readBoolField(json['stream'], 'stream') ?? false;

  final messagesRaw = json['messages'];
  if (messagesRaw is! List || messagesRaw.isEmpty) {
    throw OpenAiHttpException.invalidRequest(
      '`messages` must be a non-empty array.',
      param: 'messages',
    );
  }

  final messages = messagesRaw
      .map((Object? raw) => parseChatMessage(raw))
      .toList(growable: false);

  final tools = parseToolDefinitions(json['tools'], toolInvoker: toolInvoker);
  final toolChoice = parseToolChoice(json['tool_choice'], tools);

  if (toolChoice == ToolChoice.required && (tools == null || tools.isEmpty)) {
    throw OpenAiHttpException.invalidRequest(
      '`tool_choice = "required"` requires `tools` to be provided.',
      param: 'tool_choice',
    );
  }

  final maxTokens = readIntField(json['max_tokens'], 'max_tokens');
  final temperature = readDoubleField(json['temperature'], 'temperature');
  final topP = readDoubleField(json['top_p'], 'top_p');
  final seed = readIntField(json['seed'], 'seed');
  final stops = parseStopSequences(json['stop']);

  var params = const GenerationParams(penalty: 1.0, topP: 0.95, minP: 0.05);
  if (maxTokens != null) {
    params = params.copyWith(maxTokens: maxTokens);
  }
  if (temperature != null) {
    params = params.copyWith(temp: temperature);
  }
  if (topP != null) {
    params = params.copyWith(topP: topP);
  }
  if (seed != null) {
    params = params.copyWith(seed: seed);
  }
  if (stops.isNotEmpty) {
    params = params.copyWith(stopSequences: stops);
  }

  return OpenAiChatCompletionRequest(
    model: model,
    messages: messages,
    params: params,
    stream: stream,
    tools: tools,
    toolChoice: toolChoice,
  );
}
