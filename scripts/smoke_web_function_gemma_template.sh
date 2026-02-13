#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
APP_DIR="$ROOT_DIR/example/chat_app"
BUILD_DIR="$APP_DIR/build/web"
SMOKE_DIR="$ROOT_DIR/.dart_tool/webgpu_smoke"
SMOKE_PORT="${SMOKE_PORT:-4173}"
MODEL_URL="${WEBGPU_SMOKE_MODEL_URL:-https://huggingface.co/unsloth/functiongemma-270m-it-GGUF/resolve/main/functiongemma-270m-it-Q4_K_M.gguf?download=true}"
STARTED_SERVER=0

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Verifies FunctionGemma chat template metadata on the web bridge path.

What it checks:
  - tokenizer.chat_template is present and not truncated
  - template includes FunctionGemma marker <start_function_call>

Environment variables:
  WEBGPU_SMOKE_MODEL_URL   GGUF URL to test
  SMOKE_PORT               HTTP port for local server (default: 4173)
  SKIP_BUILD               Set to 1 to skip bridge/flutter builds

Usage:
  ./scripts/smoke_web_function_gemma_template.sh
USAGE
  exit 0
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "[smoke] Building bridge artifacts..."
  "$ROOT_DIR/scripts/build_webgpu_bridge.sh"
  echo "[smoke] Building Flutter web app..."
  (
    cd "$APP_DIR"
    flutter build web --release
  )
fi

mkdir -p "$SMOKE_DIR"
if [[ ! -d "$SMOKE_DIR/node_modules/playwright" ]]; then
  echo "[smoke] Installing Playwright in $SMOKE_DIR ..."
  npm install --prefix "$SMOKE_DIR" playwright
fi

if lsof -i ":$SMOKE_PORT" >/dev/null 2>&1; then
  echo "[smoke] Reusing existing server on port $SMOKE_PORT"
  SERVER_PID=""
else
  echo "[smoke] Starting local server on port $SMOKE_PORT ..."
  python3 -m http.server "$SMOKE_PORT" --directory "$BUILD_DIR" > "/tmp/llamadart_web_smoke.log" 2>&1 &
  SERVER_PID=$!
  STARTED_SERVER=1
fi

cleanup() {
  if [[ "$STARTED_SERVER" == "1" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

sleep 2

echo "[smoke] Launching headless Chrome and loading model ..."

node -e "const { chromium } = require('$SMOKE_DIR/node_modules/playwright');
const modelUrl = process.env.WEBGPU_SMOKE_MODEL_URL || '$MODEL_URL';
const port = process.env.SMOKE_PORT || '$SMOKE_PORT';
(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const page = await browser.newPage();
  page.on('console', (msg) => console.log('[browser]', msg.text()));
  page.setDefaultTimeout(30 * 60 * 1000);
  await page.goto('http://127.0.0.1:' + port + '/', { waitUntil: 'networkidle' });
  await page.waitForFunction(() => typeof window.LlamaWebGpuBridge === 'function');

  const result = await page.evaluate(async (url) => {
    const bridge = new window.LlamaWebGpuBridge({
      coreModuleUrl: '/webgpu_bridge/llama_webgpu_core.js',
      wasmUrl: '/webgpu_bridge/llama_webgpu_core.wasm',
      nGpuLayers: 0,
      threads: 2,
    });

    console.log('Bridge ready; starting model fetch and load');
    let lastBucket = -1;
    await bridge.loadModelFromUrl(url, {
      nCtx: 512,
      nGpuLayers: 0,
      nThreads: 2,
      progressCallback: (p) => {
        const loaded = Number(p?.loaded ?? 0);
        const total = Number(p?.total ?? 0);
        if (total <= 0) return;
        const bucket = Math.floor((loaded / total) * 10);
        if (bucket > lastBucket) {
          lastBucket = bucket;
          const pct = Math.min(100, Math.round((loaded / total) * 100));
          console.log('Model load progress: ' + pct + '%');
        }
      },
    });
    console.log('Model loaded; reading metadata');
    const template = bridge.getModelMetadata()['tokenizer.chat_template'] || '';
    const out = {
      templateLength: template.length,
      hasStartFunctionCall: template.includes('<start_function_call>'),
      hasStartOfTurn: template.includes('<start_of_turn>'),
      hasImEnd: template.includes('<|im_end|>'),
    };

    await bridge.dispose();
    return out;
  }, modelUrl);

  console.log('FUNCTION_GEMMA_TEMPLATE_SMOKE ' + JSON.stringify(result));
  await browser.close();

  if (result.templateLength <= 8192) {
    throw new Error('tokenizer.chat_template looks truncated (<= 8192 bytes)');
  }
  if (!result.hasStartFunctionCall) {
    throw new Error('tokenizer.chat_template is missing <start_function_call> marker');
  }
})().catch((e) => {
  console.error('FUNCTION_GEMMA_TEMPLATE_SMOKE_ERROR', e && e.stack ? e.stack : e);
  process.exit(1);
});"

echo "FunctionGemma web template smoke passed."
