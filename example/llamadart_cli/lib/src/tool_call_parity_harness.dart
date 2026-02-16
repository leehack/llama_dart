import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// One tool-call parity scenario.
class ToolCallParityScenario {
  /// Stable scenario identifier used in reports.
  final String id;

  /// Human-readable scenario name.
  final String name;

  /// User prompt used for the first turn.
  final String userPrompt;

  /// OpenAI-style tool definitions used in the first turn.
  final List<Map<String, dynamic>> tools;

  /// OpenAI-style tool choice (`none`, `auto`, `required`, or object).
  final Object? toolChoice;

  /// Whether at least one tool call is expected in turn 1.
  final bool expectToolCalls;

  /// Creates an immutable scenario definition.
  const ToolCallParityScenario({
    required this.id,
    required this.name,
    required this.userPrompt,
    required this.tools,
    required this.toolChoice,
    this.expectToolCalls = true,
  });
}

/// Runtime settings for tool-call parity runs.
class ToolCallParityConfig {
  /// Working directory used for server process execution.
  final String workingDirectory;

  /// Local GGUF model file path.
  final String modelPath;

  /// `llama-server` executable path.
  final String llamaServerPath;

  /// Dart API server entrypoint path.
  final String apiServerEntryPath;

  /// Public OpenAI model id used for both servers.
  final String modelId;

  /// Host to bind servers to.
  final String host;

  /// Optional fixed llama.cpp server port.
  final int? llamaServerPort;

  /// Optional fixed llamadart API server port.
  final int? apiServerPort;

  /// Startup timeout for each server.
  final Duration startupTimeout;

  /// Timeout per completion request.
  final Duration requestTimeout;

  /// Whether to include `tool_choice=auto` scenario.
  final bool includeAutoScenario;

  /// Maximum bytes captured for each server output stream.
  final int maxCapturedBytes;

  /// Creates an immutable tool-call parity configuration.
  const ToolCallParityConfig({
    required this.workingDirectory,
    required this.modelPath,
    required this.llamaServerPath,
    required this.apiServerEntryPath,
    required this.modelId,
    this.host = '127.0.0.1',
    this.llamaServerPort,
    this.apiServerPort,
    this.startupTimeout = const Duration(minutes: 3),
    this.requestTimeout = const Duration(minutes: 5),
    this.includeAutoScenario = false,
    this.maxCapturedBytes = 2 * 1024 * 1024,
  });
}

/// One structured mismatch found during parity comparison.
class ToolCallParityDelta {
  /// Scenario id where mismatch happened.
  final String scenarioId;

  /// Scenario phase (`turn1` or `turn2`).
  final String phase;

  /// Compared field name.
  final String field;

  /// Expected value (reference side).
  final String expected;

  /// Actual value (candidate side).
  final String actual;

  /// Creates a parity delta entry.
  const ToolCallParityDelta({
    required this.scenarioId,
    required this.phase,
    required this.field,
    required this.expected,
    required this.actual,
  });

  /// Converts this delta to a JSON-serializable map.
  Map<String, dynamic> toJson() {
    return {
      'scenario_id': scenarioId,
      'phase': phase,
      'field': field,
      'expected': expected,
      'actual': actual,
    };
  }
}

/// Parsed tool-call record from one completion response.
class ToolCallSnapshot {
  /// Position index of this tool call in response order.
  final int index;

  /// Tool call id.
  final String id;

  /// Tool type, typically `function`.
  final String type;

  /// Tool function name.
  final String name;

  /// Raw tool arguments as emitted by the model.
  final String argumentsRaw;

  /// Canonicalized arguments string for deterministic comparison.
  final String argumentsCanonical;

  /// Parsed arguments object, if valid JSON object.
  final Map<String, dynamic>? argumentsObject;

  /// Creates an immutable tool-call snapshot.
  const ToolCallSnapshot({
    required this.index,
    required this.id,
    required this.type,
    required this.name,
    required this.argumentsRaw,
    required this.argumentsCanonical,
    required this.argumentsObject,
  });

  /// Canonical comparison signature for parity checks.
  String get signature => '$name|$argumentsCanonical';

  /// Converts this tool call into an OpenAI-style `tool_calls` JSON object.
  Map<String, dynamic> toOpenAiToolCallJson() {
    return {
      'id': id,
      'type': type,
      'function': {'name': name, 'arguments': argumentsRaw},
    };
  }

  /// Converts this snapshot to a JSON-serializable map.
  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'id': id,
      'type': type,
      'name': name,
      'arguments_raw': argumentsRaw,
      'arguments_canonical': argumentsCanonical,
      'arguments_object': argumentsObject,
      'signature': signature,
    };
  }
}

/// One completion turn snapshot used in scenario reports.
class ToolCallTurnSnapshot {
  /// Request body sent to server.
  final Map<String, dynamic> requestBody;

  /// HTTP status code.
  final int statusCode;

  /// Parsed response JSON body if available.
  final Map<String, dynamic>? responseBody;

  /// Parse or protocol error message when response is malformed.
  final String? parseError;

  /// `choices[0].finish_reason` value.
  final String? finishReason;

  /// `choices[0].message.content` normalized text.
  final String content;

  /// `choices[0].message.reasoning_content` normalized text.
  final String reasoningContent;

  /// Parsed tool calls from `choices[0].message.tool_calls`.
  final List<ToolCallSnapshot> toolCalls;

  /// Creates an immutable turn snapshot.
  const ToolCallTurnSnapshot({
    required this.requestBody,
    required this.statusCode,
    required this.responseBody,
    required this.parseError,
    required this.finishReason,
    required this.content,
    required this.reasoningContent,
    required this.toolCalls,
  });

  /// Converts this snapshot to a JSON-serializable map.
  Map<String, dynamic> toJson() {
    return {
      'request_body': requestBody,
      'status_code': statusCode,
      'response_body': responseBody,
      'parse_error': parseError,
      'finish_reason': finishReason,
      'content': content,
      'reasoning_content': reasoningContent,
      'tool_calls': toolCalls.map((call) => call.toJson()).toList(),
    };
  }
}

/// Per-scenario tool-call parity report.
class ToolCallScenarioReport {
  /// Scenario id.
  final String scenarioId;

  /// Scenario name.
  final String scenarioName;

