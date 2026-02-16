import 'dart:convert';

import 'package:relic/relic.dart';

import '../../../../shared/shared.dart';

/// Reads and validates a JSON object request body.
Future<Map<String, dynamic>> readJsonObjectBody(Request req) async {
  final rawBody = await req.readAsString();

  dynamic decoded;
  try {
    decoded = jsonDecode(rawBody);
  } on FormatException {
    throw OpenAiHttpException.invalidRequest('Request body is not valid JSON.');
  }

  if (decoded is! Map) {
    throw OpenAiHttpException.invalidRequest(
      'Request body must be a JSON object.',
    );
  }

  return Map<String, dynamic>.from(decoded);
}

/// Builds a JSON response.
Response jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
  return Response(
    statusCode,
    body: Body.fromString(jsonEncode(body), mimeType: MimeType.json),
  );
}

/// Builds an OpenAI-compatible error response.
Response errorJsonResponse(OpenAiHttpException error) {
  return jsonResponse(error.toResponseBody(), statusCode: error.statusCode);
}
