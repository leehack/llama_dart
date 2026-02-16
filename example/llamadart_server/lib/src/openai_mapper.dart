import 'dart:convert';

import 'package:llamadart/llamadart.dart';

import 'openai_error.dart';

/// Parsed and validated request payload for `/v1/chat/completions`.
class OpenAiChatCompletionRequest {
  /// Model ID requested by the client.
  final String model;

  /// Conversation messages converted to llamadart messages.
  final List<LlamaChatMessage> messages;

  /// Generation controls mapped from OpenAI request fields.
  final GenerationParams params;

  /// Whether SSE streaming mode is enabled.
  final bool stream;

  /// Optional tool definitions included in the request.
  final List<ToolDefinition>? tools;

  /// Optional tool choice behavior.
  final ToolChoice? toolChoice;

  /// Creates a parsed request model.
  const OpenAiChatCompletionRequest({
    required this.model,
    required this.messages,
    required this.params,
    required this.stream,
    this.tools,
    this.toolChoice,
  });
}

/// Invokes one server-side tool by name and arguments.
typedef OpenAiToolInvoker =
    Future<Object?> Function(String toolName, Map<String, dynamic> arguments);

/// Parsed tool-call payload emitted by one completion turn.
class OpenAiToolCallRecord {
  /// Tool call index in emitted order.
  final int index;

  /// Tool call id.
  final String id;

  /// Tool call type (usually `function`).
  final String type;

  /// Tool function name.
  final String name;

  /// Raw JSON arguments string.
  final String argumentsRaw;

  /// Parsed argument object when valid JSON object, else empty map.
  final Map<String, dynamic> arguments;

  /// Creates an immutable tool-call record.
  const OpenAiToolCallRecord({
    required this.index,
    required this.id,
    required this.type,
    required this.name,
    required this.argumentsRaw,
    required this.arguments,
  });

  /// Converts this record into OpenAI-compatible `tool_calls` JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'function': {'name': name, 'arguments': argumentsRaw},
    };
  }
}

/// Parses and validates an OpenAI chat completion request body.
OpenAiChatCompletionRequest parseChatCompletionRequest(
  Map<String, dynamic> json, {
  required String configuredModelId,
  OpenAiToolInvoker? toolInvoker,
}) {
  final model = json['model'];
  if (model is! String || model.trim().isEmpty) {
    throw OpenAiHttpException.invalidRequest(
      'Missing required `model` field.',
      param: 'model',
    );
  }

  if (model != configuredModelId) {
    throw OpenAiHttpException.modelNotFound(model);
  }

  final n = _readIntField(json['n'], 'n');
  if (n != null && n != 1) {
    throw OpenAiHttpException.invalidRequest(
      'Only `n = 1` is supported in this example server.',
      param: 'n',
    );
  }

  final stream = _readBoolField(json['stream'], 'stream') ?? false;

  final messagesRaw = json['messages'];
  if (messagesRaw is! List || messagesRaw.isEmpty) {
    throw OpenAiHttpException.invalidRequest(
      '`messages` must be a non-empty array.',
      param: 'messages',
    );
  }

  final messages = messagesRaw
      .map((Object? raw) => _parseMessage(raw))
      .toList(growable: false);

  final tools = _parseTools(json['tools'], toolInvoker: toolInvoker);
  final toolChoice = _parseToolChoice(json['tool_choice'], tools);

  if (toolChoice == ToolChoice.required && (tools == null || tools.isEmpty)) {
    throw OpenAiHttpException.invalidRequest(
      '`tool_choice = "required"` requires `tools` to be provided.',
      param: 'tool_choice',
    );
  }

  final maxTokens = _readIntField(json['max_tokens'], 'max_tokens');
  final temperature = _readDoubleField(json['temperature'], 'temperature');
  final topP = _readDoubleField(json['top_p'], 'top_p');
  final seed = _readIntField(json['seed'], 'seed');
  final stops = _parseStopSequences(json['stop']);

  var params = const GenerationParams(penalty: 1.0, topP: 0.95, minP: 0.05);
  if (maxTokens != null) {
    params = params.copyWith(maxTokens: maxTokens);
  }
  if (temperature != null) {
    params = params.copyWith(temp: temperature);
  }
  if (topP != null) {
    params = params.copyWith(topP: topP);
  }
  if (seed != null) {
    params = params.copyWith(seed: seed);
  }
  if (stops.isNotEmpty) {
    params = params.copyWith(stopSequences: stops);
  }

  return OpenAiChatCompletionRequest(
    model: model,
    messages: messages,
    params: params,
    stream: stream,
    tools: tools,
    toolChoice: toolChoice,
  );
}