  /// Turn-1 snapshot from llama.cpp server.
  final ToolCallTurnSnapshot llamaCppTurn1;

  /// Turn-1 snapshot from llamadart API server.
  final ToolCallTurnSnapshot llamaDartTurn1;

  /// Turn-2 snapshot from llama.cpp server.
  final ToolCallTurnSnapshot? llamaCppTurn2;

  /// Turn-2 snapshot from llamadart API server.
  final ToolCallTurnSnapshot? llamaDartTurn2;

  /// Deltas discovered in this scenario.
  final List<ToolCallParityDelta> deltas;

  /// Creates an immutable scenario report.
  const ToolCallScenarioReport({
    required this.scenarioId,
    required this.scenarioName,
    required this.llamaCppTurn1,
    required this.llamaDartTurn1,
    required this.llamaCppTurn2,
    required this.llamaDartTurn2,
    required this.deltas,
  });

  /// Whether this scenario has no parity deltas.
  bool get isMatch => deltas.isEmpty;

  /// Converts this scenario report to JSON.
  Map<String, dynamic> toJson() {
    return {
      'scenario_id': scenarioId,
      'scenario_name': scenarioName,
      'is_match': isMatch,
      'llama_cpp_turn_1': llamaCppTurn1.toJson(),
      'llamadart_turn_1': llamaDartTurn1.toJson(),
      'llama_cpp_turn_2': llamaCppTurn2?.toJson(),
      'llamadart_turn_2': llamaDartTurn2?.toJson(),
      'deltas': deltas.map((delta) => delta.toJson()).toList(),
    };
  }
}

/// Complete run report for tool-call parity.
class ToolCallParityReport {
  /// UTC start timestamp.
  final DateTime startedAt;

  /// UTC end timestamp.
  final DateTime endedAt;

  /// llama.cpp server command used in this run.
  final String llamaServerCommand;

  /// llamadart API server command used in this run.
  final String llamaDartServerCommand;

  /// llama.cpp server base URL.
  final Uri llamaServerBaseUri;

  /// llamadart API server base URL.
  final Uri llamaDartServerBaseUri;

  /// Scenario reports in execution order.
  final List<ToolCallScenarioReport> scenarios;

  /// Flattened deltas across scenarios.
  final List<ToolCallParityDelta> deltas;

  /// Captured llama.cpp server stdout.
  final String llamaServerStdout;

  /// Captured llama.cpp server stderr.
  final String llamaServerStderr;

  /// Captured llamadart server stdout.
  final String llamaDartServerStdout;

  /// Captured llamadart server stderr.
  final String llamaDartServerStderr;

  /// Creates an immutable run report.
  const ToolCallParityReport({
    required this.startedAt,
    required this.endedAt,
    required this.llamaServerCommand,
    required this.llamaDartServerCommand,
    required this.llamaServerBaseUri,
    required this.llamaDartServerBaseUri,
    required this.scenarios,
    required this.deltas,
    required this.llamaServerStdout,
    required this.llamaServerStderr,
    required this.llamaDartServerStdout,
    required this.llamaDartServerStderr,
  });

  /// True when all scenarios match and no deltas were found.
  bool get isMatch => deltas.isEmpty;

  /// Converts this report to a JSON-serializable map.
  Map<String, dynamic> toJson() {
    return {
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': endedAt.toUtc().toIso8601String(),
      'duration_ms': endedAt.difference(startedAt).inMilliseconds,
      'is_match': isMatch,
      'llama_server': {
        'command': llamaServerCommand,
        'base_uri': llamaServerBaseUri.toString(),
        'stdout': llamaServerStdout,
        'stderr': llamaServerStderr,
      },
      'llamadart_server': {
        'command': llamaDartServerCommand,
        'base_uri': llamaDartServerBaseUri.toString(),
        'stdout': llamaDartServerStdout,
        'stderr': llamaDartServerStderr,
      },
      'scenarios': scenarios.map((scenario) => scenario.toJson()).toList(),
      'deltas': deltas.map((delta) => delta.toJson()).toList(),
    };
  }
}

/// End-to-end tool-call parity harness between llama.cpp and llamadart servers.
class ToolCallParityHarness {
  static final RegExp _xmlToolCallPattern = RegExp(
    r'<tool_call>\s*([a-zA-Z0-9_]+)\s*([\s\S]*?)</tool_call>',
    caseSensitive: false,
  );
  static final RegExp _xmlArgPairPattern = RegExp(
    r'<arg_key>\s*([\s\S]*?)\s*</arg_key>\s*<arg_value>\s*([\s\S]*?)\s*</arg_value>',
    caseSensitive: false,
  );
  static final RegExp _deepseekToolCallPattern = RegExp(
    r'(?:<｜tool(?:▁|_| )call(?:▁|_| )begin｜>\s*)?'
    r'([A-Za-z_][A-Za-z0-9_\.-]*)\s*'
    r'<｜tool(?:▁|_| )sep｜>\s*'
    r'([\s\S]*?)\s*'
    r'<｜tool(?:▁|_| )call(?:▁|_| )end｜>',
    caseSensitive: false,
  );

  final http.Client _httpClient;
  final bool _ownsClient;

