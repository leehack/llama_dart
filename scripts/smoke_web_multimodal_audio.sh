#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
APP_DIR="$ROOT_DIR/example/chat_app"
BUILD_DIR="$APP_DIR/build/web"
SMOKE_DIR="$ROOT_DIR/.dart_tool/webgpu_smoke"

SMOKE_PORT="${SMOKE_PORT:-4175}"

MODEL_URL="${WEBGPU_SMOKE_AUDIO_MODEL_URL:-https://huggingface.co/ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true}"
MMPROJ_URL="${WEBGPU_SMOKE_AUDIO_PROJ_URL:-https://huggingface.co/ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF/resolve/main/mmproj-ultravox-v0_5-llama-3_2-1b-f16.gguf?download=true}"
AUDIO_URL="${WEBGPU_SMOKE_AUDIO_URL:-https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/mtmd/test-2.mp3}"
PROMPT="${WEBGPU_SMOKE_AUDIO_PROMPT:-User: <audio> Transcribe the spoken content in one short sentence.<end_of_utterance>\nAssistant:}"
N_CTX="${WEBGPU_SMOKE_N_CTX:-2048}"
MAX_TOKENS="${WEBGPU_SMOKE_AUDIO_MAX_TOKENS:-96}"
THREADS="${WEBGPU_SMOKE_THREADS:-2}"
GPU_LAYERS="${WEBGPU_SMOKE_GPU_LAYERS:-0}"

STARTED_SERVER=0

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Runs a browser smoke test for web multimodal audio inference.

Default model pair:
  - ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF (Q4_K_M)
  - matching mmproj-ultravox-v0_5-llama-3_2-1b-f16.gguf

What it checks:
  - Web bridge can load GGUF model and mmproj
  - bridge reports audio capability
  - multimodal completion with an audio clip returns non-empty output

Environment variables:
  WEBGPU_SMOKE_AUDIO_MODEL_URL   Audio model GGUF URL
  WEBGPU_SMOKE_AUDIO_PROJ_URL    Matching mmproj GGUF URL
  WEBGPU_SMOKE_AUDIO_URL         Audio URL used for the prompt
  WEBGPU_SMOKE_AUDIO_PROMPT      Prompt text (must include/allow one audio marker)
  WEBGPU_SMOKE_N_CTX             Context size (default: 2048)
  WEBGPU_SMOKE_AUDIO_MAX_TOKENS  Max generation tokens (default: 96)
  WEBGPU_SMOKE_THREADS           Threads for bridge runtime (default: 2)
  WEBGPU_SMOKE_GPU_LAYERS        GPU layer request (default: 0)
  SMOKE_PORT                     Local server port (default: 4175)
  SKIP_BUILD                     Set to 1 to skip bridge/flutter builds

Usage:
  ./scripts/smoke_web_multimodal_audio.sh
USAGE
  exit 0
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "[smoke-mm-audio] Building bridge artifacts..."
  "$ROOT_DIR/scripts/build_webgpu_bridge.sh"
  echo "[smoke-mm-audio] Building Flutter web app..."
  (
    cd "$APP_DIR"
    flutter build web --release
  )
fi

mkdir -p "$SMOKE_DIR"
if [[ ! -d "$SMOKE_DIR/node_modules/playwright" ]]; then
  echo "[smoke-mm-audio] Installing Playwright in $SMOKE_DIR ..."
  npm install --prefix "$SMOKE_DIR" playwright
fi

if lsof -i ":$SMOKE_PORT" >/dev/null 2>&1; then
  echo "[smoke-mm-audio] Reusing existing server on port $SMOKE_PORT"
  SERVER_PID=""
else
  echo "[smoke-mm-audio] Starting local server on port $SMOKE_PORT ..."
  python3 -m http.server "$SMOKE_PORT" --directory "$BUILD_DIR" > "/tmp/llamadart_web_smoke_mm_audio.log" 2>&1 &
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

