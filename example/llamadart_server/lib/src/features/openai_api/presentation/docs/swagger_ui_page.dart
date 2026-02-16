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

    #swagger-ui {
      max-width: 1200px;
      margin: 0 auto;
    }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
  <script>
    window.onload = function () {
      window.ui = SwaggerUIBundle({
        url: $specUrlJson,
        dom_id: '#swagger-ui',
        deepLinking: true,
        displayRequestDuration: true,
        persistAuthorization: true,
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
