import '../../../shared/openai_http_exception.dart';

List<String> parseStopSequences(Object? raw) {
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

int? readIntField(Object? raw, String fieldName) {
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

double? readDoubleField(Object? raw, String fieldName) {
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

bool? readBoolField(Object? raw, String fieldName) {
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
