---
title: Performance Tuning
---

Performance tuning depends on model size, quantization, backend availability,
and context/generation settings.

## Model load tuning (`ModelParams`)

```dart
const modelParams = ModelParams(
  contextSize: 4096,
  gpuLayers: ModelParams.maxGpuLayers,
  preferredBackend: GpuBackend.vulkan,
  numberOfThreads: 0,
  numberOfThreadsBatch: 0,
);
```

Guidelines:

- Start with default `gpuLayers` and lower only if stability issues appear.
- Keep `contextSize` only as large as your use case needs.
- Use backend preference matching your target device/runtime.

## Generation tuning (`GenerationParams`)

```dart
const generationParams = GenerationParams(
  maxTokens: 256,
  temp: 0.7,
  topK: 40,
  topP: 0.9,
  minP: 0.0,
  penalty: 1.1,
);
```

Guidelines:

- Lower `maxTokens` for latency-sensitive paths.
- Lower `temp` for deterministic/extraction tasks.
- Adjust `topP` and `topK` gradually; avoid drastic simultaneous changes.

## Practical diagnostics

- Measure token throughput with representative prompts.
- Validate memory behavior with your real context sizes.
- Check runtime backend and VRAM info where available:

```dart
final backendName = await engine.getBackendName();
final vram = await engine.getVramInfo();
print('$backendName total=${vram.total} free=${vram.free}');
```
