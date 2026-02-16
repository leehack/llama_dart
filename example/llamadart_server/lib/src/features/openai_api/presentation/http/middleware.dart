import 'dart:convert';

import 'package:relic/relic.dart';

import '../../../shared/shared.dart';

const _bearerPrefix = 'Bearer ';

final Headers _corsHeaders = Headers.build((MutableHeaders headers) {
  _applyCorsHeaders(headers);
});

/// Creates CORS middleware for browser clients.
Middleware createCorsMiddleware() {
  return (Handler next) {
    return (Request req) async {
      if (req.method == Method.options) {
        return Response.noContent(headers: _corsHeaders);
      }

      final result = await next(req);
      if (result is Response) {
        return result.copyWith(
          headers: result.headers.transform((MutableHeaders headers) {
            _applyCorsHeaders(headers);
          }),
        );
      }

      return result;
    };
  };
}

/// Creates API key middleware for `Authorization: Bearer <key>`.
Middleware createApiKeyMiddleware(String? apiKey) {
  if (apiKey == null || apiKey.isEmpty) {
    return (Handler next) => next;
  }

  final unauthorizedPayload = jsonEncode(
    OpenAiHttpException.authentication(
      'Incorrect API key provided.',
    ).toResponseBody(),
  );

  return (Handler next) {
    return (Request req) async {
      if (req.method == Method.options) {
        return next(req);
      }

      final authHeader = req.headers['authorization']?.first;
      final token = _extractBearerToken(authHeader);

      if (token != apiKey) {
        return Response.unauthorized(
          headers: Headers.build((MutableHeaders headers) {
            headers['WWW-Authenticate'] = ['Bearer'];
            _applyCorsHeaders(headers);
          }),
          body: Body.fromString(unauthorizedPayload, mimeType: MimeType.json),
        );
      }

      return next(req);
    };
  };
}

void _applyCorsHeaders(MutableHeaders headers) {
  headers['Access-Control-Allow-Origin'] = ['*'];
  headers['Access-Control-Allow-Methods'] = ['GET, POST, OPTIONS'];
  headers['Access-Control-Allow-Headers'] = ['Authorization, Content-Type'];
}

String? _extractBearerToken(String? authorizationHeader) {
  if (authorizationHeader == null) {
    return null;
  }

  if (!authorizationHeader.startsWith(_bearerPrefix)) {
    return null;
  }

  return authorizationHeader.substring(_bearerPrefix.length).trim();
}
