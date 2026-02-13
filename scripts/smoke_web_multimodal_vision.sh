#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
APP_DIR="$ROOT_DIR/example/chat_app"
BUILD_DIR="$APP_DIR/build/web"
SMOKE_DIR="$ROOT_DIR/.dart_tool/webgpu_smoke"

SMOKE_PORT="${SMOKE_PORT:-4174}"

MODEL_URL="${WEBGPU_SMOKE_MM_MODEL_URL:-https://huggingface.co/ggml-org/SmolVLM-256M-Instruct-GGUF/resolve/main/SmolVLM-256M-Instruct-Q8_0.gguf?download=true}"
MMPROJ_URL="${WEBGPU_SMOKE_MM_PROJ_URL:-https://huggingface.co/ggml-org/SmolVLM-256M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-256M-Instruct-Q8_0.gguf?download=true}"
IMAGE_URL="${WEBGPU_SMOKE_MM_IMAGE_URL:-https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/coco_sample.png?download=true}"
PROMPT="${WEBGPU_SMOKE_MM_PROMPT:-User: <image> Describe this image in one short sentence.<end_of_utterance>\nAssistant:}"
N_CTX="${WEBGPU_SMOKE_N_CTX:-1024}"
MAX_TOKENS="${WEBGPU_SMOKE_MM_MAX_TOKENS:-64}"
THREADS="${WEBGPU_SMOKE_THREADS:-2}"
GPU_LAYERS="${WEBGPU_SMOKE_GPU_LAYERS:-0}"

STARTED_SERVER=0

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Runs a browser smoke test for web multimodal inference (image + text).

Default model pair:
  - ggml-org/SmolVLM-256M-Instruct-GGUF (Q8_0)
  - matching mmproj-SmolVLM-256M-Instruct-Q8_0.gguf

What it checks:
  - Web bridge can load GGUF model and mmproj
  - bridge reports vision capability
  - multimodal completion with an image returns non-empty output

Environment variables:
  WEBGPU_SMOKE_MM_MODEL_URL   Vision model GGUF URL
  WEBGPU_SMOKE_MM_PROJ_URL    Matching mmproj GGUF URL
  WEBGPU_SMOKE_MM_IMAGE_URL   Image URL used for the prompt
  WEBGPU_SMOKE_MM_PROMPT      Prompt text (must include/allow one image marker)
  WEBGPU_SMOKE_N_CTX          Context size (default: 1024)
  WEBGPU_SMOKE_MM_MAX_TOKENS  Max generation tokens (default: 64)
  WEBGPU_SMOKE_THREADS        Threads for bridge runtime (default: 2)
  WEBGPU_SMOKE_GPU_LAYERS     GPU layer request (default: 0)
  SMOKE_PORT                  Local server port (default: 4174)
  SKIP_BUILD                  Set to 1 to skip bridge/flutter builds

Usage:
  ./scripts/smoke_web_multimodal_vision.sh
USAGE
  exit 0
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "[smoke-mm] Building bridge artifacts..."
  "$ROOT_DIR/scripts/build_webgpu_bridge.sh"
  echo "[smoke-mm] Building Flutter web app..."
  (
    cd "$APP_DIR"
    flutter build web --release
  )
fi

mkdir -p "$SMOKE_DIR"
if [[ ! -d "$SMOKE_DIR/node_modules/playwright" ]]; then
  echo "[smoke-mm] Installing Playwright in $SMOKE_DIR ..."
  npm install --prefix "$SMOKE_DIR" playwright
fi

if lsof -i ":$SMOKE_PORT" >/dev/null 2>&1; then
  echo "[smoke-mm] Reusing existing server on port $SMOKE_PORT"
  SERVER_PID=""
else
  echo "[smoke-mm] Starting local server on port $SMOKE_PORT ..."
  python3 -m http.server "$SMOKE_PORT" --directory "$BUILD_DIR" > "/tmp/llamadart_web_smoke_mm.log" 2>&1 &
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

echo "[smoke-mm] Launching headless Chrome for multimodal run ..."

