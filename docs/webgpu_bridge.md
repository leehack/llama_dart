# WebGPU Bridge Contract (Experimental)

This document defines the JavaScript contract expected by
`WebGpuLlamaBackend`.

The Dart backend looks for a global constructor named
`LlamaWebGpuBridge`.

## Quick Prototype Build

This repository includes an experimental WebGPU bridge build scaffold:

```bash
./scripts/build_webgpu_bridge.sh
```

Default output files:

- `example/chat_app/web/webgpu_bridge/llama_webgpu_core.js`
- `example/chat_app/web/webgpu_bridge/llama_webgpu_core.wasm`
- `example/chat_app/web/webgpu_bridge/llama_webgpu_bridge.js`

Requirements:

- Emscripten SDK (`emcmake`, `emcc`) in `PATH`
- Local `llama.cpp` source at `third_party/llama_cpp`
  (or set `LLAMA_CPP_DIR=/path/to/llama.cpp`)

The build script also auto-detects a sibling checkout at `../llama.cpp`.

The current bridge is a prototype focused on validating WebGPU build and
runtime wiring. It now performs basic llama.cpp load + generation, but is not
production hardened yet.

## Bridge Repositories

Planned split for reusable bridge distribution:

- Source/build repo: `leehack/llama-web-bridge`
- CDN assets repo: `leehack/llama-web-bridge-assets`

`llamadart` keeps the Dart backend adapter and consumes published bridge
artifacts.

## Distribution Model (Local First + CDN Fallback)

`example/chat_app/web/index.html` uses a local-first loader:

1. Try `./webgpu_bridge/llama_webgpu_bridge.js`
2. Fallback to jsDelivr:
   `https://cdn.jsdelivr.net/gh/leehack/llama-web-bridge-assets@<tag>/llama_webgpu_bridge.js`

Default tag in the example is `main`. For reproducible production builds,
override it to a pinned release tag.

You can override at runtime by defining globals before the loader script:

```html
<script>
  window.__llamadartBridgeAssetsRepo = 'leehack/llama-web-bridge-assets';
  window.__llamadartBridgeAssetsTag = 'v0.1.0';
</script>
```

## Fetching Pinned Assets for Self-Hosted Builds

To bundle prebuilt bridge artifacts into your own web app at build time:

```bash
WEBGPU_BRIDGE_ASSETS_TAG=v0.1.0 ./scripts/fetch_webgpu_bridge_assets.sh
```

This script downloads files into `example/chat_app/web/webgpu_bridge/` and
verifies checksums when `sha256sums.txt` is available.

## CI Gate (WASM Build)

`CI` now includes a dedicated `Build WebGPU Bridge (WASM)` job that:

- resolves the pinned llama.cpp tag from `hook/build.dart`
- clones llama.cpp source
- builds the bridge with Emscripten
- verifies expected wasm/js artifacts exist

## Publishing Bridge Assets

Use the `Publish WebGPU Bridge Assets` GitHub Actions workflow
(`.github/workflows/publish_webgpu_bridge_assets.yml`) to build and publish
artifacts to the CDN asset repo.

Required workflow inputs:

- `assets_tag` (recommended semver tag, for example `v0.1.0`)
- `assets_repo` (`owner/repo`, defaults to `leehack/llama-web-bridge-assets`)
- optional `llama_cpp_tag` override

Required secret:

- `WEBGPU_BRIDGE_ASSETS_PAT` with write access to the target assets repo

### Example app bootstrap

`example/chat_app/web/index.html` loads the bridge by default using local-first
then CDN fallback behavior.

Equivalent loader snippet:

```html
<script type="module">
  const localUrl = './webgpu_bridge/llama_webgpu_bridge.js';
  const cdnUrl = 'https://cdn.jsdelivr.net/gh/leehack/llama-web-bridge-assets@v0.1.0/llama_webgpu_bridge.js';

  const load = async (url) => {
    const mod = await import(url);
    if (!mod?.LlamaWebGpuBridge) throw new Error('missing export');
    window.LlamaWebGpuBridge = mod.LlamaWebGpuBridge;
  };

  load(localUrl).catch(() => load(cdnUrl));
</script>
```

## FunctionGemma regression smoke

Run this local smoke command to verify FunctionGemma metadata is not truncated
on the bridge path:

```bash
./scripts/smoke_web_function_gemma_template.sh
```

## Multimodal vision smoke

Run this local smoke command to verify an image+text multimodal request on the
web bridge path:

```bash
./scripts/smoke_web_multimodal_vision.sh
```

By default it uses a small SmolVLM GGUF + matching mmproj pair from
`ggml-org/SmolVLM-256M-Instruct-GGUF`.

## Multimodal audio smoke

Run this local smoke command to verify an audio+text multimodal request on the
web bridge path:

```bash
./scripts/smoke_web_multimodal_audio.sh
```

