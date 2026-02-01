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
  - **Android/Linux/Windows**: Vulkan
-  **LoRA Support**: Apply fine-tuned adapters (GGUF) dynamically at runtime.
- 🌐 **Web Support**: Run inference in the browser via WASM (powered by `wllama` v2).
- 💎 **Dart-First API**: Streamlined architecture with decoupled backends.
- 🔇 **Logging Control**: Toggle native engine output or use granular filtering on Web.
- 🧪 **High Coverage**: Robust test suite with 80%+ global core coverage.

---

## 🏗️ Architecture

llamadart 0.3.0+ uses a modern, decoupled architecture designed for flexibility and platform independence:

- **LlamaEngine**: The primary high-level orchestrator. It handles model lifecycle, tokenization, chat templating, and manages the inference stream.
- **ChatSession**: A stateful wrapper for `LlamaEngine` that automatically manages conversation history, system prompts, and enforces context window limits (sliding window).
- **LlamaBackend**: A platform-agnostic interface that allows swapping implementation details:
  - `NativeLlamaBackend`: Uses Dart FFI and background Isolates for high-performance desktop/mobile inference.
  - `WebLlamaBackend`: Uses WebAssembly and the `wllama` JS library for in-browser inference.
- **LlamaBackendFactory**: Automatically selects the appropriate backend for your current platform.

---

## 🚀 Quick Start

| Platform | Architecture(s) | GPU Backend | Status |
|----------|-----------------|-------------|--------|
| **macOS** | arm64, x86_64 | Metal | ✅ Tested |
| **iOS** | arm64 (Device), x86_64 (Sim) | Metal (Device), CPU (Sim) | ✅ Tested |
| **Android** | arm64-v8a, x86_64 | Vulkan | ✅ Tested |
| **Linux** | arm64, x86_64 | Vulkan | ✅ Tested |
| **Windows** | x64 | Vulkan | ✅ Tested |
| **Web** | WASM | CPU | ✅ Tested |

---

## 📦 Installation

Add `llamadart` to your `pubspec.yaml`:

```yaml
dependencies:
  llamadart: ^0.3.0
```

### Zero Setup (Native Assets)

`llamadart` leverages the **Dart Native Assets** (build hooks) system. When you run your app for the first time (`dart run` or `flutter run`), the package automatically:
1. Detects your target platform and architecture.
2. Downloads the appropriate pre-compiled binary from GitHub.
3. Bundles it seamlessly into your application.

No manual binary downloads, CMake configuration, or platform-specific project changes are needed.

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

### 2. Advanced Usage (Decoupled Engine)

Use `LlamaEngine` directly for more granular control, such as swapping backends or manual context management.

```dart
import 'package:llamadart/llamadart.dart';

void main() async {
  // Explicitly select Native or Web backend
  final backend = NativeLlamaBackend(); 
  final engine = LlamaEngine(backend);

  try {
    await engine.loadModel('model.gguf');

    // High-level Chat interface (handles templates and stop sequences)
    final messages = [
      LlamaChatMessage(role: 'system', content: 'You are a poetic assistant.'),
      LlamaChatMessage(role: 'user', content: 'Tell a story about a cat.'),
    ];

    await for (final text in engine.chat(messages)) {
      print(text);
    }
  } finally {
    await engine.dispose();
  }
}
```

### 3. Stateful Chat (ChatSession)

Use `ChatSession` for most chat applications. it automatically maintains history and manages the model's context window.

```dart
import 'package:llamadart/llamadart.dart';

void main() async {
  final engine = LlamaEngine(LlamaBackend());
  
  try {
    await engine.loadModel('model.gguf');

    // Create a session with an optional system prompt
    final session = ChatSession(engine, systemPrompt: 'You are a helpful assistant.');

    // Just send the user text, history is handled automatically
    await for (final token in session.chat('What is the capital of Japan?')) {
      stdout.write(token);
    }

    // Next message will include previous context
    await for (final token in session.chat('And its population?')) {
      stdout.write(token);
    }
  } finally {
    await engine.dispose();
  }
}
```

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

Check out our [LoRA Training Notebook](example/training_notebook/lora_training.ipynb) to learn how to train and convert your own adapters.

---

## 🧪 Testing & Quality

This project maintains a high standard of quality with **80%+ global test coverage**.

- **Native Tests**: Integration tests using real GGUF models via FFI.
- **Web Tests**: Browser-based unit and integration tests using Chrome.
- **CI/CD**: Automatic analysis, linting, and cross-platform test execution on every PR.

```bash
# Run all native tests
dart test

# Run web tests (requires Chrome)
dart test -p chrome test/web_backend_unit_test.dart
```

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for architecture details and maintainer instructions for building native binaries.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