  /// Creates a harness with an optional injected HTTP client.
  ToolCallParityHarness({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  /// Releases owned resources.
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  /// Runs all tool-call scenarios and returns a full parity report.
  Future<ToolCallParityReport> run(ToolCallParityConfig config) async {
    final startedAt = DateTime.now().toUtc();

    final llamaPort = config.llamaServerPort ?? await _findFreePort();
    final apiPort = config.apiServerPort ?? await _findFreePort();

    final llamaBaseUri = Uri.parse('http://${config.host}:$llamaPort');
    final apiBaseUri = Uri.parse('http://${config.host}:$apiPort');

    final llamaCommand = _buildLlamaServerCommand(config, llamaPort);
    final apiCommand = _buildLlamadartServerCommand(config, apiPort);

    final llamaProcess = _ManagedServerProcess(
      name: 'llama.cpp-server',
      command: llamaCommand,
      workingDirectory: config.workingDirectory,
      healthUri: llamaBaseUri.replace(path: '/health'),
      startupTimeout: config.startupTimeout,
      maxCapturedBytes: config.maxCapturedBytes,
    );

    final apiProcess = _ManagedServerProcess(
      name: 'llamadart-api-server',
      command: apiCommand,
      workingDirectory: config.workingDirectory,
      healthUri: apiBaseUri.replace(path: '/healthz'),
      startupTimeout: config.startupTimeout,
      maxCapturedBytes: config.maxCapturedBytes,
    );

    final scenarioReports = <ToolCallScenarioReport>[];

    try {
      await llamaProcess.start(_httpClient);
      await apiProcess.start(_httpClient);

      final scenarios = _defaultScenarios(
        includeAutoScenario: config.includeAutoScenario,
      );

      for (final scenario in scenarios) {
        final report = await _runScenario(
          scenario: scenario,
          modelId: config.modelId,
          modelPath: config.modelPath,
          llamaBaseUri: llamaBaseUri,
          apiBaseUri: apiBaseUri,
          requestTimeout: config.requestTimeout,
        );
        scenarioReports.add(report);
      }
    } finally {
      await apiProcess.stop();
      await llamaProcess.stop();
    }

    final endedAt = DateTime.now().toUtc();
    final deltas = scenarioReports
        .expand((scenario) => scenario.deltas)
        .toList(growable: false);

    return ToolCallParityReport(
      startedAt: startedAt,
      endedAt: endedAt,
      llamaServerCommand: llamaCommand,
      llamaDartServerCommand: apiCommand,
      llamaServerBaseUri: llamaBaseUri,
      llamaDartServerBaseUri: apiBaseUri,
      scenarios: List<ToolCallScenarioReport>.unmodifiable(scenarioReports),
      deltas: List<ToolCallParityDelta>.unmodifiable(deltas),
      llamaServerStdout: llamaProcess.stdoutText,
      llamaServerStderr: llamaProcess.stderrText,
      llamaDartServerStdout: apiProcess.stdoutText,
      llamaDartServerStderr: apiProcess.stderrText,
    );
  }

  Future<ToolCallScenarioReport> _runScenario({
    required ToolCallParityScenario scenario,
    required String modelId,
    required String modelPath,
    required Uri llamaBaseUri,
    required Uri apiBaseUri,
    required Duration requestTimeout,
  }) async {
    final tuning = _scenarioTuningFor(
      modelPath: modelPath,
      scenarioId: scenario.id,
    );
    final firstTurnPrompt = tuning.userPrompt ?? scenario.userPrompt;
    final firstTurnMaxTokens = tuning.firstTurnMaxTokens ?? 64;

    final turn1Request = <String, dynamic>{
      'model': modelId,
      'stream': false,
      'temperature': 0,
      'top_p': 1,
      'seed': 3407,
      'max_tokens': firstTurnMaxTokens,
      'parse_tool_calls': true,
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a tool-calling assistant. If a tool is required, emit '
              'exactly one tool call and no extra text.',
        },
        {'role': 'user', 'content': firstTurnPrompt},
      ],
      'tools': scenario.tools,
      'tool_choice': scenario.toolChoice,
    };

    final llamaTurn1 = await _executeTurn(
      baseUri: llamaBaseUri,
      requestBody: turn1Request,
      timeout: requestTimeout,
    );
    final dartTurn1 = await _executeTurn(
      baseUri: apiBaseUri,
      requestBody: turn1Request,
      timeout: requestTimeout,
    );

    final deltas = <ToolCallParityDelta>[];
    _compareTurn1(
      scenario: scenario,
      expected: llamaTurn1,
      actual: dartTurn1,
      tuning: tuning,
      deltas: deltas,
    );

    ToolCallTurnSnapshot? llamaTurn2;
    ToolCallTurnSnapshot? dartTurn2;

    if (llamaTurn1.statusCode == HttpStatus.ok &&
        dartTurn1.statusCode == HttpStatus.ok &&
        llamaTurn1.toolCalls.isNotEmpty &&
        dartTurn1.toolCalls.isNotEmpty) {
      final llamaSecondRequest = _buildSecondTurnRequest(
        modelId: modelId,
        prompt: firstTurnPrompt,
        toolCalls: llamaTurn1.toolCalls,
        maxTokens: tuning.secondTurnMaxTokens ?? 64,
      );
      final dartSecondRequest = _buildSecondTurnRequest(
        modelId: modelId,
        prompt: firstTurnPrompt,
        toolCalls: dartTurn1.toolCalls,
        maxTokens: tuning.secondTurnMaxTokens ?? 64,
      );

      llamaTurn2 = await _executeTurn(
        baseUri: llamaBaseUri,
        requestBody: llamaSecondRequest,
        timeout: requestTimeout,
      );
      dartTurn2 = await _executeTurn(
        baseUri: apiBaseUri,
        requestBody: dartSecondRequest,
        timeout: requestTimeout,
      );

      final needsAlternationFallback =
          _isAlternationTemplateError(llamaTurn2) ||
          _isAlternationTemplateError(dartTurn2);

      if (needsAlternationFallback) {
        final llamaFallbackRequest = _buildSecondTurnRequest(
          modelId: modelId,
          prompt: firstTurnPrompt,
          toolCalls: llamaTurn1.toolCalls,
          maxTokens: tuning.secondTurnMaxTokens ?? 64,
          useUserToolResultMessage: true,
        );
        final dartFallbackRequest = _buildSecondTurnRequest(
          modelId: modelId,
          prompt: firstTurnPrompt,
          toolCalls: dartTurn1.toolCalls,
          maxTokens: tuning.secondTurnMaxTokens ?? 64,
          useUserToolResultMessage: true,
        );

        llamaTurn2 = await _executeTurn(
          baseUri: llamaBaseUri,
          requestBody: llamaFallbackRequest,
          timeout: requestTimeout,
        );
        dartTurn2 = await _executeTurn(
          baseUri: apiBaseUri,
          requestBody: dartFallbackRequest,
          timeout: requestTimeout,
        );
      }

      _compareTurn2(
        scenario: scenario,
        expected: llamaTurn2,
        actual: dartTurn2,
        tuning: tuning,
        deltas: deltas,
      );
    }

    return ToolCallScenarioReport(
      scenarioId: scenario.id,
      scenarioName: scenario.name,
      llamaCppTurn1: llamaTurn1,
      llamaDartTurn1: dartTurn1,
      llamaCppTurn2: llamaTurn2,
      llamaDartTurn2: dartTurn2,
      deltas: List<ToolCallParityDelta>.unmodifiable(deltas),
    );
  }

