# llamadart CLI Clone Example

This example provides a `llama.cpp`-style terminal chat CLI built with
`llamadart`.

It is designed so you can run GLM-4.7-Flash with the same style of commands
used in the Unsloth guide.

## Features

- llama.cpp-like argument surface (`--model`, `-hf`, `--ctx-size`, `--fit`)
- Interactive chat loop with streaming output
- Terminal banner + llama.cpp-style prompt flow (`>`, thinking stream)
- Sampling controls (`--temp`, `--top-p`, `--min-p`, `--repeat-penalty`)
- Common alias compatibility (`--n-predict`, `--top_p`, `--repeat_penalty`)
- Hugging Face shorthand resolver (`-hf repo[:file-hint]`)
- `--simple-io` mode with llama.cpp-compatible terminal behavior
- Prompt-file input with `--file`
- Local model cache in `./models` by default

## Quick Start

From this directory:

```bash
dart pub get
dart run bin/llamadart_cli.dart --help
```

### Unsloth GLM flow (same command style)

```bash
dart run bin/llamadart_cli.dart \
  -hf unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL \
  --jinja --ctx-size 16384 \
  --temp 1.0 --top-p 0.95 --min-p 0.01 --fit on
```

### Local model path

```bash
dart run bin/llamadart_cli.dart \
  --model /path/to/GLM-4.7-Flash-UD-Q4_K_XL.gguf \
  --ctx-size 16384 --fit on --jinja
```

### Prompt from file

```bash
dart run bin/llamadart_cli.dart \
  --model ./models/GLM-4.7-Flash-UD-Q4_K_XL.gguf \
  --file ./tool/parity_prompts/flappy_bird.txt \
  --simple-io
```

## Parity Harness

### Build llama.cpp for parity (once)

```bash
mkdir -p .parity_tools
git clone https://github.com/ggml-org/llama.cpp .parity_tools/llama.cpp
cmake -S .parity_tools/llama.cpp -B .parity_tools/llama.cpp/build \
  -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON
cmake --build .parity_tools/llama.cpp/build --config Release -j --target llama-cli
```

Optionally build a bundled `llamadart_cli` binary (avoids `dart run` hook noise):

```bash
dart build cli --output .parity_tools/build_cli
```

### Run parity

Run llama.cpp and the Dart CLI clone with the same scripted prompts, then write
raw and normalized transcript reports:

```bash
dart run tool/parity_harness.dart \
  --llama-cpp-command ".parity_tools/llama.cpp/build/bin/llama-cli --model ./models/GLM-4.7-Flash-UD-Q4_K_XL.gguf --ctx-size 8192 --seed 3407 --temp 1.0 --top-p 0.95 --min-p 0.01 --repeat-penalty 1.0 --fit on --jinja --simple-io --no-show-timings --log-disable -n 16" \
  --llamadart-command ".parity_tools/build_cli/bundle/bin/llamadart_cli --model ./models/GLM-4.7-Flash-UD-Q4_K_XL.gguf --ctx-size 8192 --seed 3407 --temp 1.0 --top-p 0.95 --min-p 0.01 --repeat-penalty 1.0 --fit on --jinja --simple-io -n 16" \
  --prompts-file tool/parity_prompts/flappy_bird.txt
```

Strict raw stdout comparison:

```bash
dart run tool/parity_harness.dart \
  --strict-raw \
  --llama-cpp-command "..." \
  --llamadart-command "..."
```

Reports are written to `.parity_reports/` by default.

## Tool-call parity (server loop)

This compares full OpenAI-style tool-call round trips between:

- llama.cpp `llama-server`
- `example/llamadart_server` (llamadart-backed)

### Build `llama-server` (once)

```bash
mkdir -p .parity_tools
git clone https://github.com/ggml-org/llama.cpp .parity_tools/llama.cpp
cmake -S .parity_tools/llama.cpp -B .parity_tools/llama.cpp/build \
  -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DLLAMA_BUILD_SERVER=ON
cmake --build .parity_tools/llama.cpp/build --config Release -j --target llama-server
```

### Run tool-call parity report

```bash
dart run tool/tool_call_parity.dart \
  --model ./models/GLM-4.7-Flash-UD-Q4_K_XL.gguf \
  --llama-server-path ./.parity_tools/llama.cpp/build/bin/llama-server \
  --api-server-entry ../llamadart_server/bin/llamadart_server.dart
```

Artifacts are written to `.parity_reports_tool/`.

### Batch all local models (matrix)

If you keep multiple GGUF files locally, run the harness in a loop and collect
one report directory per model:

```bash
timestamp=$(date +"%Y%m%d_%H%M%S")
run_root=".parity_reports_tool_all_models_${timestamp}"
mkdir -p "$run_root"

for model in /path/to/models/*.gguf; do
  slug=$(basename "$model" .gguf | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-')
  dart run tool/tool_call_parity.dart \
    --model "$model" \
    --llama-server-path ./.parity_tools/llama.cpp/build/bin/llama-server \
    --api-server-entry ../llamadart_server/bin/llamadart_server.dart \
    --include-auto-scenario \
    --report-dir "$run_root/$slug"
done
```

Tip: add your own summary script (or CI step) to aggregate MATCH/DIFFERENT from
each model report folder.

### Local parity gate test

One-command local verification:

```bash
./tool/check_local_parity.sh
```

This runs `dart analyze`, default tests, transcript parity gate, and tool-call
parity gate.

It fails fast if required local artifacts are missing:

- model GGUF file (`models/GLM-4.7-Flash-UD-Q4_K_XL.gguf` by default)
- `.parity_tools/llama.cpp/build/bin/llama-cli`
- `.parity_tools/build_cli/bundle/bin/llamadart_cli`
- `.parity_tools/llama.cpp/build/bin/llama-server`

Run the real-model parity gate (tagged `local-only`):

```bash
dart test --run-skipped -t local-only test/parity_gate_real_local_test.dart
dart test --run-skipped -t local-only test/tool_call_parity_real_local_test.dart
```

Optional environment overrides:

- `LLAMADART_PARITY_MODEL`
- `LLAMADART_PARITY_LLAMA_CPP_CLI`
- `LLAMADART_PARITY_LLAMADART_CLI`
- `LLAMADART_PARITY_PROMPTS_FILE`
- `LLAMADART_PARITY_TIMEOUT_MS`

Tool-call gate environment overrides:

- `LLAMADART_TOOL_PARITY_MODEL`
- `LLAMADART_TOOL_PARITY_LLAMA_SERVER`
- `LLAMADART_TOOL_PARITY_API_SERVER_ENTRY`
- `LLAMADART_TOOL_PARITY_MODEL_ID`
- `LLAMADART_TOOL_PARITY_TIMEOUT_MS`
- `LLAMADART_TOOL_PARITY_STARTUP_TIMEOUT_MS`
- `LLAMADART_TOOL_PARITY_INCLUDE_AUTO`

## Notes

- `--fit` and `--jinja` are accepted for llama.cpp parity.
- `--fit on` automatically trims old turns and caps `--predict` to available
  context budget for the current turn.
- `llamadart` automatically applies chat templates, so `--jinja` is currently a
  compatibility flag.
- `--simple-io` follows llama.cpp simple-io style (banner, `> ` prompts, thinking stream).
- Native backend logging defaults to warning/error level to reduce noise.
- Type `exit` / `quit` / `/exit` to leave interactive mode.
- Interactive slash commands: `/help`, `/regen`, `/read`, `/clear`, `/reset`, `/model`, `/params`.

## Test

```bash
dart test
```
