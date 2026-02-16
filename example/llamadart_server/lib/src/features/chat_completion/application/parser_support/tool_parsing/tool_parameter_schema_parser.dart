import 'package:llamadart/llamadart.dart';

import '../../../../shared/openai_http_exception.dart';
import 'tool_parameter_type_handlers.dart';

List<ToolParam> parseToolParameters(Object? raw) {
  if (raw == null) {
    return const <ToolParam>[];
  }

  if (raw is! Map) {
    throw OpenAiHttpException.invalidRequest(
      '`tools[].function.parameters` must be an object.',
      param: 'tools.function.parameters',
    );
  }

  final schema = Map<String, dynamic>.from(raw);
  final type = schema['type'];
  if (type != null && type != 'object') {
    throw OpenAiHttpException.invalidRequest(
      'Tool parameter schema root must use `type = "object"`.',
      param: 'tools.function.parameters.type',
    );
  }

  final propertiesRaw = schema['properties'];
  if (propertiesRaw == null) {
    return const <ToolParam>[];
  }

  if (propertiesRaw is! Map) {
    throw OpenAiHttpException.invalidRequest(
      '`tools[].function.parameters.properties` must be an object.',
      param: 'tools.function.parameters.properties',
    );
  }

  final requiredSet = parseRequiredStringSet(
    schema['required'],
    param: 'tools.function.parameters.required',
  );
  final properties = Map<String, dynamic>.from(propertiesRaw);

  return properties.entries
      .map((MapEntry<String, dynamic> entry) {
        final fieldSchema = entry.value;
        if (fieldSchema is! Map) {
          throw OpenAiHttpException.invalidRequest(
            'Each property schema must be an object.',
            param: 'tools.function.parameters.properties.${entry.key}',
          );
        }

        return mapSchemaToToolParam(
          entry.key,
          Map<String, dynamic>.from(fieldSchema),
          required: requiredSet.contains(entry.key),
        );
      })
      .toList(growable: false);
}