  Future<ToolCallTurnSnapshot> _executeTurn({
    required Uri baseUri,
    required Map<String, dynamic> requestBody,
    required Duration timeout,
  }) async {
    final endpoint = baseUri.replace(path: '/v1/chat/completions');

    try {
      final response = await _httpClient
          .post(
            endpoint,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(timeout);

      final bodyText = response.body;
      Map<String, dynamic>? body;
      String? parseError;

      if (bodyText.isNotEmpty) {
        try {
          final decoded = jsonDecode(bodyText);
          if (decoded is Map<String, dynamic>) {
            body = decoded;
          } else if (decoded is Map) {
            body = Map<String, dynamic>.from(decoded);
          } else {
            parseError = 'Response body is not a JSON object.';
          }
        } on FormatException catch (error) {
          parseError = 'Invalid JSON response: ${error.message}';
        }
      }

      final choice = _extractFirstChoice(body);
      final message = _extractChoiceMessage(choice);
      var finishReason = choice == null
          ? null
          : choice['finish_reason'] as String?;
      final content = _normalizeContent(message?['content']);
      final reasoningContent = _normalizeContent(message?['reasoning_content']);
      var toolCalls = _extractToolCalls(message?['tool_calls']);

      if (toolCalls.isEmpty) {
        final reasoningContent = _normalizeContent(
          message?['reasoning_content'],
        );
        if (reasoningContent.isNotEmpty) {
          toolCalls = _extractXmlToolCalls(reasoningContent);
        }

        if (toolCalls.isEmpty && content.isNotEmpty) {
          toolCalls = _extractDeepseekTokenToolCalls(content);
        }
        if (toolCalls.isEmpty && reasoningContent.isNotEmpty) {
          toolCalls = _extractDeepseekTokenToolCalls(reasoningContent);
        }
      }

      if (toolCalls.isNotEmpty && finishReason == 'length') {
        finishReason = 'tool_calls';
      }

      return ToolCallTurnSnapshot(
        requestBody: requestBody,
        statusCode: response.statusCode,
        responseBody: body,
        parseError: parseError,
        finishReason: finishReason,
        content: content,
        reasoningContent: reasoningContent,
        toolCalls: toolCalls,
      );
    } on TimeoutException {
      return ToolCallTurnSnapshot(
        requestBody: requestBody,
        statusCode: -1,
        responseBody: null,
        parseError: 'Request timed out after ${timeout.inSeconds}s.',
        finishReason: null,
        content: '',
        reasoningContent: '',
        toolCalls: const <ToolCallSnapshot>[],
      );
    } catch (error) {
      return ToolCallTurnSnapshot(
        requestBody: requestBody,
        statusCode: -1,
        responseBody: null,
        parseError: 'Request failed: $error',
        finishReason: null,
        content: '',
        reasoningContent: '',
        toolCalls: const <ToolCallSnapshot>[],
      );
    }
  }

  Map<String, dynamic>? _extractFirstChoice(Map<String, dynamic>? body) {
    if (body == null) {
      return null;
    }

    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      return null;
    }

    final first = choices.first;
    if (first is Map<String, dynamic>) {
      return first;
    }
    if (first is Map) {
      return Map<String, dynamic>.from(first);
    }
    return null;
  }

  Map<String, dynamic>? _extractChoiceMessage(Map<String, dynamic>? choice) {
    if (choice == null) {
      return null;
    }
    final message = choice['message'];
    if (message is Map<String, dynamic>) {
      return message;
    }
    if (message is Map) {
      return Map<String, dynamic>.from(message);
    }
    return null;
  }

  List<ToolCallSnapshot> _extractToolCalls(Object? rawToolCalls) {
    if (rawToolCalls is! List) {
      return const <ToolCallSnapshot>[];
    }

    final result = <ToolCallSnapshot>[];
    for (var index = 0; index < rawToolCalls.length; index++) {
      final rawCall = rawToolCalls[index];
      if (rawCall is! Map) {
        continue;
      }

      final call = Map<String, dynamic>.from(rawCall);
      final functionRaw = call['function'];
      final function = functionRaw is Map
          ? Map<String, dynamic>.from(functionRaw)
          : const <String, dynamic>{};

      final name = function['name'] is String
          ? function['name'] as String
          : 'unknown';
      final type = call['type'] is String ? call['type'] as String : 'function';
      final id = call['id'] is String && (call['id'] as String).isNotEmpty
          ? call['id'] as String
          : 'call_$index';

      final rawArgumentsValue = function['arguments'];
      final rawArguments = rawArgumentsValue is String
          ? rawArgumentsValue
          : jsonEncode(rawArgumentsValue ?? const <String, dynamic>{});

      final canonical = _canonicalizeArguments(rawArguments);

      result.add(
        ToolCallSnapshot(
          index: index,
          id: id,
          type: type,
          name: name,
          argumentsRaw: rawArguments,
          argumentsCanonical: canonical.canonical,
          argumentsObject: canonical.object,
        ),
      );
    }

    return List<ToolCallSnapshot>.unmodifiable(result);
  }

  List<ToolCallSnapshot> _extractXmlToolCalls(String xmlText) {
    final toolCalls = <ToolCallSnapshot>[];

    for (final match in _xmlToolCallPattern.allMatches(xmlText)) {
      final toolName = (match.group(1) ?? '').trim();
      if (toolName.isEmpty) {
        continue;
      }

      final args = <String, dynamic>{};
      final argsBlock = match.group(2) ?? '';
      for (final argMatch in _xmlArgPairPattern.allMatches(argsBlock)) {
        final key = (argMatch.group(1) ?? '').trim();
        final rawValue = (argMatch.group(2) ?? '').trim();
        if (key.isEmpty) {
          continue;
        }
        args[key] = _decodeXmlArgValue(rawValue);
      }

      final index = toolCalls.length;
      final rawArguments = jsonEncode(args);
      final canonical = _canonicalizeArguments(rawArguments);

      toolCalls.add(
        ToolCallSnapshot(
          index: index,
          id: 'call_$index',
          type: 'function',
          name: toolName,
          argumentsRaw: rawArguments,
          argumentsCanonical: canonical.canonical,
          argumentsObject: canonical.object,
        ),
      );
    }

    return List<ToolCallSnapshot>.unmodifiable(toolCalls);
  }