/// Creates a response payload for `GET /v1/models`.
Map<String, dynamic> toOpenAiModelListResponse({
  required String modelId,
  required int created,
  String ownedBy = 'llamadart',
}) {
  return {
    'object': 'list',
    'data': [
      {
        'id': modelId,
        'object': 'model',
        'created': created,
        'owned_by': ownedBy,
      },
    ],
  };
}

/// Converts a llamadart chunk into OpenAI-compatible chunk JSON.
Map<String, dynamic> toOpenAiChatCompletionChunk(
  LlamaCompletionChunk chunk, {
  required String model,
  required bool includeRole,
}) {
  if (chunk.choices.isEmpty) {
    throw OpenAiHttpException.server(
      'Received a completion chunk with no choices.',
    );
  }

  final choice = chunk.choices.first;
  final delta = <String, dynamic>{};

  if (includeRole) {
    delta['role'] = 'assistant';
  }

  final content = choice.delta.content;
  if (content != null && content.isNotEmpty) {
    delta['content'] = content;
  }

  final toolCalls = choice.delta.toolCalls;
  if (toolCalls != null && toolCalls.isNotEmpty) {
    delta['tool_calls'] = toolCalls
        .map((LlamaCompletionChunkToolCall call) => _toolCallChunkToJson(call))
        .toList(growable: false);
  }

  final reasoning = choice.delta.thinking;
  if (reasoning != null && reasoning.isNotEmpty) {
    delta['reasoning_content'] = reasoning;
  }

  return {
    'id': chunk.id,
    'object': 'chat.completion.chunk',
    'created': chunk.created,
    'model': model,
    'choices': [
      {
        'index': choice.index,
        'delta': delta,
        'finish_reason': choice.finishReason,
      },
    ],
  };
}

/// Accumulates streaming chunks into a single non-stream OpenAI response.
class OpenAiChatCompletionAccumulator {
  final StringBuffer _content = StringBuffer();
  final StringBuffer _reasoning = StringBuffer();
  final Map<int, _ToolCallAccumulator> _toolCallsByIndex =
      <int, _ToolCallAccumulator>{};

  String _finishReason = 'stop';

  /// Adds one streaming chunk to this accumulator.
  void addChunk(LlamaCompletionChunk chunk) {
    if (chunk.choices.isEmpty) {
      return;
    }

    final choice = chunk.choices.first;

    final content = choice.delta.content;
    if (content != null) {
      _content.write(content);
    }

    final reasoning = choice.delta.thinking;
    if (reasoning != null) {
      _reasoning.write(reasoning);
    }

    final toolCalls = choice.delta.toolCalls;
    if (toolCalls != null) {
      for (final call in toolCalls) {
        final accumulator = _toolCallsByIndex.putIfAbsent(
          call.index,
          () => _ToolCallAccumulator(call.index),
        );

        accumulator.add(call);
      }
    }

    if (choice.finishReason != null) {
      _finishReason = choice.finishReason!;
    }
  }

  /// Accumulated assistant content.
  String get content => _content.toString();

  /// Accumulated assistant reasoning text.
  String get reasoningContent => _reasoning.toString();

