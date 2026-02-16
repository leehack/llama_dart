/// Error type used to produce OpenAI-compatible error payloads.
class OpenAiHttpException implements Exception {
  /// HTTP status code for this error.
  final int statusCode;

  /// OpenAI-style error category.
  final String type;

  /// Human-readable message.
  final String message;

  /// Optional parameter name tied to the error.
  final String? param;

  /// Optional machine-readable error code.
  final String? code;

  /// Creates a new [OpenAiHttpException].
  const OpenAiHttpException({
    required this.statusCode,
    required this.type,
    required this.message,
    this.param,
    this.code,
  });

  /// Creates a 400 invalid request error.
  factory OpenAiHttpException.invalidRequest(
    String message, {
    String? param,
    String? code,
  }) {
    return OpenAiHttpException(
      statusCode: 400,
      type: 'invalid_request_error',
      message: message,
      param: param,
      code: code,
    );
  }

  /// Creates a 401 authentication error.
  factory OpenAiHttpException.authentication(String message) {
    return OpenAiHttpException(
      statusCode: 401,
      type: 'authentication_error',
      message: message,
      code: 'invalid_api_key',
    );
  }

  /// Creates a 404 model-not-found error.
  factory OpenAiHttpException.modelNotFound(String model) {
    return OpenAiHttpException(
      statusCode: 404,
      type: 'invalid_request_error',
      message: 'The model `$model` does not exist.',
      param: 'model',
      code: 'model_not_found',
    );
  }

  /// Creates a 429 rate-limit style error.
  factory OpenAiHttpException.busy(String message) {
    return OpenAiHttpException(
      statusCode: 429,
      type: 'rate_limit_error',
      message: message,
      code: 'server_busy',
    );
  }

  /// Creates a 500 server error.
  factory OpenAiHttpException.server(String message) {
    return OpenAiHttpException(
      statusCode: 500,
      type: 'server_error',
      message: message,
      code: 'internal_error',
    );
  }

  /// Converts this error to an OpenAI-compatible JSON payload.
  Map<String, dynamic> toResponseBody() {
    return {
      'error': {'message': message, 'type': type, 'param': param, 'code': code},
    };
  }

  @override
  String toString() {
    return 'OpenAiHttpException('
        'statusCode: $statusCode, '
        'type: $type, '
        'message: $message, '
        'param: $param, '
        'code: $code)';
  }
}
