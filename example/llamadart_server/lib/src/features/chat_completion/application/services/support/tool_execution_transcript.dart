import 'package:llamadart/llamadart.dart';

import '../../../domain/openai_chat_completion_request.dart';

/// Appends assistant tool calls and tool results into conversation history.
Future<void> appendToolExecutionMessages({
  required List<LlamaChatMessage> conversation,
  required List<ToolDefinition> tools,
  required List<OpenAiToolCallRecord> toolCalls,
}) async {
  if (toolCalls.isEmpty) {
    return;
  }

  final assistantParts = toolCalls
      .map(
        (OpenAiToolCallRecord call) => LlamaToolCallContent(
          id: call.id,
          name: call.name,
          arguments: call.arguments,
          rawJson: call.argumentsRaw,
        ),
      )
      .toList(growable: false);

  conversation.add(
    LlamaChatMessage.withContent(
      role: LlamaChatRole.assistant,
      content: assistantParts,
    ),
  );

  final toolsByName = {
    for (final definition in tools) definition.name: definition,
  };

  for (final call in toolCalls) {
    final definition = toolsByName[call.name];
    Object? result;

    if (definition == null) {
      result = {'ok': false, 'error': 'Tool `${call.name}` was not found.'};
    } else {
      try {
        result = await definition.invoke(call.arguments);
      } catch (error) {
        result = {
          'ok': false,
          'error': 'Tool `${call.name}` execution failed.',
          'details': '$error',
        };
      }
    }

    conversation.add(
      LlamaChatMessage.withContent(
        role: LlamaChatRole.tool,
        content: <LlamaContentPart>[
          LlamaToolResultContent(id: call.id, name: call.name, result: result),
        ],
      ),
    );
  }
}
