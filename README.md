# llamadart

[![Pub Version](https://img.shields.io/pub/v/llamadart?logo=dart&color=blue)](https://pub.dev/packages/llamadart)
[![codecov](https://codecov.io/gh/leehack/llamadart/graph/badge.svg?token=)](https://codecov.io/gh/leehack/llamadart)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)
[![GitHub](https://img.shields.io/github/stars/leehack/llamadart?style=social)](https://github.com/leehack/llamadart)

**llamadart** is a high-performance Dart and Flutter plugin for [llama.cpp](https://github.com/ggml-org/llama.cpp). It allows you to run Large Language Models (LLMs) locally using GGUF models across all major platforms with minimal setup.

## ✨ Features

- 🚀 **High Performance**: Powered by `llama.cpp`'s optimized C++ kernels.
- 🛠️ **Zero Configuration**: Uses the modern **Pure Native Asset** mechanism—no manual build scripts or platform folders required.
- 📱 **Cross-Platform**: Full support for Android, iOS, macOS, Linux, and Windows.
- ⚡ **GPU Acceleration**:
  - **Apple**: Metal (macOS/iOS)
  - **Android/Linux/Windows**: Vulkan (default) with optional per-bundle
    backend modules (OpenCL/CUDA/HIP/BLAS where available)
- 🖼️ **Multimodal Support**: Run vision and audio models (LLaVA, Gemma 3, Qwen2-VL) with integrated media processing.
- ⏬ **Resumable Downloads**: Robust background-safe model downloads with parallel chunking and partial-file resume tracking.
- **LoRA Support**: Apply fine-tuned adapters (GGUF) dynamically at runtime.
- 🌐 **Web Support**: Web backend router with WebGPU bridge support and WASM fallback.
- 💎 **Dart-First API**: Streamlined architecture with decoupled backends.
- 🔇 **Split Logging Control**: Configure Dart-side logger and native backend logs independently.
- 🧪 **High Coverage**: CI enforces >=70% coverage on maintainable core code.

---

## 🏗️ Architecture

llamadart uses a modern, decoupled architecture designed for flexibility and platform independence:

- **LlamaEngine**: The primary high-level orchestrator. It handles model lifecycle, tokenization, chat templating, and manages the inference stream.
- **ChatSession**: A stateful wrapper for `LlamaEngine` that automatically manages conversation history, system prompts, and enforces context window limits (sliding window).
- **LlamaBackend**: A platform-agnostic interface with a default `LlamaBackend()` factory constructor that auto-selects native (`llama.cpp`) or web (WebGPU bridge first, WASM fallback) implementations.

---

## 🚀 Quick Start

| Platform | Architecture(s) | GPU Backend | Status |
|----------|-----------------|-------------|--------|
| **macOS** | arm64, x86_64 | Metal | ✅ Tested |
| **iOS** | arm64 (Device), arm64/x86_64 (Sim) | Metal (Device), CPU (Sim) | ✅ Tested |
| **Android** | arm64-v8a, x86_64 | Vulkan | ✅ Tested |
| **Linux** | arm64, x86_64 | Vulkan | ✅ Tested |
| **Windows** | x64 | Vulkan | ✅ Tested |
| **Web** | WASM / WebGPU Bridge | CPU / Experimental WebGPU | ✅ Tested (WASM) |

---

## 🌐 Web Backend Notes (Router)

The default web backend uses the bridge runtime (`WebGpuLlamaBackend`) for
both WebGPU and CPU execution paths.

Current limitations:

- Web mode is currently **experimental** and depends on an external JS bridge runtime.
- Bridge API contract: [WebGPU bridge contract](https://github.com/leehack/llamadart/blob/main/doc/webgpu_bridge.md).
- Prebuilt web bridge assets are published from
  [`leehack/llama-web-bridge`](https://github.com/leehack/llama-web-bridge)
  to
  [`leehack/llama-web-bridge-assets`](https://github.com/leehack/llama-web-bridge-assets).
- [`example/chat_app`](https://github.com/leehack/llamadart/blob/main/example/chat_app/README.md) uses local bridge files first and
  falls back to jsDelivr assets when local assets are missing.
- Bridge model loading now uses browser Cache Storage when `useCache` is true
  (enabled by default in `llamadart` web backend), so repeat loads of the same
  model URL can avoid full re-download.
- To self-host pinned assets at build time:
  `WEBGPU_BRIDGE_ASSETS_TAG=<tag> ./scripts/fetch_webgpu_bridge_assets.sh`.
- The fetch script applies a Safari compatibility patch by default for universal
  browser use (`WEBGPU_BRIDGE_PATCH_SAFARI_COMPAT=1`,
  `WEBGPU_BRIDGE_MIN_SAFARI_VERSION=170400`).
- The same patch flow also updates legacy bridge chunk assembly logic to avoid
  Safari stream-reader buffer reuse issues during model downloads.
- `example/chat_app/web/index.html` applies the same Safari compatibility patch
  at runtime for bridge core loading (including CDN fallback paths).
- Bridge wasm build/publish CI and runtime implementation are maintained in
  [`leehack/llama-web-bridge`](https://github.com/leehack/llama-web-bridge).
- Current bridge browser targets in this repo: Chrome >= 128, Firefox >= 129,
  Safari >= 17.4.
- Safari GPU execution uses a compatibility gate: legacy bridge assets are
  forced to CPU by default, while adaptive bridge assets can probe/cap GPU
  layers and auto-fallback to CPU when generation looks unstable.
- You can bypass the legacy safeguard with
  `window.__llamadartAllowSafariWebGpu = true` before model load.
- `loadMultimodalProjector` is available on web when using URL-based model/mmproj assets.
- `supportsVision` / `supportsAudio` reflect loaded projector capabilities on web.
- **LoRA runtime adapter APIs are not supported** on web in the current implementation.
- Changing log level via `setLogLevel`/`setNativeLogLevel` applies on the next model load.

If your app targets both native and web, gate feature toggles by platform/capability checks.

---

## 📦 Installation

Add `llamadart` to your `pubspec.yaml`:

```yaml
dependencies:
  llamadart: ^0.5.4
```

### Zero Setup (Native Assets)

`llamadart` leverages the **Dart Native Assets** (build hooks) system. When you run your app for the first time (`dart run` or `flutter run`), the package automatically:
1. Detects your target platform and architecture.
2. Downloads the appropriate pre-compiled native bundle from
   [`leehack/llamadart-native`](https://github.com/leehack/llamadart-native).
3. Bundles it seamlessly into your application.

No manual binary downloads, CMake configuration, or platform-specific project changes are needed.

### Native Backend Modules (Optional)

For non-Apple targets, `llamadart` can bundle backend modules per
platform/architecture via hooks user-defines in `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_backends:
        platforms:
          android-arm64: [vulkan] # opencl is optional opt-in
          linux-x64: [vulkan]
          windows-x64: [vulkan]
```

Backend module matrix (from pinned native tag `b8095`, verified against all
published platform/arch bundle assets):

| Target | Configurable | Default runtime backends | Available backend modules in bundle |
|--------|--------------|--------------------------|-------------------------------------|
| android-arm64 | yes | cpu, vulkan | cpu, vulkan, opencl |
| android-x64 | yes | cpu, vulkan | cpu, vulkan, opencl |
| linux-arm64 | yes | cpu, vulkan | cpu, vulkan, blas |
| linux-x64 | yes | cpu, vulkan | cpu, vulkan, blas, cuda, hip |
| windows-arm64 | yes | cpu, vulkan | cpu, vulkan, blas |
| windows-x64 | yes | cpu, vulkan | cpu, vulkan, blas, cuda |
| macos-arm64 | no | cpu, METAL | n/a (single consolidated native lib) |
| macos-x86_64 | no | cpu, METAL | n/a (single consolidated native lib) |
| ios-arm64 | no | cpu, METAL | n/a (single consolidated native lib) |
| ios-arm64-sim | no | cpu, METAL | n/a (single consolidated native lib) |
| ios-x86_64-sim | no | cpu, METAL | n/a (single consolidated native lib) |

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

- Module availability depends on the pinned native release bundle and can change when the native tag is updated.
- Configurable targets always keep `cpu` bundled as a fallback backend module.
- Android keeps OpenCL available for opt-in configuration, but defaults to Vulkan.
- `KleidiAI` and `ZenDNN` are CPU-path optimizations in `llama.cpp`, not separate backend module files like `ggml-vulkan` or `ggml-cuda`.
- Because of that, they do not appear as selectable entries in `llamadart_native_backends` or as separate rows in the bundle-module matrix.
- If you request a backend that is unavailable for a target, `llamadart` logs a warning and falls back to that target's default backend modules.
- `example/chat_app` backend settings show runtime-detected backends/devices (what actually initialized on the device), not just bundled module files.
- `example/chat_app` no longer exposes a user-facing `Auto` backend option; it lists concrete detected backends.
- Legacy saved `Auto` preferences in `example/chat_app` are auto-migrated to the best detected backend at runtime.
- The native-assets hook now refreshes emitted native files on each build; if you are upgrading from older cached outputs, run `flutter clean` once.

Apple targets are intentionally non-configurable in this path:

- macOS and iOS device use the consolidated Metal+CPU native library.
- iOS simulator uses the simulator-native consolidated library.

---

## ⚠️ Breaking Changes in 0.5.0

If you are upgrading from `0.4.x`, read:

- [MIGRATION.md](https://github.com/leehack/llamadart/blob/main/MIGRATION.md)

High-impact changes:

- `ChatSession` now centers on `create(...)` and streams `LlamaCompletionChunk`.
- `LlamaChatMessage` named constructors were standardized:
  - `LlamaChatMessage.text(...)` -> `LlamaChatMessage.fromText(...)`
  - `LlamaChatMessage.multimodal(...)` -> `LlamaChatMessage.withContent(...)`
- `ModelParams.logLevel` was removed; logging is now controlled at engine level via:
  - `setDartLogLevel(...)`
  - `setNativeLogLevel(...)`
- Root exports changed; previously exported internals such as `ToolRegistry`,
  `LlamaTokenizer`, and `ChatTemplateProcessor` are no longer part of the
  public package surface.
- Custom backend implementations must match the updated `LlamaBackend`
  interface (including `getVramInfo` and updated `applyChatTemplate`).

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
