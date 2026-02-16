import 'package:llamadart/llamadart.dart';

import '../../../../shared/openai_http_exception.dart';

List<LlamaContentPart> parseContentParts(Object? content, LlamaChatRole role) {
  if (content == null) {
    return <LlamaContentPart>[];
  }

  if (content is String) {
    return <LlamaContentPart>[LlamaTextContent(content)];
  }

  if (content is! List) {
    throw OpenAiHttpException.invalidRequest(
      '`content` must be a string, an array, or null.',
      param: 'messages.content',
    );
  }

  final parts = <LlamaContentPart>[];
  for (final rawPart in content) {
    if (rawPart is! Map) {
      throw OpenAiHttpException.invalidRequest(
        'Message content parts must be objects.',
        param: 'messages.content',
      );
    }

    final part = Map<String, dynamic>.from(rawPart);
    final type = part['type'];
    if (type is! String) {
      throw OpenAiHttpException.invalidRequest(
        'Content part requires a `type` field.',
        param: 'messages.content.type',
      );
    }

    switch (type) {
      case 'text':
      case 'input_text':
        final text = part['text'];
        if (text is! String) {
          throw OpenAiHttpException.invalidRequest(
            'Text content part must include a string `text` field.',
            param: 'messages.content.text',
          );
        }
        parts.add(LlamaTextContent(text));
        break;
      default:
        throw OpenAiHttpException.invalidRequest(
          'Unsupported content part type `$type` for role `${role.name}`.',
          param: 'messages.content.type',
        );
    }
  }

  return parts;
}
