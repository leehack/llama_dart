import 'package:llamadart/llamadart.dart';

import '../../../../shared/openai_http_exception.dart';

typedef _ToolParamTypeHandler =
    ToolParam Function(
      String name,
      Map<String, dynamic> schema, {
      required bool required,
    });

final Map<String, _ToolParamTypeHandler> _typeHandlers =
    <String, _ToolParamTypeHandler>{
      'string': _buildStringParam,
      'integer': _buildIntegerParam,
      'number': _buildNumberParam,
      'boolean': _buildBooleanParam,
      'array': _buildArrayParam,
      'object': _buildObjectParam,
    };

ToolParam mapSchemaToToolParam(
  String name,
  Map<String, dynamic> schema, {
  required bool required,
}) {
  final description = schema['description'] as String?;
  final enumValues = schema['enum'];

  if (enumValues is List &&
      enumValues.every((Object? value) => value is String)) {
    return ToolParam.enumType(
      name,
      values: enumValues.cast<String>(),
      description: description,
      required: required,
    );
  }

  final type = schema['type'];
  if (type is String) {
    final handler = _typeHandlers[type];
    if (handler != null) {
      return handler(name, schema, required: required);
    }
  }

  return ToolParam.string(name, description: description, required: required);
}

Set<String> parseRequiredStringSet(Object? raw, {required String param}) {
  if (raw == null) {
    return const <String>{};
  }

  if (raw is List && raw.every((Object? value) => value is String)) {
    return raw.cast<String>().toSet();
  }

  throw OpenAiHttpException.invalidRequest(
    'Required field lists must contain only strings.',
    param: param,
  );
}

ToolParam _buildStringParam(
  String name,
  Map<String, dynamic> schema, {
  required bool required,
}) {
  return ToolParam.string(
    name,
    description: schema['description'] as String?,
    required: required,
  );
}

ToolParam _buildIntegerParam(
  String name,
  Map<String, dynamic> schema, {
  required bool required,
}) {
  return ToolParam.integer(
    name,
    description: schema['description'] as String?,
    required: required,
  );
}

ToolParam _buildNumberParam(
  String name,
  Map<String, dynamic> schema, {
  required bool required,
}) {
  return ToolParam.number(
    name,
    description: schema['description'] as String?,
    required: required,
  );
}

ToolParam _buildBooleanParam(
  String name,
  Map<String, dynamic> schema, {
  required bool required,
}) {
  return ToolParam.boolean(
    name,
    description: schema['description'] as String?,
    required: required,
  );
}

ToolParam _buildArrayParam(
  String name,
  Map<String, dynamic> schema, {
  required bool required,
}) {
  final itemsRaw = schema['items'];
  final itemType = itemsRaw is Map
      ? mapSchemaToToolParam(
          '${name}_item',
          Map<String, dynamic>.from(itemsRaw),
          required: false,
        )
      : ToolParam.string('${name}_item');

  return ToolParam.array(
    name,
    itemType: itemType,
    description: schema['description'] as String?,
    required: required,
  );
}

ToolParam _buildObjectParam(
  String name,
  Map<String, dynamic> schema, {
  required bool required,
}) {
  final nestedPropertiesRaw = schema['properties'];
  final nestedRequired = parseRequiredStringSet(
    schema['required'],
    param: 'tools.function.parameters.required',
  );

  final nestedParams = <ToolParam>[];
  if (nestedPropertiesRaw is Map) {
    final nestedProperties = Map<String, dynamic>.from(nestedPropertiesRaw);

    for (final entry in nestedProperties.entries) {
      final nestedSchema = entry.value;
      if (nestedSchema is Map) {
        nestedParams.add(
          mapSchemaToToolParam(
            entry.key,
            Map<String, dynamic>.from(nestedSchema),
            required: nestedRequired.contains(entry.key),
          ),
        );
      }
    }
  }

  return ToolParam.object(
    name,
    properties: nestedParams,
    description: schema['description'] as String?,
    required: required,
  );
}
