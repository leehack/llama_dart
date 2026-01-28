# llamadart

A Dart/Flutter plugin for `llama.cpp`. Run LLM inference directly in Dart and Flutter applications using GGUF models with hardware acceleration.

## ⚠️ Status
**Actively Under Development**.
The core features are implemented and running. Many more features are in the pipeline, including:
*   High-level APIs for easier integration.
*   Multi-modality support (Vision/LLaVA).

We welcome contributors to help us test on more platforms (especially Windows)!

## 🚀 Supported Platforms

| Platform | Architecture(s) | GPU Backend | Status |
|----------|-----------------|-------------|--------|
| **macOS** | Universal (arm64, x86_64) | Metal | ✅ Tested (CPU, Metal) |
| **iOS** | arm64 (Device), x86_64/arm64 (Sim) | Metal (Device), CPU (Sim) | ✅ Tested (CPU, Metal) |
| **Android** | arm64-v8a, x86_64 | Vulkan (if supported) | ✅ Tested (CPU, Vulkan) |
| **Linux** | x86_64 | CUDA / Vulkan | ⚠️ Tested (CPU Verified, Vulkan Untested) |
| **Windows**| x86_64 | CUDA / Vulkan | ❓ Needs Testing |
| **Web**| WASM | CPU (WASM) | ✅ Tested (WASM) |

---

### 1. Add Dependency
Add `llamadart` to your `pubspec.yaml`:
```yaml
dependencies:
  llamadart: ^0.1.0
```

### 2. Platform Setup

#### 📱 iOS
**No manual setup required.**
The plugin automatically builds `llama.cpp` for iOS (Device/Simulator) when you run `flutter build ios`.
*Note: The first build will take a few minutes to compile the C++ libraries.*

#### 💻 macOS / Linux / Windows
The package handles native builds automatically via CMake.
*   **macOS**: Metal acceleration is enabled by default.
*   **Linux/Windows**: CPU inference is supported.

#### 📱 Android
**No manual setup required.**
The plugin uses CMake to compile the native library automatically.
- Ensure you have the **Android NDK** installed via Android Studio.
- The first build will take a few minutes to compile the `llama.cpp` libraries for your target device's architecture.

#### 🌐 Web
**Zero-config** by default (uses jsDelivr CDN for `wllama`).
1.  Import and use `LlamaService`.
2.  Enable WASM support in Flutter web:
    ```bash
    flutter run -d chrome --wasm
    # OR build with wasm
    flutter build web --wasm
    ```

**Offline / Bundled Usage (Optional):**
1.  Download assets to your `assets/` directory:
    ```bash
    dart run llamadart:download_wllama
    ```
2.  Add the folder to your `pubspec.yaml`:
    ```yaml
    flutter:
      assets:
        - assets/wllama/single-thread/
    ```
3.  Initialize with local asset paths:
    ```dart
    final service = LlamaService(
      wllamaPath: 'assets/wllama/single-thread/wllama.js',
      wasmPath: 'assets/wllama/single-thread/wllama.wasm',
    );
    ```

---

## 📱 Platform Specifics

### iOS
- **Metal**: Acceleration enabled by default on physical devices.
- **Simulator**: Runs on CPU (x86_64 or arm64).

### macOS
- **Sandboxing**: Add these entitlements to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements` for network access (model downloading):
  ```xml
  <key>com.apple.security.network.client</key>
  <true/>
  ```

### Android
- **Architectures**: `arm64-v8a` (most devices) and `x86_64` (emulators).
- **Vulkan**: GPU acceleration is enabled by default on devices with Vulkan support.
- **NDK**: Requires Android NDK 26+ installed (usually handled by Android Studio).

---

## 🎮 GPU Configuration

GPU backends are **enabled by default** where available. Use the options below to customize.

### Runtime Control (Recommended)

Control GPU usage at runtime via `ModelParams`:

```dart
// Use GPU with automatic backend selection (default)
await service.init('model.gguf', modelParams: ModelParams(
  gpuLayers: 99,  // Offload all layers to GPU
  preferredBackend: GpuBackend.auto,
));

// Force CPU-only inference
await service.init('model.gguf', modelParams: ModelParams(
  gpuLayers: 0,  // No GPU offloading
  preferredBackend: GpuBackend.cpu,
));

// Request specific backend (if compiled in)
await service.init('model.gguf', modelParams: ModelParams(
  preferredBackend: GpuBackend.vulkan,
));
```

**Available backends**: `auto`, `cpu`, `cuda`, `vulkan`, `metal`

### Compile-Time Options (Advanced)

To disable GPU backends at build time:

**Android** (in `android/gradle.properties`):
```properties
LLAMA_DART_NO_VULKAN=true
```

**Desktop** (CMake flags):
```bash
# Disable CUDA
cmake -DLLAMA_DART_NO_CUDA=ON ...

# Disable Vulkan
cmake -DLLAMA_DART_NO_VULKAN=ON ...
```

---

## 🚀 Usage

```dart
import 'package:llamadart/llamadart.dart';

void main() async {
  final service = LlamaService();

  try {
    // 1. Initialize with model path (GGUF)
    // On iOS/macOS, ensures Metal is used if available.
    await service.init('models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf');
    
    // 2. Generate text (streaming)
    final prompt = "<start_of_turn>user\nTell me a story about a llama.<end_of_turn>\n<start_of_turn>model\n";
    
    await for (final token in service.generate(prompt)) {
      stdout.write(token);
    }
  } finally {
    // 3. Always dispose to free native memory
    service.dispose();
  }
}
```

---

## 📱 Examples

- **Flutter Chat App**: `example/chat_app`
  - A full-featured chat interface with real-time streaming, GPU acceleration support, and model management.
- **Basic Console App**: `example/basic_app`
  - Minimal example demonstrating model download and basic inference.


## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed instructions on:
-   Setting up the development environment.
-   Building the native libraries.
-   Running tests and examples.


## License
MIT
