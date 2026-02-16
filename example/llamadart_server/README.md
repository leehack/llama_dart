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

## Project structure

This example now follows a feature-first structure:

- `lib/src/features/openai_api/` - OpenAI-compatible HTTP server and docs
- `lib/src/features/chat_completion/` - chat request model, parser, mapper, and
  completion use cases
- `lib/src/features/model_management/` - model path resolution and download
- `lib/src/features/server_engine/` - engine contract + llama engine adapter
- `lib/src/features/shared/` - shared API error types
- `lib/src/bootstrap/` - CLI argument parsing and runtime wiring

Public APIs are exported directly from `lib/llamadart_server.dart`.

## Limitations

- Supports a single generation at a time (returns 429 while busy)
- Supports `n = 1` only
- By default, tools are passed through to the model prompt only (no server-side
  execution). Use `--enable-tool-execution` to enable an example built-in tool
  loop.
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
- `--enable-tool-execution` (default: disabled; enables built-in demo handlers)
- `--max-tool-rounds` (default: `5`; used only when tool execution is enabled)
- `--log` (enable verbose Dart + HTTP request logs; native logs stay error-only)

### Exit codes

- `0` - success (including `--help`)
- `64` - invalid CLI usage or argument values
- `70` - runtime/server startup failure

### Sampling defaults

When omitted in a request body, this example server applies a stable default
`GenerationParams` baseline:

- `penalty = 1.0`
- `top_p = 0.95`
- `min_p = 0.05`

Request-provided sampling fields (for example `temperature`, `top_p`, `seed`,
`max_tokens`) override these defaults per call.

## API Examples

### 0. OpenAPI and Swagger UI

- OpenAPI JSON: `http://127.0.0.1:8080/openapi.json`
- Swagger UI: `http://127.0.0.1:8080/docs`
- Swagger includes ready-made chat request examples (basic, streaming, tools)
  under `POST /v1/chat/completions`.

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
