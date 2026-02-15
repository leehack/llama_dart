# llamadart OpenAI-Compatible API Server Example

This example runs a local API server in Dart using
[`relic`](https://pub.dev/packages/relic), backed by `llamadart`.

It exposes OpenAI-compatible endpoints:

- `GET /v1/models`
- `POST /v1/chat/completions`
- `GET /openapi.json`
- `GET /docs` (Swagger UI)

## Features

- OpenAI-style JSON responses
- Streaming (`stream: true`) over SSE with `data: [DONE]`
- Optional Bearer auth (`--api-key`)
- Built-in OpenAPI + Swagger UI docs
- CORS support for local browser clients
- One loaded GGUF model per server process

## Limitations

- Supports a single generation at a time (returns 429 while busy)
- Supports `n = 1` only
- Tools are passed through to the model prompt only; this example does not
  execute tools server-side
- Chat Completions only (no Embeddings or legacy Completions endpoint)

## Run

```bash
dart pub get
dart run llamadart_server --model /path/to/model.gguf
```

Use a remote GGUF URL instead of a path if you want automatic download.

Optional flags:

- `--model-id` (default: `llamadart-local`)
- `--host` (default: `127.0.0.1`)
- `--port` (default: `8080`)
- `--api-key` (optional)
- `--context-size` (default: `4096`)
- `--gpu-layers` (default: `999`)
- `--log` (enable verbose Dart + HTTP request logs; native logs stay error-only)

## API Examples

### 0. OpenAPI and Swagger UI

- OpenAPI JSON: `http://127.0.0.1:8080/openapi.json`
- Swagger UI: `http://127.0.0.1:8080/docs`

```bash
curl http://127.0.0.1:8080/openapi.json
```

If `--api-key` is enabled, use Swagger UI's **Authorize** button and enter your
API key value.

### 1. List models

```bash
curl http://127.0.0.1:8080/v1/models
```

### 2. Non-streaming chat completion

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llamadart-local",
    "messages": [
      {"role": "system", "content": "You are concise."},
      {"role": "user", "content": "Give me one sentence about Seoul."}
    ],
    "max_tokens": 128
  }'
```

### 3. Streaming chat completion (SSE)

```bash
curl -N http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llamadart-local",
    "stream": true,
    "messages": [
      {"role": "user", "content": "Write a 3-line poem."}
    ]
  }'
```

### 4. With API key

```bash
curl http://127.0.0.1:8080/v1/models \
  -H "Authorization: Bearer YOUR_KEY"
```

## Tests

```bash
dart test
```
