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
- 🖼️ **Multimodal Support**: Run vision and audio models (LLaVA, Gemma 3, Qwen2-VL) with integrated media processing.
- ⏬ **Resumable Downloads**: Robust background-safe model downloads with parallel chunking and partial-file resume tracking.
- **LoRA Support**: Apply fine-tuned adapters (GGUF) dynamically at runtime.
- 🌐 **Web Support**: Run inference in the browser via WASM (powered by `wllama` v2).
- 💎 **Dart-First API**: Streamlined architecture with decoupled backends.
- 🔇 **Split Logging Control**: Configure Dart-side logger and native backend logs independently.
- 🧪 **High Coverage**: Robust test suite with 80%+ global core coverage.

---

## 🏗️ Architecture

llamadart uses a modern, decoupled architecture designed for flexibility and platform independence:

- **LlamaEngine**: The primary high-level orchestrator. It handles model lifecycle, tokenization, chat templating, and manages the inference stream.
- **ChatSession**: A stateful wrapper for `LlamaEngine` that automatically manages conversation history, system prompts, and enforces context window limits (sliding window).
- **LlamaBackend**: A platform-agnostic interface with a default `LlamaBackend()` factory constructor that auto-selects native (`llama.cpp`) or web (`wllama`) implementations.

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

## 🌐 Web Backend Notes (wllama)

When running on the web backend (`wllama`), keep these current limitations in mind:

- Web is currently **WASM/CPU only** (no WebGPU acceleration in this binding yet).
- **Multimodal projector loading is not supported on web** (`loadMultimodalProjector`).
- `supportsVision` / `supportsAudio` report `false` on web.
- **LoRA runtime adapter APIs are not supported** on web in the current implementation.
- Changing log level via `setLogLevel`/`setNativeLogLevel` applies on the next model load.

If your app targets both native and web, gate feature toggles by platform/capability checks.

---

## 📦 Installation

Add `llamadart` to your `pubspec.yaml`:

```yaml
dependencies:
  llamadart: ^0.4.0
```

### Zero Setup (Native Assets)

`llamadart` leverages the **Dart Native Assets** (build hooks) system. When you run your app for the first time (`dart run` or `flutter run`), the package automatically:
1. Detects your target platform and architecture.
2. Downloads the appropriate pre-compiled binary from GitHub.
3. Bundles it seamlessly into your application.

No manual binary downloads, CMake configuration, or platform-specific project changes are needed.

---

## ⚠️ Breaking Changes (Upcoming 0.5.0)

`0.5.0` has not been published yet. This branch includes intentional
breaking changes while the API is still early.

Before upgrading from `main` / `0.4.0`, read:

- [MIGRATION.md](MIGRATION.md)

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

### 3.5 Custom Template Handlers and Overrides (Advanced)

If you need behavior for a model-specific template that is not built in yet,
you can register your own handler and/or template override.

```dart
import 'package:llamadart/llamadart.dart';

class MyHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.generic;

  @override
  List<String> get additionalStops => const [];

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    final prompt = messages.map((m) => m.content).join('\n');
    return LlamaChatTemplateResult(prompt: prompt, format: format.index);
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    return ChatParseResult(content: output.trim());
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) => null;
}

void configureTemplateRouting() {
  // 1) Register a custom handler
  ChatTemplateEngine.registerHandler(
    id: 'my-handler',
    handler: MyHandler(),
    matcher: (ctx) =>
        (ctx.metadata['general.name'] ?? '').contains('MyModel'),
  );

  // 2) Register a global template override
  ChatTemplateEngine.registerTemplateOverride(
    id: 'my-template-override',
    templateSource: '{{ messages[0]["content"] }}',
    matcher: (ctx) => ctx.hasTools,
  );
}

Future<void> usePerCallOverride(LlamaEngine engine) async {
  final template = await engine.chatTemplate(
    [
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'hello',
      ),
    ],
    customTemplate: '{{ "CUSTOM:" ~ messages[0]["content"] }}',
    customHandlerId: 'my-handler',
  );

  print(template.prompt);
}
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

Check out our [LoRA Training Notebook](example/training_notebook/lora_training.ipynb) to learn how to train and convert your own adapters.

---

## 🧪 Testing & Quality

This project maintains a high standard of quality with **80%+ global test coverage**.

- **Multi-Platform Testing**: Run all tests across VM and Chrome automatically.
- **CI/CD**: Automatic analysis, linting, and cross-platform test execution on every PR.

```bash
# Run all tests (VM and Chrome)
dart test

# Run tests with coverage
dart test --coverage=coverage
```

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for architecture details and maintainer instructions for building native binaries.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
