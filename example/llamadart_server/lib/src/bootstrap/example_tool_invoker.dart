/// Built-in tool invoker for demo usage.
Future<Object?> invokeExampleTool(
  String toolName,
  Map<String, dynamic> arguments,
) async {
  switch (toolName) {
    case 'get_current_time':
    case 'get_time':
      final timezone =
          _extractStringValue(arguments['timezone'])?.toLowerCase() ?? 'local';
      final now = timezone == 'utc' ? DateTime.now().toUtc() : DateTime.now();
      return {
        'ok': true,
        'tool': toolName,
        'timezone': timezone,
        'iso8601': now.toIso8601String(),
      };

    case 'get_current_weather':
    case 'get_weather':
      final city =
          _extractStringValue(arguments['city']) ??
          _extractStringValue(arguments['location']) ??
          'unknown';
      final unit = (_extractStringValue(arguments['unit']) ?? 'celsius')
          .toLowerCase();
      const celsius = 23;
      final temperature = unit == 'fahrenheit'
          ? (celsius * 9 / 5 + 32).round()
          : celsius;

      return {
        'ok': true,
        'tool': toolName,
        'city': city,
        'unit': unit,
        'condition': 'sunny',
        'temperature': temperature,
      };

    default:
      throw UnsupportedError(
        'No server-side handler registered for `$toolName`.',
      );
  }
}

String? _extractStringValue(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  if (value is num || value is bool) {
    return value.toString();
  }

  if (value is List) {
    for (final item in value) {
      final extracted = _extractStringValue(item);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
    }
    return null;
  }

  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    if (map.containsKey('value')) {
      final extracted = _extractStringValue(map['value']);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
    }

    for (final entry in map.entries) {
      final extracted = _extractStringValue(entry.value);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
    }
  }

  return null;
}
