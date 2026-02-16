import 'dart:convert';

import '../../../../shared/openai_http_exception.dart';

Map<String, dynamic> parseToolArguments(Object? rawArguments) {
  if (rawArguments == null) {
    return const <String, dynamic>{};
  }

  if (rawArguments is Map) {
    return Map<String, dynamic>.from(rawArguments);
  }

  if (rawArguments is String) {
    if (rawArguments.trim().isEmpty) {
      return const <String, dynamic>{};
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(rawArguments);
    } on FormatException {
      throw OpenAiHttpException.invalidRequest(
        'Tool call function arguments must be valid JSON.',
        param: 'messages.tool_calls.function.arguments',
      );
    }

    if (decoded is! Map) {
      throw OpenAiHttpException.invalidRequest(
        'Tool call function arguments must be a JSON object.',
        param: 'messages.tool_calls.function.arguments',
      );
    }

    return Map<String, dynamic>.from(decoded);
  }

  throw OpenAiHttpException.invalidRequest(
    'Tool call function arguments must be a string or object.',
    param: 'messages.tool_calls.function.arguments',
  );
}

String readContentAsString(Object? content) {
  if (content == null) {
    return '';
  }

  if (content is String) {
    return content;
  }

  return jsonEncode(content);
}
