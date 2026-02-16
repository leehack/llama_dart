import 'dart:typed_data';

import 'package:relic/relic.dart';

final Headers _sseHeaders = Headers.build((MutableHeaders headers) {
  headers['Cache-Control'] = ['no-cache'];
  headers['Connection'] = ['keep-alive'];
  headers['X-Accel-Buffering'] = ['no'];
});

/// Builds a standard SSE response for OpenAI stream mode.
Response sseResponse(Stream<Uint8List> stream) {
  return Response.ok(
    headers: _sseHeaders,
    body: Body.fromDataStream(
      stream,
      mimeType: MimeType.parse('text/event-stream'),
    ),
  );
}
