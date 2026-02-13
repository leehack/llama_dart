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

Default pinned tag in the example is `v0.1.1`.

To vendor pinned assets into local app web files:

```bash
WEBGPU_BRIDGE_ASSETS_TAG=v0.1.1 ./scripts/fetch_webgpu_bridge_assets.sh
```

## Runtime Override Knobs

You can override CDN source/version before the bridge loader runs:

```html
<script>
  window.__llamadartBridgeAssetsRepo = 'leehack/llama-web-bridge-assets';
  window.__llamadartBridgeAssetsTag = 'v0.1.1';
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