  /// Parsed tool calls emitted in this completion.
  List<OpenAiToolCallRecord> get toolCalls {
    final accumulators = _toolCallsByIndex.values.toList(growable: false)
      ..sort((a, b) => a.index.compareTo(b.index));
    return accumulators
        .map((accumulator) => accumulator.toRecord())
        .toList(growable: false);
  }

  /// Builds a full OpenAI completion response JSON object.
  Map<String, dynamic> toResponseJson({
    required String id,
    required int created,
    required String model,
    required int promptTokens,
    required int completionTokens,
  }) {
    final toolCallJson = toolCalls
        .map((record) => record.toJson())
        .toList(growable: false);

    final hasToolCalls = toolCallJson.isNotEmpty;
    final reasoning = reasoningContent;

    final message = <String, dynamic>{
      'role': 'assistant',
      'content': hasToolCalls ? null : content,
      if (reasoning.isNotEmpty) 'reasoning_content': reasoning,
      if (hasToolCalls) 'tool_calls': toolCallJson,
    };

    return {
      'id': id,
      'object': 'chat.completion',
      'created': created,
      'model': model,
      'choices': [
        {
          'index': 0,
          'message': message,
          'finish_reason': hasToolCalls ? 'tool_calls' : _finishReason,
        },
      ],
      'usage': {
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'total_tokens': promptTokens + completionTokens,
      },
    };
  }
}

/// Encodes one SSE data payload line.
String encodeSseData(Map<String, dynamic> payload) {
  return 'data: ${jsonEncode(payload)}\n\n';
}

/// Encodes the SSE completion sentinel.
String encodeSseDone() {
  return 'data: [DONE]\n\n';
}

LlamaChatMessage _parseMessage(Object? raw) {
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

  final role = _parseRole(roleRaw);

  if (role == LlamaChatRole.tool) {
    return _parseToolMessage(message);
  }

  final parts = _parseContentParts(message['content'], role);

  if (role == LlamaChatRole.assistant) {
    final reasoning = _readContentAsString(message['reasoning_content']).trim();
    if (reasoning.isNotEmpty) {
      parts.add(LlamaThinkingContent(reasoning));
    }

    final assistantToolCalls = _parseAssistantToolCalls(message['tool_calls']);
    parts.addAll(assistantToolCalls);
  }

  if (parts.isEmpty) {
    if (role == LlamaChatRole.assistant) {
      parts.add(const LlamaTextContent(''));
    } else {
      throw OpenAiHttpException.invalidRequest(
        'Message content cannot be empty for role `${role.name}`.',
        param: 'messages.content',
      );
    }
  }

  return LlamaChatMessage.withContent(role: role, content: parts);
}

LlamaChatMessage _parseToolMessage(Map<String, dynamic> message) {
  final toolCallId = message['tool_call_id'];
  if (toolCallId != null && toolCallId is! String) {
    throw OpenAiHttpException.invalidRequest(
      '`tool_call_id` must be a string.',
      param: 'messages.tool_call_id',
    );
  }

  final contentRaw = message['content'];
  final content = _readContentAsString(contentRaw);

  final nameRaw = message['name'];
  final name = nameRaw is String && nameRaw.isNotEmpty ? nameRaw : 'tool';

  return LlamaChatMessage.withContent(
    role: LlamaChatRole.tool,
    content: [
      LlamaToolResultContent(
        id: toolCallId as String?,
        name: name,
        result: content,
      ),
    ],
  );
}

List<LlamaContentPart> _parseContentParts(Object? content, LlamaChatRole role) {
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

List<LlamaToolCallContent> _parseAssistantToolCalls(Object? rawToolCalls) {
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

    final arguments = _parseToolArguments(functionMap['arguments']);

    result.add(
      LlamaToolCallContent(
        id: call['id'] as String?,
        name: name,
        arguments: arguments,
        rawJson: jsonEncode(call),
      ),
    );
  }

  return result;
}

