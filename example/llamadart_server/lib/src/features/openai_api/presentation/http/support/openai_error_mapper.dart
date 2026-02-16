import '../../../../shared/shared.dart';

/// Converts unexpected exceptions into server errors.
OpenAiHttpException toServerError(Object error, String prefix) {
  return OpenAiHttpException.server('$prefix: $error');
}
