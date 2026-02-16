import 'dart:convert';

/// Builds a Swagger UI HTML page using CDN assets.
String buildSwaggerUiHtml({
  required String specUrl,
  String title = 'llamadart API Docs',
}) {
  final encodedTitle = htmlEscape.convert(title);
  final specUrlJson = jsonEncode(specUrl);

  return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>$encodedTitle</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css" />
  <style>
    html, body {
      margin: 0;
      padding: 0;
      background: #fafafa;
    }

    .quick-help {
      max-width: 1200px;
      margin: 0 auto;
      padding: 12px 16px;
      border-bottom: 1px solid #e5e7eb;
      background: #f8fafc;
      color: #111827;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      font-size: 14px;
      line-height: 1.4;
    }

    .quick-help strong {
      display: inline-block;
      margin-right: 8px;
    }

    .quick-help code {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      background: #eef2ff;
      padding: 1px 5px;
      border-radius: 4px;
    }

    #swagger-ui {
      max-width: 1200px;
      margin: 0 auto;
    }
  </style>
</head>
<body>
  <div class="quick-help">
    <strong>Quick test:</strong>
    Open <code>POST /v1/chat/completions</code>, choose an example under
    <code>Request body</code>, click <code>Try it out</code>, then
    <code>Execute</code>.
  </div>
  <div id="swagger-ui"></div>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
  <script>
    window.onload = function () {
      window.ui = SwaggerUIBundle({
        url: $specUrlJson,
        dom_id: '#swagger-ui',
        deepLinking: true,
        filter: true,
        tryItOutEnabled: true,
        docExpansion: 'list',
        defaultModelsExpandDepth: -1,
        displayRequestDuration: true,
        persistAuthorization: true,
        syntaxHighlight: {
          activated: true,
          theme: 'agate'
        },
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIStandalonePreset
        ],
        layout: 'BaseLayout'
      });
    };
  </script>
</body>
</html>
''';
}
