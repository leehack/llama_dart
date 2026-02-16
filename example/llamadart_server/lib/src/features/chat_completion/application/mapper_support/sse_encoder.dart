import 'dart:convert';

/// Encodes one SSE data payload line.
String encodeSseData(Map<String, dynamic> payload) {
  return 'data: ${jsonEncode(payload)}\n\n';
}

/// Encodes the SSE completion sentinel.
String encodeSseDone() {
  return 'data: [DONE]\n\n';
}
