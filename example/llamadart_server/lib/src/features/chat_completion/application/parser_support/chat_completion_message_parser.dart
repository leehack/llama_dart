import 'package:llamadart/llamadart.dart';

import '../../../shared/openai_http_exception.dart';
import 'message_parsing/assistant_tool_calls_parser.dart';
import 'message_parsing/message_content_part_parser.dart';
import 'message_parsing/message_content_utils.dart';
import 'message_parsing/message_role_parser.dart';
import 'message_parsing/tool_message_parser.dart';

LlamaChatMessage parseChatMessage(Object? raw) {
  if (raw is! Map) {
    throw OpenAiHttpException.invalidRequest(
      'Each message must be a JSON object.',
      param: 'messages',
    );
  }

  final message = Map<String, dynamic>.from(raw);
  final roleRaw = message['role'];
  if (roleRaw is! String || roleRaw.isEmpty) {
    throw OpenAiHttpException.invalidRequest(
      'Message `role` must be a non-empty string.',
      param: 'messages.role',
    );
  }

  final role = parseMessageRole(roleRaw);
  if (role == LlamaChatRole.tool) {
    return parseToolRoleMessage(message);
  }

  final parts = parseContentParts(message['content'], role);
  if (role == LlamaChatRole.assistant) {
    _appendAssistantParts(parts, message);
  }

  if (parts.isEmpty) {
    if (role != LlamaChatRole.assistant) {
      throw OpenAiHttpException.invalidRequest(
        'Message content cannot be empty for role `${role.name}`.',
        param: 'messages.content',
      );
    }
    parts.add(const LlamaTextContent(''));
  }

  return LlamaChatMessage.withContent(role: role, content: parts);
}

void _appendAssistantParts(
  List<LlamaContentPart> parts,
  Map<String, dynamic> message,
) {
  final reasoning = readContentAsString(message['reasoning_content']).trim();
  if (reasoning.isNotEmpty) {
    parts.add(LlamaThinkingContent(reasoning));
  }

  parts.addAll(parseAssistantToolCalls(message['tool_calls']));
}
