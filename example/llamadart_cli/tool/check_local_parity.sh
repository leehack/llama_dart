#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

resolve_path() {
  local value="$1"
  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
    return
  fi
  printf '%s\n' "$ROOT_DIR/$value"
}

run_step() {
  local title="$1"
  shift
  printf '\n== %s ==\n' "$title"
  "$@"
}

cd "$ROOT_DIR"

parity_model="${LLAMADART_PARITY_MODEL:-models/GLM-4.7-Flash-UD-Q4_K_XL.gguf}"
parity_llama_cli="${LLAMADART_PARITY_LLAMA_CPP_CLI:-.parity_tools/llama.cpp/build/bin/llama-cli}"
parity_llamadart_cli="${LLAMADART_PARITY_LLAMADART_CLI:-.parity_tools/build_cli/bundle/bin/llamadart_cli}"
tool_llama_server="${LLAMADART_TOOL_PARITY_LLAMA_SERVER:-.parity_tools/llama.cpp/build/bin/llama-server}"
tool_api_entry="${LLAMADART_TOOL_PARITY_API_SERVER_ENTRY:-../llamadart_server/bin/llamadart_server.dart}"

parity_model_abs="$(resolve_path "$parity_model")"
parity_llama_cli_abs="$(resolve_path "$parity_llama_cli")"
parity_llamadart_cli_abs="$(resolve_path "$parity_llamadart_cli")"
tool_llama_server_abs="$(resolve_path "$tool_llama_server")"
tool_api_entry_abs="$(resolve_path "$tool_api_entry")"

missing=()
[[ -f "$parity_model_abs" ]] || missing+=("model: $parity_model_abs")
[[ -x "$parity_llama_cli_abs" ]] || missing+=("llama-cli: $parity_llama_cli_abs")
[[ -x "$parity_llamadart_cli_abs" ]] || missing+=("llamadart_cli: $parity_llamadart_cli_abs")
[[ -x "$tool_llama_server_abs" ]] || missing+=("llama-server: $tool_llama_server_abs")
[[ -f "$tool_api_entry_abs" ]] || missing+=("api entry: $tool_api_entry_abs")

if (( ${#missing[@]} > 0 )); then
  printf 'Missing required local parity assets:\n'
  for item in "${missing[@]}"; do
    printf '  - %s\n' "$item"
  done
  printf '\nBuild prerequisites first (see README parity sections).\n'
  exit 66
fi

export LLAMADART_PARITY_MODEL="$parity_model_abs"
export LLAMADART_PARITY_LLAMA_CPP_CLI="$parity_llama_cli_abs"
export LLAMADART_PARITY_LLAMADART_CLI="$parity_llamadart_cli_abs"
export LLAMADART_TOOL_PARITY_MODEL="$parity_model_abs"
export LLAMADART_TOOL_PARITY_LLAMA_SERVER="$tool_llama_server_abs"
export LLAMADART_TOOL_PARITY_API_SERVER_ENTRY="$tool_api_entry_abs"

run_step "Get dependencies" dart pub get
run_step "Static analysis" dart analyze
run_step "Default tests" dart test
run_step \
  "Transcript parity gate" \
  dart test --run-skipped -t local-only test/parity_gate_real_local_test.dart
run_step \
  "Tool-call parity gate" \
  dart test --run-skipped -t local-only test/tool_call_parity_real_local_test.dart

printf '\nLocal parity check completed.\n'
