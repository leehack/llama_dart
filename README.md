# llamadart

[![Pub Version](https://img.shields.io/pub/v/llamadart?logo=dart&color=blue)](https://pub.dev/packages/llamadart)
[![codecov](https://codecov.io/gh/leehack/llamadart/graph/badge.svg?token=)](https://codecov.io/gh/leehack/llamadart)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)
[![GitHub](https://img.shields.io/github/stars/leehack/llamadart?style=social)](https://github.com/leehack/llamadart)

**llamadart** is a high-performance Dart and Flutter plugin for [llama.cpp](https://github.com/ggml-org/llama.cpp). It lets you run GGUF LLMs locally across native platforms and web (CPU/WebGPU bridge path).

## ✨ Features

- 🚀 **High Performance**: Powered by `llama.cpp` kernels.
- 🛠️ **Zero Configuration**: Uses Pure Native Assets; no manual CMake or platform project edits.
- 📱 **Cross-Platform**: Android, iOS, macOS, Linux, Windows, and web.
- ⚡ **GPU Acceleration**:
  - Apple: Metal
  - Android/Linux/Windows: Vulkan by default, with optional target-specific modules
  - Web: WebGPU via bridge runtime (with CPU fallback)
- 🖼️ **Multimodal Support**: Vision/audio model runtime support.
- **LoRA Support**: Runtime GGUF adapter application.
- 🔇 **Split Logging Control**: Dart logs and native logs can be configured independently.

---

## 🚀 Start Here (Plugin Users)

### 1. Add dependency

```yaml
dependencies:
  llamadart: ^0.6.0
```

### 2. Run with defaults

On first `dart run` / `flutter run`, `llamadart` will:
1. Detect platform/architecture.
2. Download the matching native runtime bundle from [`leehack/llamadart-native`](https://github.com/leehack/llamadart-native).
3. Wire it into your app via native assets.

No manual binary download or C++ build steps are required.

### 3. Optional: choose backend modules per target (non-Apple)

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_backends:
        platforms:
          android-arm64: [vulkan] # opencl is opt-in
          linux-x64: [vulkan, cuda]
          windows-x64: [vulkan, cuda]
```

If a requested module is unavailable for a target, `llamadart` logs a warning and falls back to target defaults.

### 4. Minimal first model load

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = LlamaEngine(LlamaBackend());
  try {
    await engine.loadModel('path/to/model.gguf');
    await for (final token in engine.generate('Hello')) {
      print(token);
    }
  } finally {
    await engine.dispose();
  }
}
```

---

## ✅ Platform Defaults and Configurability

| Target | Default runtime backends | Configurable in `pubspec.yaml` |
|--------|--------------------------|---------------------------------|
| android-arm64 / android-x64 | cpu, vulkan | yes |
| linux-arm64 / linux-x64 | cpu, vulkan | yes |
| windows-arm64 / windows-x64 | cpu, vulkan | yes |
| macos-arm64 / macos-x86_64 | cpu, METAL | no |
| ios-arm64 / ios simulators | cpu, METAL | no |
| web | webgpu, cpu (bridge router) | n/a |

<details>
<summary>Full module matrix (available modules by target)</summary>

Backend module matrix from pinned native tag `b8099`:

| Target | Available backend modules in bundle |
|--------|-------------------------------------|
| android-arm64 | cpu, vulkan, opencl |
| android-x64 | cpu, vulkan, opencl |
| linux-arm64 | cpu, vulkan, blas |
| linux-x64 | cpu, vulkan, blas, cuda, hip |
| windows-arm64 | cpu, vulkan, blas |
| windows-x64 | cpu, vulkan, blas, cuda |
| macos-arm64 | n/a (single consolidated native lib) |
| macos-x86_64 | n/a (single consolidated native lib) |
| ios-arm64 | n/a (single consolidated native lib) |
| ios-arm64-sim | n/a (single consolidated native lib) |
| ios-x86_64-sim | n/a (single consolidated native lib) |

</details>

Recognized backend names for `llamadart_native_backends`:

- `vulkan`
- `cpu`
- `opencl`
- `cuda`
- `blas`
- `metal`
- `hip`

Accepted aliases:

- `vk` -> `vulkan`
- `ocl` -> `opencl`
- `open-cl` -> `opencl`

Notes:

- Module availability depends on the pinned native release bundle and may change when the native tag updates.
- Configurable targets always keep `cpu` bundled as a fallback.
- Android keeps OpenCL available for opt-in, but defaults to Vulkan.
- `KleidiAI` and `ZenDNN` are CPU-path optimizations in `llama.cpp`, not standalone backend module files.
- `example/chat_app` backend settings show runtime-detected backends/devices (what initialized), not only bundled module files.
- `example/chat_app` no longer exposes an `Auto` selector; it lists concrete detected backends.
- Legacy saved `Auto` preferences in `example/chat_app` are auto-migrated at runtime.
- Apple targets are intentionally non-configurable in this hook path and use consolidated native libraries.
- The native-assets hook refreshes emitted files each build; if you are upgrading from older cached outputs, run `flutter clean` once.

If you change `llamadart_native_backends`, run `flutter clean` once so stale native-asset outputs do not override new bundle selection.

---

## 🌐 Web Backend Notes (Router)

The default web backend uses `WebGpuLlamaBackend` as a router for WebGPU and CPU paths.

- Web mode is currently experimental and depends on an external JS bridge runtime.
- Bridge API contract: [WebGPU bridge contract](https://github.com/leehack/llamadart/blob/main/doc/webgpu_bridge.md).
- Runtime assets are published via:
  - [`leehack/llama-web-bridge`](https://github.com/leehack/llama-web-bridge)
  - [`leehack/llama-web-bridge-assets`](https://github.com/leehack/llama-web-bridge-assets)
- `example/chat_app` prefers local bridge assets, then falls back to jsDelivr.
- Browser Cache Storage is used for repeated model loads when `useCache` is enabled (default).
- `loadMultimodalProjector` is supported on web for URL-based model/mmproj assets.
- `supportsVision` and `supportsAudio` reflect loaded projector capabilities.
- LoRA runtime adapters are not currently supported on web.
- `setLogLevel` / `setNativeLogLevel` changes take effect on next model load.

If your app targets both native and web, gate feature toggles by capability checks.

---

## 🐧 Linux Runtime Prerequisites

Linux targets may need host runtime dependencies based on selected backends:

- `cpu`: no extra GPU runtime dependency.
- `vulkan`: Vulkan loader + valid GPU driver/ICD.
- `blas`: OpenBLAS runtime (`libopenblas.so.0`).
- `cuda` (linux-x64): NVIDIA driver + compatible CUDA runtime libs.
- `hip` (linux-x64): ROCm runtime libs (for example `libhipblas.so.2`).

Example (Ubuntu/Debian):

```bash
sudo apt-get update
sudo apt-get install -y libvulkan1 vulkan-tools libopenblas0
```

Example (Fedora/RHEL/CentOS):

```bash
sudo dnf install -y vulkan-loader vulkan-tools openblas
```

Example (Arch Linux):

```bash
sudo pacman -S --needed vulkan-icd-loader vulkan-tools openblas
```

Quick verification:

```bash
for f in .dart_tool/lib/libggml-*.so; do
  LD_LIBRARY_PATH=.dart_tool/lib ldd "$f" | grep "not found" || true
done
```

<details>
<summary>Docker-based Linux link/runtime validation (power users and maintainers)</summary>

```bash
# 1) Prepare linux-x64 native modules in .dart_tool/lib
docker run --rm --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -v "/absolute/path/to/model.gguf:/models/your.gguf:ro" \
  -w /workspace/example/llamadart_cli \
  ghcr.io/cirruslabs/flutter:stable \
  bash -lc '
    rm -rf .dart_tool /workspace/.dart_tool/lib &&
    dart pub get &&
    dart run bin/llamadart_cli.dart --model /models/your.gguf --no-interactive --predict 1 --gpu-layers 0
  '

# 2) Baseline CPU/Vulkan/BLAS link-check
docker run --rm --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -w /workspace/example/llamadart_cli \
  ghcr.io/cirruslabs/flutter:stable \
  bash -lc '
    apt-get update &&
    apt-get install -y --no-install-recommends libvulkan1 vulkan-tools libopenblas0 &&
    /workspace/scripts/check_native_link_deps.sh .dart_tool/lib \
      libggml-cpu.so libggml-vulkan.so libggml-blas.so
  '

# Optional CUDA module link-check without GPU execution
docker build --platform linux/amd64 \
  -f docker/validation/Dockerfile.cuda-linkcheck \
  -t llamadart-linkcheck-cuda .

docker run --rm --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -w /workspace/example/llamadart_cli \
  llamadart-linkcheck-cuda \
  bash -lc '
    /workspace/scripts/check_native_link_deps.sh .dart_tool/lib \
      libggml-cuda.so libggml-blas.so libggml-vulkan.so
  '

# Optional HIP module link-check without GPU execution
docker build --platform linux/amd64 \
  -f docker/validation/Dockerfile.hip-linkcheck \
  -t llamadart-linkcheck-hip .

docker run --rm --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -w /workspace/example/llamadart_cli \
  llamadart-linkcheck-hip \
  bash -lc '
    export LD_LIBRARY_PATH=".dart_tool/lib:/opt/rocm/lib:/opt/rocm-6.3.0/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}" &&
    /workspace/scripts/check_native_link_deps.sh .dart_tool/lib libggml-hip.so
  '
```

Notes:

- Docker can validate module packaging and shared-library resolution.
- GPU execution still requires host device/runtime passthrough.
- CUDA validation requires NVIDIA runtime-enabled container execution.
- HIP validation requires ROCm passthrough.

</details>

---

## 🏗️ Runtime Repositories (Maintainer Context)

llamadart has decoupled runtime ownership:

- Native source/build/release:
  [`leehack/llamadart-native`](https://github.com/leehack/llamadart-native)
- Web bridge source/build:
  [`leehack/llama-web-bridge`](https://github.com/leehack/llama-web-bridge)
- Web bridge runtime assets:
  [`leehack/llama-web-bridge-assets`](https://github.com/leehack/llama-web-bridge-assets)
- This repository consumes pinned published artifacts from those repositories.

Core abstractions in this package:

- `LlamaEngine`: orchestrates model lifecycle, generation, and templates.
- `ChatSession`: stateful helper for chat history and sliding-window context.
- `LlamaBackend`: platform-agnostic backend interface with native/web routing.

---
## ⚠️ Breaking Changes in 0.6.0

If you are upgrading from `0.5.x`, read:

- [MIGRATION.md](https://github.com/leehack/llamadart/blob/main/MIGRATION.md)

High-impact changes:

- Removed legacy custom template-handler/override APIs from `ChatTemplateEngine`:
  - `registerHandler(...)`, `unregisterHandler(...)`, `clearCustomHandlers(...)`
  - `registerTemplateOverride(...)`, `unregisterTemplateOverride(...)`,
    `clearTemplateOverrides(...)`
- Removed legacy per-call handler routing:
  - `customHandlerId` and parse `handlerId`
- Render/parse paths no longer silently downgrade to content-only output when
  a handler/parser fails; failures are surfaced to the caller.

---

## 🛠️ Usage

### 1. Simple Usage

The easiest way to get started is by using the default `LlamaBackend`.

```dart
import 'package:llamadart/llamadart.dart';

void main() async {
  // Automatically selects Native or Web backend
  final engine = LlamaEngine(LlamaBackend());

  try {
    // Initialize with a local GGUF model
    await engine.loadModel('path/to/model.gguf');

    // Generate text (streaming)
    await for (final token in engine.generate('The capital of France is')) {
      print(token);
    }
  } finally {
    // CRITICAL: Always dispose the engine to release native resources
    await engine.dispose();
  }
}
```

### 2. Advanced Usage (ChatSession)

Use `ChatSession` for most chat applications. It automatically manages conversation history, system prompts, and handles context window limits.

```dart
import 'package:llamadart/llamadart.dart';

void main() async {
  final engine = LlamaEngine(LlamaBackend());

  try {
    await engine.loadModel('model.gguf');

    // Create a session with a system prompt
    final session = ChatSession(
      engine, 
      systemPrompt: 'You are a helpful assistant.',
    );

    // Send a message
    await for (final chunk in session.create([LlamaTextContent('What is the capital of France?')])) {
      stdout.write(chunk.choices.first.delta.content ?? '');
    }
  } finally {
    await engine.dispose();
  }
}
```

### 3. Tool Calling
  
`llamadart` supports intelligent tool calling where the model can use external functions to help it answer questions.
  
```dart
final tools = [
  ToolDefinition(
    name: 'get_weather',
    description: 'Get the current weather',
    parameters: [
      ToolParam.string('location', description: 'City name', required: true),
    ],
    handler: (params) async {
      final location = params.getRequiredString('location');
      return 'It is 22°C and sunny in $location';
    },
  ),
];

final session = ChatSession(engine);

// Pass tools per-request
await for (final chunk in session.create(
  [LlamaTextContent("how's the weather in London?")],
  tools: tools,
)) {
  final delta = chunk.choices.first.delta;
  if (delta.content != null) stdout.write(delta.content);
}
```

Notes:

- Built-in template handlers automatically select model-specific tool-call grammar and parser behavior; you usually do not need to set `GenerationParams.grammar` manually for normal tool use.
- Some handlers use lazy grammar activation (triggered when a tool-call prefix appears) to match llama.cpp behavior.
- If you implement a custom handler grammar, prefer Dart raw strings (`r'''...'''`) for GBNF blocks to avoid escaping bugs.

### 3.5 Template Routing (Strict llama.cpp parity)

Template/render/parse routing is intentionally strict to match llama.cpp:

- Built-in format detection and built-in handlers are always used.
- `customTemplate` is supported per call.
- Legacy custom handler/override registry APIs were removed.

If you need deterministic template customization, use `customTemplate`,
`chatTemplateKwargs`, and `templateNow`:

```dart
final result = await engine.chatTemplate(
  [
    const LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'hello',
    ),
  ],
  customTemplate: '{{ "CUSTOM:" ~ messages[0]["content"] }}',
  chatTemplateKwargs: {'my_flag': true, 'tenant': 'demo'},
  templateNow: DateTime.utc(2026, 1, 1),
);

print(result.prompt);
```

### 3.6 Logging Control

Use separate log levels for Dart and native output when debugging:

```dart
import 'package:llamadart/llamadart.dart';

final engine = LlamaEngine(LlamaBackend());

// Dart-side logs (template routing, parser diagnostics, etc.)
await engine.setDartLogLevel(LlamaLogLevel.info);

// Native llama.cpp / ggml logs
await engine.setNativeLogLevel(LlamaLogLevel.warn);

// Convenience: set both at once
await engine.setLogLevel(LlamaLogLevel.none);
```

### 4. Multimodal Usage (Vision/Audio)

`llamadart` supports multimodal models (vision and audio) using `LlamaChatMessage.withContent`.

```dart
import 'package:llamadart/llamadart.dart';

void main() async {
  final engine = LlamaEngine(LlamaBackend());
  
  try {
    await engine.loadModel('vision-model.gguf');
    await engine.loadMultimodalProjector('mmproj.gguf');

    final session = ChatSession(engine);

    // Create a multimodal message
    final messages = [
      LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: [
          LlamaImageContent(path: 'image.jpg'),
          LlamaTextContent('What is in this image?'),
        ],
      ),
    ];

    // Use stateless engine.create for one-off multimodal requests
    final response = engine.create(messages);
    await for (final chunk in response) {
      stdout.write(chunk.choices.first.delta.content ?? '');
    }
  } finally {
    await engine.dispose();
  }
}
```

Web-specific note:

- Load model/mmproj with URL-based assets (`loadModelFromUrl` + URL projector).
- For user-picked browser files, send media as bytes (`LlamaImageContent(bytes: ...)`,
  `LlamaAudioContent(bytes: ...)`) rather than local file paths.

### 💡 Model-Specific Notes

#### Moondream 2 & Phi-2
These models use a unique architecture where the Start-of-Sequence (BOS) and End-of-Sequence (EOS) tokens are identical. `llamadart` includes a specialized handler for these models that:
- **Disables Auto-BOS**: Prevents the model from stopping immediately upon generation.
- **Manual Templates**: Automatically applies the required `Question: / Answer:` format if the model metadata is missing a chat template.
- **Stop Sequences**: Injects `Question:` as a stop sequence to prevent rambling in multi-turn conversations.

---

## 🧹 Resource Management


Since `llamadart` allocates significant native memory and manages background worker Isolates/Threads, it is essential to manage its lifecycle correctly.

- **Explicit Disposal**: Always call `await engine.dispose()` when you are finished with an engine instance. 
- **Native Stability**: On mobile and desktop, failing to dispose can lead to "hanging" background processes or memory pressure.
- **Hot Restart Support**: In Flutter, placing the engine inside a `Provider` or `State` and calling `dispose()` in the appropriate lifecycle method ensures stability across Hot Restarts.

```dart
@override
void dispose() {
  _engine.dispose();
  super.dispose();
}
```

---

## 🎨 Low-Rank Adaptation (LoRA)

`llamadart` supports applying multiple LoRA adapters dynamically at runtime.

- **Dynamic Scaling**: Adjust the strength (`scale`) of each adapter on the fly.
- **Isolate-Safe**: Native adapters are managed in a background Isolate to prevent UI jank.
- **Efficient**: Multiple LoRAs share the memory of a single base model.

Check out our [LoRA Training Notebook](https://github.com/leehack/llamadart/blob/main/example/training_notebook/lora_training.ipynb) to learn how to train and convert your own adapters.

---

## 🧪 Testing & Quality

This project maintains a high standard of quality with **>=70% line coverage on maintainable `lib/` code** (auto-generated files marked with `// coverage:ignore-file` are excluded).

- **Multi-Platform Testing**: `dart test` runs VM and Chrome-compatible suites automatically.
- **Local-Only Scenarios**: Slow E2E tests are tagged `local-only` and skipped by default.
- **CI/CD**: Automatic analysis, linting, and cross-platform test execution on every PR.

```bash
# Run default test suite (VM + Chrome-compatible tests)
dart test

# Run local-only E2E scenarios
dart test --run-skipped -t local-only

# Run VM tests with coverage
dart test -p vm --coverage=coverage

# Format lcov for maintainable code (respects // coverage:ignore-file)
dart pub global run coverage:format_coverage --lcov --in=coverage/test --out=coverage/lcov.info --report-on=lib --check-ignore

# Enforce >=70% threshold
dart run tool/testing/check_lcov_threshold.dart coverage/lcov.info 70
```

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](https://github.com/leehack/llamadart/blob/main/CONTRIBUTING.md) for architecture details and maintainer instructions for building native binaries.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/leehack/llamadart/blob/main/LICENSE) file for details.
