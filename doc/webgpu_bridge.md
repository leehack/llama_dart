# WebGPU Bridge Contract (Experimental)

This document defines the JavaScript contract expected by
`WebGpuLlamaBackend` in `llamadart`.

## Ownership

- Bridge source/build CI: `leehack/llama-web-bridge`
- Published CDN assets: `leehack/llama-web-bridge-assets`

`llamadart` is a bridge consumer. It does not own bridge build/publish
pipelines.

## Distribution Model (Local First + CDN Fallback)

`example/chat_app/web/index.html` loads bridge runtime in this order:

1. Local: `./webgpu_bridge/llama_webgpu_bridge.js`
2. CDN fallback:
   `https://cdn.jsdelivr.net/gh/leehack/llama-web-bridge-assets@<tag>/llama_webgpu_bridge.js`

Default pinned tag in the example is `v0.1.3`.

For broader browser coverage in this repository, fetched/local assets are patched
to a universal Safari-compatible gate by default (`MIN_SAFARI_VERSION=170400`).
`example/chat_app/web/index.html` also applies the same Safari guard patch at
runtime before bridge initialization, covering CDN fallback paths.
The fetch patch flow also updates legacy bridge stream chunk assembly to clone
read chunks, preventing Safari reader buffer reuse from corrupting downloaded
model bytes.

To vendor pinned assets into local app web files:

```bash
WEBGPU_BRIDGE_ASSETS_TAG=v0.1.3 ./scripts/fetch_webgpu_bridge_assets.sh
```

Optional compatibility env vars:

- `WEBGPU_BRIDGE_PATCH_SAFARI_COMPAT=1|0` (default `1`)
- `WEBGPU_BRIDGE_MIN_SAFARI_VERSION=<packed>` (default `170400`)

## Model Caching

Bridge model fetches use browser Cache Storage by default (`useCache: true` in
web backend load options).

- First load of a model URL fetches from network and stores into cache.
- Subsequent loads of the same URL can be served from cache.
- Cache behavior/availability depends on browser storage quota and private mode
  policies.

## Browser Compatibility Targets

Current bundled bridge runtime targets:

- Chrome >= 128
- Firefox >= 129
- Safari >= 17.4 (patched universal gate in this repo)

WebGPU availability still depends on browser/device capabilities and local user
settings. CPU mode remains available through the same bridge runtime path.

Current safeguard in `llamadart` web backend:

- Legacy bridge assets (without adaptive Safari probe support) are forced to
  CPU by default on Safari when GPU layers are requested.
- Adaptive bridge assets can keep Safari GPU enabled and run a short generation
  probe; if output looks unstable, they cap GPU layers and/or auto-fallback to
  CPU.
- You can still bypass the legacy safeguard by setting
  `window.__llamadartAllowSafariWebGpu = true` before model load.

## Runtime Override Knobs

You can override CDN source/version before the bridge loader runs:

```html
<script>
  window.__llamadartBridgeAssetsRepo = 'leehack/llama-web-bridge-assets';
  window.__llamadartBridgeAssetsTag = 'v0.1.3';
</script>
```

## Expected Global

```js
window.LlamaWebGpuBridge = class LlamaWebGpuBridge {
  constructor(config) {}
};
```

## Required Methods

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

- Web backend remains GGUF URL-based (`modelLoadFromUrl`).
- If bridge activation fails, model loading fails (no alternate web backend).
- During this experimental phase, bridge can be supplied by:
  - preloaded global `window.LlamaWebGpuBridge`, or
  - dynamic import URL via `WebGpuLlamaBackend(bridgeScriptUrl: ...)`.
- `loadMultimodalProjector` and `supportsVision` / `supportsAudio` are active on web.