By default it uses Ultravox 0.5 1B + matching mmproj from
`ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF` with the sample MP3 from
`llama.cpp/tools/mtmd/test-2.mp3`.

Audio preprocessing in the bridge build is currently forced to single-threaded
mode for browser wasm compatibility.

## Expected global

```js
window.LlamaWebGpuBridge = class LlamaWebGpuBridge {
  constructor(config) {}
};
```

## Required methods

`WebGpuLlamaBackend` can use these methods if present:

- `loadModelFromUrl(url, { nCtx, nThreads, nGpuLayers, useCache, progressCallback })`
- `loadMultimodalProjector(url)`
- `unloadMultimodalProjector()`
- `supportsVision()`
- `supportsAudio()`
- `createCompletion(prompt, { nPredict, temp, topK, topP, penalty, seed, grammar, onToken, parts, signal })`
- `tokenize(text, addSpecial)`
- `detokenize(tokens, special)`
- `getModelMetadata()`
- `getContextSize()`
- `cancel()`
- `dispose()`
- `applyChatTemplate(messages, addAssistant, customTemplate)`
- `isGpuActive()`
- `getBackendName()`

## Notes

- The backend remains GGUF URL based (`modelLoadFromUrl`).
- If bridge activation fails, model loading fails (no alternate web backend).
- During this experimental phase, the bridge can be supplied either by:
  - a preloaded global `window.LlamaWebGpuBridge`, or
  - dynamic import URL passed to `WebGpuLlamaBackend(bridgeScriptUrl: ...)`.
- The prototype bridge now executes real llama.cpp prompt + generation calls
  through exported C functions.
- Tokenize/detokenize now call native llama.cpp APIs through bridge exports.
- Generation cancellation is wired through both JS abort signals and the native
  runtime cancel callback.

## Core C exports used by JS bridge

The generated `llama_webgpu_core.js/.wasm` module currently exports:

- `llamadart_webgpu_probe()`
- `llamadart_webgpu_backends_json()`
- `llamadart_webgpu_last_error()`
- `llamadart_webgpu_load_model(path, nCtx, nThreads, nGpuLayers)`
- `llamadart_webgpu_mmproj_load(path)`
- `llamadart_webgpu_mmproj_free()`
- `llamadart_webgpu_mmproj_supports_vision()`
- `llamadart_webgpu_mmproj_supports_audio()`
- `llamadart_webgpu_media_clear_pending()`
- `llamadart_webgpu_media_add_file(path)`
- `llamadart_webgpu_media_add_encoded(bytes, length)`
- `llamadart_webgpu_media_add_rgb(width, height, bytes, length)`
- `llamadart_webgpu_media_add_audio_f32(samples, sampleCount)`
- `llamadart_webgpu_tokenize_to_json(text, addSpecial)`
- `llamadart_webgpu_last_tokens_json()`
- `llamadart_webgpu_detokenize_from_json(tokens, special)`
- `llamadart_webgpu_last_detokenized()`
- `llamadart_webgpu_generate(prompt, nPredict, temp, topK, topP, repeatPenalty, seed)`
- `llamadart_webgpu_begin_generation(prompt, temp, topK, topP, repeatPenalty, seed)`
- `llamadart_webgpu_next_token()`
- `llamadart_webgpu_last_piece()`
- `llamadart_webgpu_end_generation()`
- `llamadart_webgpu_last_output()`
- `llamadart_webgpu_get_context_size()`
- `llamadart_webgpu_model_meta_json()`
- `llamadart_webgpu_shutdown()`

## Low-latency tuning notes

For first-token latency in this prototype bridge:

- Use a smaller context (`nCtx: 512` or `1024`) for quick responses.
- Keep thread count modest (`threads: 2` to `4`) to reduce scheduling overhead.
- Use lower `nPredict` for interactive responses (e.g. 32-64 tokens).

In a local smoke run with `functiongemma-270m-it-Q4_K_M.gguf`:

- `nCtx=1024, threads=4`: first token ~288 ms
- `nCtx=512, threads=2`: first token ~208 ms

## Minimal skeleton

```js
export class LlamaWebGpuBridge {
  constructor(config = {}) {
    this.config = config;
  }

  async loadModelFromUrl(url, options = {}) {}

  async createCompletion(prompt, options = {}) {
    // Call options.onToken(Uint8Array, currentText) while generating.
  }

  async tokenize(text, addSpecial = true) {
    return new Uint32Array();
  }

  async detokenize(tokens, special = false) {
    return '';
  }

  getModelMetadata() {
    return {};
  }

  getContextSize() {
    return 0;
  }

  isGpuActive() {
    return true;
  }

  getBackendName() {
    return 'WebGPU (Bridge)';
  }

  cancel() {}

  async dispose() {}

  async applyChatTemplate(messages, addAssistant = true, customTemplate) {
    return '';
  }
}
```
