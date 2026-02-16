import 'package:llamadart/llamadart.dart';

import '../../../../shared/openai_http_exception.dart';

LlamaChatRole parseMessageRole(String role) {
  switch (role) {
    case 'system':
    case 'developer':
      return LlamaChatRole.system;
    case 'user':
      return LlamaChatRole.user;
    case 'assistant':
      return LlamaChatRole.assistant;
    case 'tool':
      return LlamaChatRole.tool;
    default:
      throw OpenAiHttpException.invalidRequest(
        'Unsupported role `$role`.',
        param: 'messages.role',
      );
  }
}