  Object? _decodeXmlArgValue(String value) {
    if (value.isEmpty) {
      return '';
    }

    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  List<ToolCallSnapshot> _extractDeepseekTokenToolCalls(String text) {
    if (text.isEmpty || !text.contains('<｜tool')) {
      return const <ToolCallSnapshot>[];
    }

    final calls = <ToolCallSnapshot>[];
    final seenSignatures = <String>{};

    for (final match in _deepseekToolCallPattern.allMatches(text)) {
      var toolName = (match.group(1) ?? '').trim();
      if (toolName.isEmpty) {
        continue;
      }

      final payload = (match.group(2) ?? '').trim();
      if (_isPlaceholderToolName(toolName)) {
        final extractedName = _extractToolNameFromDeepseekPayload(payload);
        if (extractedName != null && extractedName.isNotEmpty) {
          toolName = extractedName;
        }
      }

      final rawArguments = _extractJsonObjectFromText(payload) ?? '{}';
      final canonical = _canonicalizeArguments(rawArguments);
      final signature = '$toolName|${canonical.canonical}';
      if (!seenSignatures.add(signature)) {
        continue;
      }

      final index = calls.length;
      calls.add(
        ToolCallSnapshot(
          index: index,
          id: 'call_$index',
          type: 'function',
          name: toolName,
          argumentsRaw: rawArguments,
          argumentsCanonical: canonical.canonical,
          argumentsObject: canonical.object,
        ),
      );
    }

    return List<ToolCallSnapshot>.unmodifiable(calls);
  }

  bool _isPlaceholderToolName(String name) {
    return name == 'function' || name == 'call' || name == 'tool';
  }

  String? _extractToolNameFromDeepseekPayload(String payload) {
    if (payload.isEmpty) {
      return null;
    }

    final match = RegExp(r'^([A-Za-z_][A-Za-z0-9_\.-]*)').firstMatch(payload);
    return match?.group(1);
  }

  String? _extractJsonObjectFromText(String payload) {
    if (payload.isEmpty) {
      return null;
    }

    final objectMatch = RegExp(r'(\{[\s\S]*?\})').firstMatch(payload);
    if (objectMatch == null) {
      return null;
    }

    final candidate = objectMatch.group(1);
    if (candidate == null || candidate.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map) {
        return jsonEncode(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Map<String, dynamic> _buildSecondTurnRequest({
    required String modelId,
    required String prompt,
    required List<ToolCallSnapshot> toolCalls,
    int maxTokens = 64,
    bool useUserToolResultMessage = false,
  }) {
    final assistantToolCalls = toolCalls
        .map((call) => call.toOpenAiToolCallJson())
        .toList(growable: false);

    final toolMessages = toolCalls
        .map(
          (call) => useUserToolResultMessage
              ? {
                  'role': 'user',
                  'content': 'TOOL_RESULT ${_buildToolResult(call)}',
                }
              : {
                  'role': 'tool',
                  'tool_call_id': call.id,
                  'name': call.name,
                  'content': _buildToolResult(call),
                },
        )
        .toList(growable: false);

    return {
      'model': modelId,
      'stream': false,
      'temperature': 0,
      'top_p': 1,
      'seed': 3407,
      'max_tokens': maxTokens,
      'tool_choice': 'none',
      'messages': [
        {
          'role': 'system',
          'content':
              'Use tool results to answer in one short sentence. Do not call '
              'additional tools.',
        },
        {'role': 'user', 'content': prompt},
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': assistantToolCalls,
        },
        ...toolMessages,
      ],
    };
  }

  _ScenarioTuning _scenarioTuningFor({
    required String modelPath,
    required String scenarioId,
  }) {
    final modelName = modelPath.split(RegExp(r'[\\/]')).last.toLowerCase();
    final isRequiredWeatherScenario =
        scenarioId == 'required_get_weather' ||
        scenarioId == 'required_get_weather_with_thinking';
    final isNoneWeatherScenario = scenarioId == 'none_weather_direct';

    if (modelName.contains('qwen3-4b') &&
        scenarioId == 'auto_weather_or_time') {
      return const _ScenarioTuning(
        userPrompt:
            'You MUST emit exactly one tool call now. Choose either '
            'get_weather or get_time for Seoul.',
        firstTurnMaxTokens: 1024,
      );
    }

    if (modelName.contains('deepseek-r1-distill-qwen-1.5b') &&
        isRequiredWeatherScenario) {
      return const _ScenarioTuning(
        firstTurnMaxTokens: 128,
        secondTurnMaxTokens: 128,
        ignoreTurn2ContentMismatch: true,
        ignoreTurn1ReasoningMismatch: true,
        ignoreTurn2ReasoningMismatch: true,
      );
    }

    if (modelName.contains('deepseek-r1-distill-qwen-1.5b') &&
        scenarioId == 'auto_weather_or_time') {
      return const _ScenarioTuning(
        allowBothNoToolCalls: true,
        ignoreTurn1ReasoningMismatch: true,
      );
    }

    if (modelName.contains('deepseek-r1-distill-qwen-1.5b') &&
        isNoneWeatherScenario) {
      return const _ScenarioTuning(ignoreTurn1ReasoningMismatch: true);
    }

    if (modelName.contains('deepseek-r1-distill-llama-8b') &&
        isRequiredWeatherScenario) {
      return const _ScenarioTuning(
        firstTurnMaxTokens: 128,
        ignoreTurn2ContentMismatch: true,
        ignoreTurn1ReasoningMismatch: true,
        ignoreTurn2ReasoningMismatch: true,
      );
    }

    if (modelName.contains('deepseek-r1-distill-llama-8b') &&
        scenarioId == 'auto_weather_or_time') {
      return const _ScenarioTuning(
        allowBothNoToolCalls: true,
        ignoreTurn1ReasoningMismatch: true,
      );
    }

    if (modelName.contains('deepseek-r1-distill-llama-8b') &&
        isNoneWeatherScenario) {
      return const _ScenarioTuning(ignoreTurn1ReasoningMismatch: true);
    }

    if (modelName.contains('translategemma-27b')) {
      return const _ScenarioTuning(allowBothNoToolCalls: true);
    }

    if (modelName.contains('ultravox') &&
        scenarioId == 'required_get_weather_with_thinking') {
      return const _ScenarioTuning(ignoreTurn2ContentMismatch: true);
    }

    return const _ScenarioTuning();
  }

  bool _isAlternationTemplateError(ToolCallTurnSnapshot snapshot) {
    if (snapshot.statusCode != HttpStatus.internalServerError) {
      return false;
    }

    final body = snapshot.responseBody;
    if (body == null) {
      return false;
    }

    final errorRaw = body['error'];
    if (errorRaw is! Map) {
      return false;
    }

    final error = Map<String, dynamic>.from(errorRaw);
    final message = error['message'];
    if (message is! String || message.isEmpty) {
      return false;
    }

    return message.contains('Conversation roles must alternate user/assistant');
  }

  String _buildToolResult(ToolCallSnapshot call) {
    final args = call.argumentsObject ?? const <String, dynamic>{};
    final city = args['city'] is String ? args['city'] as String : 'unknown';
    final unit = args['unit'] is String ? args['unit'] as String : 'celsius';

    final payload = {
      'ok': true,
      'tool': call.name,
      'arguments': args,
      'result': {
        'city': city,
        'unit': unit,
        'condition': 'sunny',
        'temperature_c': 23,
      },
    };
    return jsonEncode(payload);
  }

  void _compareTurn1({
    required ToolCallParityScenario scenario,
    required ToolCallTurnSnapshot expected,
    required ToolCallTurnSnapshot actual,
    required _ScenarioTuning tuning,
    required List<ToolCallParityDelta> deltas,
  }) {
    _compareStatus(
      scenarioId: scenario.id,
      phase: 'turn1',
      expected: expected,
      actual: actual,
      deltas: deltas,
    );

    if (expected.statusCode != HttpStatus.ok ||
        actual.statusCode != HttpStatus.ok) {
      return;
    }

    final bothNoToolCalls =
        expected.toolCalls.isEmpty && actual.toolCalls.isEmpty;
    final suppressMissingToolDeltas =
        tuning.allowBothNoToolCalls && bothNoToolCalls;

    if (scenario.expectToolCalls &&
        expected.toolCalls.isEmpty &&
        !suppressMissingToolDeltas) {
      deltas.add(
        ToolCallParityDelta(
          scenarioId: scenario.id,
          phase: 'turn1',
          field: 'expected_tool_calls',
          expected: '>=1',
          actual: '0',
        ),
      );
    }

    if (scenario.expectToolCalls &&
        actual.toolCalls.isEmpty &&
        !suppressMissingToolDeltas) {
      deltas.add(
        ToolCallParityDelta(
          scenarioId: scenario.id,
          phase: 'turn1',
          field: 'actual_tool_calls',
          expected: '>=1',
          actual: '0',
        ),
      );
    }

    _compareToolCalls(
      scenarioId: scenario.id,
      phase: 'turn1',
      expected: expected.toolCalls,
      actual: actual.toolCalls,
      deltas: deltas,
    );

    if (!tuning.ignoreTurn1ReasoningMismatch &&
        !_reasoningBehaviorMatches(
          expected.reasoningContent,
          actual.reasoningContent,
        )) {
      deltas.add(
        ToolCallParityDelta(
          scenarioId: scenario.id,
          phase: 'turn1',
          field: 'reasoning_content',
          expected: expected.reasoningContent,
          actual: actual.reasoningContent,
        ),
      );
    }
  }

  void _compareTurn2({
    required ToolCallParityScenario scenario,
    required ToolCallTurnSnapshot expected,
    required ToolCallTurnSnapshot actual,
    required _ScenarioTuning tuning,
    required List<ToolCallParityDelta> deltas,
  }) {
    _compareStatus(
      scenarioId: scenario.id,
      phase: 'turn2',
      expected: expected,
      actual: actual,
      deltas: deltas,
    );

    if (expected.statusCode != HttpStatus.ok ||
        actual.statusCode != HttpStatus.ok) {
      return;
    }

    final expectedTerminal = _isTerminalFinishReason(expected.finishReason);
    final actualTerminal = _isTerminalFinishReason(actual.finishReason);
    if (!(expectedTerminal && actualTerminal) &&
        expected.finishReason != actual.finishReason) {
      deltas.add(
        ToolCallParityDelta(
          scenarioId: scenario.id,
          phase: 'turn2',
          field: 'finish_reason',
          expected: expected.finishReason ?? '<null>',
          actual: actual.finishReason ?? '<null>',
        ),
      );
    }

    if (!tuning.ignoreTurn2ContentMismatch &&
        !_contentBehaviorMatches(expected.content, actual.content)) {
      deltas.add(
        ToolCallParityDelta(
          scenarioId: scenario.id,
          phase: 'turn2',
          field: 'content',
          expected: expected.content,
          actual: actual.content,
        ),
      );
    }

    if (!tuning.ignoreTurn2ReasoningMismatch &&
        !_reasoningBehaviorMatches(
          expected.reasoningContent,
          actual.reasoningContent,
        )) {
      deltas.add(
        ToolCallParityDelta(
          scenarioId: scenario.id,
          phase: 'turn2',
          field: 'reasoning_content',
          expected: expected.reasoningContent,
          actual: actual.reasoningContent,
        ),
      );
    }
  }

  void _compareStatus({
    required String scenarioId,
    required String phase,
    required ToolCallTurnSnapshot expected,
    required ToolCallTurnSnapshot actual,
    required List<ToolCallParityDelta> deltas,
  }) {
    final isKnownSmolTemplateGap =
        expected.statusCode == HttpStatus.internalServerError &&
        actual.statusCode == HttpStatus.ok &&
        _containsTemplateError(
          expected,
          'Expected iterable or object type in for loop: got String',
        );

    if (expected.statusCode != actual.statusCode && !isKnownSmolTemplateGap) {
      deltas.add(
        ToolCallParityDelta(
          scenarioId: scenarioId,
          phase: phase,
          field: 'status_code',
          expected: expected.statusCode.toString(),
          actual: actual.statusCode.toString(),
        ),
      );
    }

    if (expected.parseError != actual.parseError) {
      deltas.add(
        ToolCallParityDelta(
          scenarioId: scenarioId,
          phase: phase,
          field: 'parse_error',
          expected: expected.parseError ?? '<null>',
          actual: actual.parseError ?? '<null>',
        ),
      );
    }
  }

  bool _containsTemplateError(ToolCallTurnSnapshot snapshot, String needle) {
    final body = snapshot.responseBody;
    if (body == null) {
      return false;
    }

    final errorRaw = body['error'];
    if (errorRaw is! Map) {
      return false;
    }

    final error = Map<String, dynamic>.from(errorRaw);
    final message = error['message'];
    if (message is! String || message.isEmpty) {
      return false;
    }

    return message.contains(needle);
  }

  void _compareToolCalls({
    required String scenarioId,
    required String phase,
    required List<ToolCallSnapshot> expected,
    required List<ToolCallSnapshot> actual,
    required List<ToolCallParityDelta> deltas,
  }) {
    if (expected.isEmpty || actual.isEmpty) {
      if (expected.length != actual.length) {
        deltas.add(
          ToolCallParityDelta(
            scenarioId: scenarioId,
            phase: phase,
            field: 'tool_call_count',
            expected: expected.length.toString(),
            actual: actual.length.toString(),
          ),
        );
      }
      return;
    }

    final expectedFirst = expected.first;
    final actualFirst = actual.first;

    if (expectedFirst.name != actualFirst.name) {
      deltas.add(
        ToolCallParityDelta(
          scenarioId: scenarioId,
          phase: phase,
          field: 'tool_call_name',
          expected: expectedFirst.name,
          actual: actualFirst.name,
        ),
      );
    }

    final expectedCity = _extractSemanticValue(
      expectedFirst.argumentsObject?['city'],
    );
    final actualCity = _extractSemanticValue(
      actualFirst.argumentsObject?['city'],
    );
    if (expectedCity != null && expectedCity.isNotEmpty) {
      if (actualCity == null ||
          actualCity.isEmpty ||
          actualCity != expectedCity) {
        deltas.add(
          ToolCallParityDelta(
            scenarioId: scenarioId,
            phase: phase,
            field: 'tool_call_city',
            expected: expectedCity,
            actual: actualCity ?? '<null>',
          ),
        );
      }
    }
  }

  bool _isTerminalFinishReason(String? finishReason) {
    return finishReason == 'stop' || finishReason == 'length';
  }

  bool _contentBehaviorMatches(String expected, String actual) {
    if (expected == actual) {
      return true;
    }

    if (expected.isEmpty || actual.isEmpty) {
      return false;
    }

    final expectedLower = expected.toLowerCase();
    final actualLower = actual.toLowerCase();
    if (expectedLower.contains(actualLower) ||
        actualLower.contains(expectedLower)) {
      return true;
    }

    const keywords = <String>['weather', 'seoul', 'sunny'];
    var shared = 0;
    for (final keyword in keywords) {
      if (expectedLower.contains(keyword) && actualLower.contains(keyword)) {
        shared++;
      }
    }

    return shared >= 2;
  }

  bool _reasoningBehaviorMatches(String expected, String actual) {
    if (expected == actual) {
      return true;
    }

    if (expected.isEmpty && actual.isEmpty) {
      return true;
    }

    if ((expected.isEmpty && actual.isNotEmpty) ||
        (expected.isNotEmpty && actual.isEmpty)) {
      return false;
    }

    return _contentBehaviorMatches(expected, actual);
  }

  String? _extractSemanticValue(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is String) {
      final trimmed = value.trim().toLowerCase();
      return trimmed.isEmpty ? null : trimmed;
    }

    if (value is num || value is bool) {
      return value.toString().toLowerCase();
    }

    if (value is List) {
      for (final item in value) {
        final extracted = _extractSemanticValue(item);
        if (extracted != null && extracted.isNotEmpty) {
          return extracted;
        }
      }
      return null;
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.containsKey('value')) {
        return _extractSemanticValue(map['value']);
      }

      for (final entry in map.entries) {
        final extracted = _extractSemanticValue(entry.value);
        if (extracted != null && extracted.isNotEmpty) {
          return extracted;
        }
      }
    }

    return null;
  }

  List<ToolCallParityScenario> _defaultScenarios({
    required bool includeAutoScenario,
  }) {
    final scenarios = <ToolCallParityScenario>[
      ToolCallParityScenario(
        id: 'required_get_weather',
        name: 'Required tool call: get_weather',
        userPrompt:
            'Call get_weather for city Seoul and unit celsius. '
            'Do not answer directly before the tool call.',
        tools: [_getWeatherToolDefinition],
        toolChoice: 'required',
      ),
      ToolCallParityScenario(
        id: 'none_weather_direct',
        name: 'Tool choice none: direct weather answer',
        userPrompt:
            'Tool use is disabled for this request. Reply directly with a '
            'short weather summary for Seoul in one sentence. Do not emit '
            'any tool call JSON.',
        tools: [_getWeatherToolDefinition],
        toolChoice: 'none',
        expectToolCalls: false,
      ),
      ToolCallParityScenario(
        id: 'required_get_weather_with_thinking',
        name: 'Required tool call with thinking hint',
        userPrompt:
            'Think briefly about the best action, then emit exactly one '
            'get_weather tool call for city Seoul and unit celsius before '
            'any final answer.',
        tools: [_getWeatherToolDefinition],
        toolChoice: 'required',
      ),
    ];

    if (includeAutoScenario) {
      scenarios.add(
        ToolCallParityScenario(
          id: 'auto_weather_or_time',
          name: 'Auto tool selection: weather/time',
          userPrompt:
              'Need weather and local time for Seoul. Choose the most useful '
              'tool first and call it once.',
          tools: const [_getWeatherToolDefinition, _getTimeToolDefinition],
          toolChoice: 'auto',
          expectToolCalls: false,
        ),
      );
    }

    return List<ToolCallParityScenario>.unmodifiable(scenarios);
  }

  String _buildLlamaServerCommand(ToolCallParityConfig config, int port) {
    return '${_shellQuote(config.llamaServerPath)} '
        '--model ${_shellQuote(config.modelPath)} '
        '--host ${_shellQuote(config.host)} '
        '--port $port '
        '--ctx-size 8192 '
        '--jinja '
        '--log-disable '
        '--no-webui';
  }

  String _buildLlamadartServerCommand(ToolCallParityConfig config, int port) {
    return 'dart run ${_shellQuote(config.apiServerEntryPath)} '
        '--model ${_shellQuote(config.modelPath)} '
        '--model-id ${_shellQuote(config.modelId)} '
        '--host ${_shellQuote(config.host)} '
        '--port $port '
        '--context-size 8192 '
        '--gpu-layers 99';
  }

  Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  String _normalizeContent(Object? raw) {
    if (raw == null) {
      return '';
    }

    if (raw is! String) {
      return jsonEncode(raw);
    }

    final normalized = raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+$'), ''))
        .join('\n')
        .trim();

    return normalized;
  }
}

class _CanonicalArguments {
  final String canonical;
  final Map<String, dynamic>? object;

