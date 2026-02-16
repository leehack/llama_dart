import 'package:llamadart/llamadart.dart';

import '../../../../shared/openai_http_exception.dart';
import 'message_content_utils.dart';

LlamaChatMessage parseToolRoleMessage(Map<String, dynamic> message) {
  final toolCallId = message['tool_call_id'];
  if (toolCallId != null && toolCallId is! String) {
    throw OpenAiHttpException.invalidRequest(
      '`tool_call_id` must be a string.',
      param: 'messages.tool_call_id',
    );
  }

  final content = readContentAsString(message['content']);
  final nameRaw = message['name'];
  final name = nameRaw is String && nameRaw.isNotEmpty ? nameRaw : 'tool';

  return LlamaChatMessage.withContent(
    role: LlamaChatRole.tool,
    content: <LlamaContentPart>[
      LlamaToolResultContent(
        id: toolCallId as String?,
        name: name,
        result: content,
      ),
    ],
  );
}
