import 'dart:convert';

import 'package:llamadart/llamadart.dart';

import '../../../../shared/openai_http_exception.dart';
import 'message_content_utils.dart';

List<LlamaToolCallContent> parseAssistantToolCalls(Object? rawToolCalls) {
  if (rawToolCalls == null) {
    return const <LlamaToolCallContent>[];
  }

  if (rawToolCalls is! List) {
    throw OpenAiHttpException.invalidRequest(
      '`tool_calls` must be an array.',
      param: 'messages.tool_calls',
    );
  }

  final result = <LlamaToolCallContent>[];

  for (final rawToolCall in rawToolCalls) {
    if (rawToolCall is! Map) {
      throw OpenAiHttpException.invalidRequest(
        'Each tool call must be an object.',
        param: 'messages.tool_calls',
      );
    }

    final call = Map<String, dynamic>.from(rawToolCall);

    final function = call['function'];
    if (function is! Map) {
      throw OpenAiHttpException.invalidRequest(
        'Tool calls require a `function` object.',
        param: 'messages.tool_calls.function',
      );
    }

    final functionMap = Map<String, dynamic>.from(function);
    final name = functionMap['name'];
    if (name is! String || name.isEmpty) {
      throw OpenAiHttpException.invalidRequest(
        'Tool call function name must be a non-empty string.',
        param: 'messages.tool_calls.function.name',
      );
    }

    result.add(
      LlamaToolCallContent(
        id: call['id'] as String?,
        name: name,
        arguments: parseToolArguments(functionMap['arguments']),
        rawJson: jsonEncode(call),
      ),
    );
  }

  return result;
}