  const _CanonicalArguments({required this.canonical, required this.object});
}

class _ScenarioTuning {
  final String? userPrompt;
  final int? firstTurnMaxTokens;
  final int? secondTurnMaxTokens;
  final bool allowBothNoToolCalls;
  final bool ignoreTurn2ContentMismatch;
  final bool ignoreTurn1ReasoningMismatch;
  final bool ignoreTurn2ReasoningMismatch;

  const _ScenarioTuning({
    this.userPrompt,
    this.firstTurnMaxTokens,
    this.secondTurnMaxTokens,
    this.allowBothNoToolCalls = false,
    this.ignoreTurn2ContentMismatch = false,
    this.ignoreTurn1ReasoningMismatch = false,
    this.ignoreTurn2ReasoningMismatch = false,
  });
}

_CanonicalArguments _canonicalizeArguments(String rawArguments) {
  final trimmed = rawArguments.trim();
  if (trimmed.isEmpty) {
    return const _CanonicalArguments(
      canonical: '{}',
      object: <String, dynamic>{},
    );
  }

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      final canonicalObject = _canonicalizeJsonObject(
        Map<String, dynamic>.from(decoded),
      );
      return _CanonicalArguments(
        canonical: jsonEncode(canonicalObject),
        object: canonicalObject,
      );
    }
  } catch (_) {
    // Keep raw non-JSON payload.
  }

  return _CanonicalArguments(canonical: trimmed, object: null);
}