LlamaChatRole _parseRole(String role) {
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

Map<String, dynamic> _parseToolArguments(Object? rawArguments) {
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

String _readContentAsString(Object? content) {
  if (content == null) {
    return '';
  }

  if (content is String) {
    return content;
  }

  return jsonEncode(content);
}

List<ToolDefinition>? _parseTools(
  Object? rawTools, {
  OpenAiToolInvoker? toolInvoker,
}) {
  if (rawTools == null) {
    return null;
  }

  if (rawTools is! List) {
    throw OpenAiHttpException.invalidRequest(
      '`tools` must be an array.',
      param: 'tools',
    );
  }

  if (rawTools.isEmpty) {
    return null;
  }

  final tools = <ToolDefinition>[];

  for (final raw in rawTools) {
    if (raw is! Map) {
      throw OpenAiHttpException.invalidRequest(
        'Each tool must be an object.',
        param: 'tools',
      );
    }

    final tool = Map<String, dynamic>.from(raw);
    final type = tool['type'];
    if (type != 'function') {
      throw OpenAiHttpException.invalidRequest(
        'Only `type = "function"` tools are supported.',
        param: 'tools.type',
      );
    }

    final function = tool['function'];
    if (function is! Map) {
      throw OpenAiHttpException.invalidRequest(
        'Tool requires a `function` object.',
        param: 'tools.function',
      );
    }

    final functionMap = Map<String, dynamic>.from(function);

    final name = functionMap['name'];
    if (name is! String || name.isEmpty) {
      throw OpenAiHttpException.invalidRequest(
        'Tool function name must be a non-empty string.',
        param: 'tools.function.name',
      );
    }

    final description = functionMap['description'];
    if (description != null && description is! String) {
      throw OpenAiHttpException.invalidRequest(
        'Tool function description must be a string.',
        param: 'tools.function.description',
      );
    }

    final parametersRaw = functionMap['parameters'];
    final parameters = _parseToolParameters(parametersRaw);

    tools.add(
      ToolDefinition(
        name: name,
        description: description as String? ?? '',
        parameters: parameters,
        handler: (ToolParams params) async {
          if (toolInvoker == null) {
            return 'Tool execution is disabled in this server example.';
          }

          return toolInvoker(name, params.raw);
        },
      ),
    );
  }

  return tools;
}

List<ToolParam> _parseToolParameters(Object? raw) {
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

  final requiredSet = _toStringSet(schema['required']);
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

        return _schemaToToolParam(
          entry.key,
          Map<String, dynamic>.from(fieldSchema),
          required: requiredSet.contains(entry.key),
        );
      })
      .toList(growable: false);
}