WEBGPU_SMOKE_MM_MODEL_URL="$MODEL_URL" \
WEBGPU_SMOKE_MM_PROJ_URL="$MMPROJ_URL" \
WEBGPU_SMOKE_MM_IMAGE_URL="$IMAGE_URL" \
WEBGPU_SMOKE_MM_PROMPT="$PROMPT" \
WEBGPU_SMOKE_N_CTX="$N_CTX" \
WEBGPU_SMOKE_MM_MAX_TOKENS="$MAX_TOKENS" \
WEBGPU_SMOKE_THREADS="$THREADS" \
WEBGPU_SMOKE_GPU_LAYERS="$GPU_LAYERS" \
SMOKE_PORT="$SMOKE_PORT" \
node -e "const { chromium } = require('$SMOKE_DIR/node_modules/playwright');
const modelUrl = process.env.WEBGPU_SMOKE_MM_MODEL_URL;
const mmprojUrl = process.env.WEBGPU_SMOKE_MM_PROJ_URL;
const imageUrl = process.env.WEBGPU_SMOKE_MM_IMAGE_URL;
const prompt = process.env.WEBGPU_SMOKE_MM_PROMPT;
const nCtx = Number(process.env.WEBGPU_SMOKE_N_CTX || '1024');
const nPredict = Number(process.env.WEBGPU_SMOKE_MM_MAX_TOKENS || '64');
const nThreads = Number(process.env.WEBGPU_SMOKE_THREADS || '2');
const nGpuLayers = Number(process.env.WEBGPU_SMOKE_GPU_LAYERS || '0');
const port = process.env.SMOKE_PORT || '4174';

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const page = await browser.newPage();
  page.on('console', (msg) => console.log('[browser]', msg.text()));
  page.setDefaultTimeout(45 * 60 * 1000);

  await page.goto('http://127.0.0.1:' + port + '/', { waitUntil: 'networkidle' });
  await page.waitForFunction(() => typeof window.LlamaWebGpuBridge === 'function');

  const result = await page.evaluate(async (args) => {
    const bridge = new window.LlamaWebGpuBridge({
      coreModuleUrl: '/webgpu_bridge/llama_webgpu_core.js',
      wasmUrl: '/webgpu_bridge/llama_webgpu_core.wasm',
      nGpuLayers: args.nGpuLayers,
      threads: args.nThreads,
    });

    let modelBucket = -1;
    await bridge.loadModelFromUrl(args.modelUrl, {
      nCtx: args.nCtx,
      nGpuLayers: args.nGpuLayers,
      nThreads: args.nThreads,
      progressCallback: (p) => {
        const loaded = Number(p?.loaded ?? 0);
        const total = Number(p?.total ?? 0);
        if (total <= 0) return;
        const bucket = Math.floor((loaded / total) * 10);
        if (bucket > modelBucket) {
          modelBucket = bucket;
          const pct = Math.min(100, Math.round((loaded / total) * 100));
          console.log('Model load progress: ' + pct + '%');
        }
      },
    });

    console.log('Model loaded; loading multimodal projector ...');
    await bridge.loadMultimodalProjector(args.mmprojUrl);

    const supportsVision = !!bridge.supportsVision();
    const supportsAudio = !!bridge.supportsAudio();

    console.log('Projector ready: vision=' + supportsVision + ', audio=' + supportsAudio);

    const output = await bridge.createCompletion(args.prompt, {
      nPredict: args.nPredict,
      temp: 0.2,
      topK: 40,
      topP: 0.9,
      parts: [{ type: 'image', url: args.imageUrl }],
    });

    await bridge.dispose();

    return {
      supportsVision,
      supportsAudio,
      outputLength: String(output || '').trim().length,
      outputPreview: String(output || '').trim().slice(0, 220),
    };
  }, {
    modelUrl,
    mmprojUrl,
    imageUrl,
    prompt,
    nCtx,
    nPredict,
    nThreads,
    nGpuLayers,
  });

  console.log('WEB_MULTIMODAL_SMOKE ' + JSON.stringify(result));
  await browser.close();

  if (!result.supportsVision) {
    throw new Error('Loaded multimodal projector does not report vision support');
  }

  if (result.outputLength <= 0) {
    throw new Error('Multimodal response is empty');
  }
})().catch((e) => {
  console.error('WEB_MULTIMODAL_SMOKE_ERROR', e && e.stack ? e.stack : e);
  process.exit(1);
});"

echo "Web multimodal smoke passed."