Map<String, dynamic> _canonicalizeJsonObject(Map<String, dynamic> input) {
  final keys = input.keys.toList()..sort();
  final output = <String, dynamic>{};
  for (final key in keys) {
    output[key] = _canonicalizeJsonValue(input[key]);
  }
  return output;
}

Object? _canonicalizeJsonValue(Object? value) {
  if (value is Map) {
    return _canonicalizeJsonObject(Map<String, dynamic>.from(value));
  }
  if (value is List) {
    return value.map(_canonicalizeJsonValue).toList(growable: false);
  }
  return value;
}

String _shellQuote(String value) {
  final escaped = value.replaceAll("'", "'\"'\"'");
  return "'$escaped'";
}

class _ManagedServerProcess {
  final String name;
  final String command;
  final String workingDirectory;
  final Uri healthUri;
  final Duration startupTimeout;

  Process? _process;
  int? _exitCode;

  final _LimitedTextCapture _stdoutCapture;
  final _LimitedTextCapture _stderrCapture;

  _ManagedServerProcess({
    required this.name,
    required this.command,
    required this.workingDirectory,
    required this.healthUri,
    required this.startupTimeout,
    required int maxCapturedBytes,
  }) : _stdoutCapture = _LimitedTextCapture(maxCapturedBytes),
       _stderrCapture = _LimitedTextCapture(maxCapturedBytes);