ToolParam _schemaToToolParam(
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

  switch (type) {
    case 'string':
      return ToolParam.string(
        name,
        description: description,
        required: required,
      );
    case 'integer':
      return ToolParam.integer(
        name,
        description: description,
        required: required,
      );
    case 'number':
      return ToolParam.number(
        name,
        description: description,
        required: required,
      );
    case 'boolean':
      return ToolParam.boolean(
        name,
        description: description,
        required: required,
      );
    case 'array':
      final itemsRaw = schema['items'];
      final itemType = itemsRaw is Map
          ? _schemaToToolParam(
              '${name}_item',
              Map<String, dynamic>.from(itemsRaw),
              required: false,
            )
          : ToolParam.string('${name}_item');

      return ToolParam.array(
        name,
        itemType: itemType,
        description: description,
        required: required,
      );
    case 'object':
      final nestedPropertiesRaw = schema['properties'];
      final nestedRequired = _toStringSet(schema['required']);

      final nestedParams = <ToolParam>[];
      if (nestedPropertiesRaw is Map) {
        final nestedProperties = Map<String, dynamic>.from(nestedPropertiesRaw);

        for (final entry in nestedProperties.entries) {
          final nestedSchema = entry.value;
          if (nestedSchema is Map) {
            nestedParams.add(
              _schemaToToolParam(
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
        description: description,
        required: required,
      );
    default:
      return ToolParam.string(
        name,
        description: description,
        required: required,
      );
  }
}

ToolChoice? _parseToolChoice(Object? raw, List<ToolDefinition>? tools) {
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

List<String> _parseStopSequences(Object? raw) {
  if (raw == null) {
    return const <String>[];
  }

  if (raw is String) {
    return <String>[raw];
  }

  if (raw is List && raw.every((Object? value) => value is String)) {
    return raw.cast<String>();
  }

  throw OpenAiHttpException.invalidRequest(
    '`stop` must be a string or a string array.',
    param: 'stop',
  );
}

int? _readIntField(Object? raw, String fieldName) {
  if (raw == null) {
    return null;
  }

  if (raw is int) {
    return raw;
  }

  if (raw is num && raw == raw.toInt()) {
    return raw.toInt();
  }

  throw OpenAiHttpException.invalidRequest(
    '`$fieldName` must be an integer.',
    param: fieldName,
  );
}

double? _readDoubleField(Object? raw, String fieldName) {
  if (raw == null) {
    return null;
  }

  if (raw is num) {
    return raw.toDouble();
  }

  throw OpenAiHttpException.invalidRequest(
    '`$fieldName` must be a number.',
    param: fieldName,
  );
}

bool? _readBoolField(Object? raw, String fieldName) {
  if (raw == null) {
    return null;
  }

  if (raw is bool) {
    return raw;
  }

  throw OpenAiHttpException.invalidRequest(
    '`$fieldName` must be a boolean.',
    param: fieldName,
  );
}

Set<String> _toStringSet(Object? raw) {
  if (raw == null) {
    return const <String>{};
  }

  if (raw is List && raw.every((Object? value) => value is String)) {
    return raw.cast<String>().toSet();
  }

  throw OpenAiHttpException.invalidRequest(
    'Required field lists must contain only strings.',
    param: 'tools.function.parameters.required',
  );
}

Map<String, dynamic> _toolCallChunkToJson(LlamaCompletionChunkToolCall call) {
  final function = <String, dynamic>{};
  if (call.function?.name != null) {
    function['name'] = call.function!.name;
  }
  if (call.function?.arguments != null) {
    function['arguments'] = call.function!.arguments;
  }

  return {
    'index': call.index,
    if (call.id != null) 'id': call.id,
    if (call.type != null) 'type': call.type,
    if (function.isNotEmpty) 'function': function,
  };
}

class _ToolCallAccumulator {
  final int index;

  String? id;
  String? type;
  String? name;
  final StringBuffer arguments = StringBuffer();

  _ToolCallAccumulator(this.index);

  void add(LlamaCompletionChunkToolCall call) {
    id ??= call.id;
    type ??= call.type;

    final function = call.function;
    if (function?.name != null) {
      name = function!.name;
    }
    if (function?.arguments != null) {
      arguments.write(function!.arguments);
    }
  }

  OpenAiToolCallRecord toRecord() {
    final rawArguments = arguments.toString();
    return OpenAiToolCallRecord(
      index: index,
      id: id ?? 'call_$index',
      type: type ?? 'function',
      name: name ?? '',
      argumentsRaw: rawArguments,
      arguments: _decodeArgumentsObject(rawArguments),
    );
  }

  Map<String, dynamic> toJson() {
    return toRecord().toJson();
  }
}

Map<String, dynamic> _decodeArgumentsObject(String rawArguments) {
  final trimmed = rawArguments.trim();
  if (trimmed.isEmpty) {
    return const <String, dynamic>{};
  }

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    // Keep fallback empty map when the model emits non-JSON arguments.
  }

  return const <String, dynamic>{};
}
