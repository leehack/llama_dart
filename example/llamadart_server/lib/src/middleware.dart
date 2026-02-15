import 'dart:convert';

import 'package:relic/relic.dart';

import 'openai_error.dart';

/// Creates CORS middleware for browser clients.
Middleware createCorsMiddleware() {
  return (Handler next) {
    return (Request req) async {
      if (req.method == Method.options) {
        return Response.noContent(headers: _corsHeaders());
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

  return (Handler next) {
    return (Request req) async {
      if (req.method == Method.options) {
        return next(req);
      }

      final authHeader = req.headers['authorization']?.first;
      final token = _extractBearerToken(authHeader);

      if (token != apiKey) {
        final error = OpenAiHttpException.authentication(
          'Incorrect API key provided.',
        );

        return Response.unauthorized(
          headers: Headers.build((MutableHeaders headers) {
            headers['WWW-Authenticate'] = ['Bearer'];
            _applyCorsHeaders(headers);
          }),
          body: Body.fromString(
            jsonEncode(error.toResponseBody()),
            mimeType: MimeType.json,
          ),
        );
      }

      return next(req);
    };
  };
}

Headers _corsHeaders() {
  return Headers.build((MutableHeaders headers) {
    _applyCorsHeaders(headers);
  });
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

  const prefix = 'Bearer ';
  if (!authorizationHeader.startsWith(prefix)) {
    return null;
  }

  return authorizationHeader.substring(prefix.length).trim();
}