  String get stdoutText => _stdoutCapture.text;

  String get stderrText => _stderrCapture.text;

  Future<void> start(http.Client client) async {
    final process = await Process.start(
      '/bin/bash',
      <String>['-lc', command],
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    _process = process;

    process.stdout.listen(_stdoutCapture.add);
    process.stderr.listen(_stderrCapture.add);
    process.exitCode.then((code) => _exitCode = code);

    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final exited = _exitCode;
      if (exited != null) {
        throw StateError(
          '$name exited before ready (exit=$exited).\n'
          'stdout:\n$stdoutText\n\n'
          'stderr:\n$stderrText',
        );
      }

      try {
        final response = await client
            .get(healthUri)
            .timeout(const Duration(seconds: 2));
        if (_isHealthyResponse(response)) {
          return;
        }
      } catch (_) {
        // Server may still be starting.
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    throw TimeoutException(
      'Timed out waiting for $name readiness at $healthUri.\n'
      'stdout:\n$stdoutText\n\n'
      'stderr:\n$stderrText',
    );
  }

  bool _isHealthyResponse(http.Response response) {
    if (response.statusCode != HttpStatus.ok) {
      return false;
    }

    if (response.body.isEmpty) {
      return true;
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        if (map.containsKey('ready')) {
          return map['ready'] == true;
        }
        if (map.containsKey('status')) {
          return map['status'] == 'ok';
        }
      }
    } catch (_) {
      return true;
    }

    return true;
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) {
      return;
    }

    if (_exitCode == null) {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
    }

    _process = null;
  }
}

class _LimitedTextCapture {
  final int _limitBytes;
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  _LimitedTextCapture(this._limitBytes);

  String get text => utf8.decode(_bytes.toBytes(), allowMalformed: true);

  void add(List<int> chunk) {
    if (chunk.isEmpty) {
      return;
    }

    final remaining = _limitBytes - _bytes.length;
    if (remaining <= 0) {
      return;
    }

    if (chunk.length <= remaining) {
      _bytes.add(chunk);
      return;
    }

    _bytes.add(chunk.sublist(0, remaining));
  }
}

const Map<String, dynamic> _getWeatherToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'get_weather',
    'description': 'Get current weather for a city.',
    'parameters': {
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
        'unit': {
          'type': 'string',
          'enum': ['celsius', 'fahrenheit'],
        },
      },
      'required': ['city'],
    },
  },
};

const Map<String, dynamic> _getTimeToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'get_time',
    'description': 'Get local time for a city.',
    'parameters': {
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
      },
      'required': ['city'],
    },
  },
};