echo "[smoke-mm-audio] Launching headless Chrome for multimodal run ..."

WEBGPU_SMOKE_AUDIO_MODEL_URL="$MODEL_URL" \
WEBGPU_SMOKE_AUDIO_PROJ_URL="$MMPROJ_URL" \
WEBGPU_SMOKE_AUDIO_URL="$AUDIO_URL" \
WEBGPU_SMOKE_AUDIO_PROMPT="$PROMPT" \
WEBGPU_SMOKE_N_CTX="$N_CTX" \
WEBGPU_SMOKE_AUDIO_MAX_TOKENS="$MAX_TOKENS" \
WEBGPU_SMOKE_THREADS="$THREADS" \
WEBGPU_SMOKE_GPU_LAYERS="$GPU_LAYERS" \
SMOKE_PORT="$SMOKE_PORT" \
node -e "const { chromium } = require('$SMOKE_DIR/node_modules/playwright');
const modelUrl = process.env.WEBGPU_SMOKE_AUDIO_MODEL_URL;
const mmprojUrl = process.env.WEBGPU_SMOKE_AUDIO_PROJ_URL;
const audioUrl = process.env.WEBGPU_SMOKE_AUDIO_URL;
const prompt = process.env.WEBGPU_SMOKE_AUDIO_PROMPT;
const nCtx = Number(process.env.WEBGPU_SMOKE_N_CTX || '2048');
const nPredict = Number(process.env.WEBGPU_SMOKE_AUDIO_MAX_TOKENS || '96');
const nThreads = Number(process.env.WEBGPU_SMOKE_THREADS || '2');
const nGpuLayers = Number(process.env.WEBGPU_SMOKE_GPU_LAYERS || '0');
const port = process.env.SMOKE_PORT || '4175';

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const page = await browser.newPage();
  page.on('console', (msg) => console.log('[browser]', msg.text()));
  page.on('pageerror', (err) => console.error('[pageerror]', err && err.stack ? err.stack : err));
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

    let output = '';
    let generationError = null;

    try {
      output = await bridge.createCompletion(args.prompt, {
        nPredict: args.nPredict,
        temp: 0.2,
        topK: 40,
        topP: 0.9,
        parts: [{ type: 'audio', url: args.audioUrl }],
      });
    } catch (err) {
      let nativeError = '';
      try {
        nativeError = String(
          bridge?._core?.ccall('llamadart_webgpu_last_error', 'string', [], []) || '',
        );
      } catch (_) {
        nativeError = '';
      }

      generationError = {
        message: err && err.message ? String(err.message) : String(err),
        stack: err && err.stack ? String(err.stack) : '',
        nativeError,
      };
    }

    await bridge.dispose();

    return {
      supportsVision,
      supportsAudio,
      outputLength: String(output || '').trim().length,
      outputPreview: String(output || '').trim().slice(0, 220),
      generationError,
    };
  }, {
    modelUrl,
    mmprojUrl,
    audioUrl,
    prompt,
    nCtx,
    nPredict,
    nThreads,
    nGpuLayers,
  });

  console.log('WEB_MULTIMODAL_AUDIO_SMOKE ' + JSON.stringify(result));
  await browser.close();

  if (!result.supportsAudio) {
    throw new Error('Loaded multimodal projector does not report audio support');
  }

  if (result.generationError) {
    const details = [
      result.generationError.message || 'unknown error',
      result.generationError.nativeError
        ? 'native=' + result.generationError.nativeError
        : '',
      result.generationError.stack || '',
    ].filter(Boolean).join(' | ');
    throw new Error('Audio generation failed: ' + details);
  }

  if (result.outputLength <= 0) {
    throw new Error('Multimodal audio response is empty');
  }
})().catch((e) => {
  console.error('WEB_MULTIMODAL_AUDIO_SMOKE_ERROR', e && e.stack ? e.stack : e);
  process.exit(1);
});"

echo "Web multimodal audio smoke passed."
