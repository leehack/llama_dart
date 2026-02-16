import 'package:llamadart/llamadart.dart';

import '../../../../shared/openai_http_exception.dart';

ToolChoice? parseToolChoice(Object? raw, List<ToolDefinition>? tools) {
  if (raw == null) {
    if (tools == null || tools.isEmpty) {
      return null;
    }
    return ToolChoice.auto;
  }

  if (raw is String) {
    switch (raw) {
      case 'none':
        return ToolChoice.none;
      case 'auto':
        return ToolChoice.auto;
      case 'required':
        return ToolChoice.required;
      default:
        throw OpenAiHttpException.invalidRequest(
          'Unsupported `tool_choice` value `$raw`.',
          param: 'tool_choice',
        );
    }
  }

  if (raw is Map) {
    final choice = Map<String, dynamic>.from(raw);
    final type = choice['type'];
    if (type == 'function') {
      return ToolChoice.required;
    }

    throw OpenAiHttpException.invalidRequest(
      'Only function tool choices are supported.',
      param: 'tool_choice',
    );
  }

  throw OpenAiHttpException.invalidRequest(
    '`tool_choice` must be a string or object.',
    param: 'tool_choice',
  );
}
