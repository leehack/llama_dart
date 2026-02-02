## 0.3.1
*   **Cross-Platform Architecture**: 
    *   Refactored `LlamaBackend` for strict Web isolation using "Native-First" conditional exports, ensuring native performance and full web safety.
    *   Standardized backend instantiation via a unified `LlamaBackend()` factory across all examples and scripts.
*   **Web & Context Stability**:
    *   Resolved "Max Tokens is 0" on Web by implementing `getLoadedContextInfo()` and robust GGUF metadata fallback in `LlamaEngine`.
    *   Improved numeric metadata extraction on Web for better compatibility with varied GGUF exporters.
*   **Project Hygiene**:
    *   Achieved 100% clean `dart analyze` across the core library and all example applications.
    *   Replaced legacy stubs in the chat application with a clean, interface-based `ModelService` architecture.
*   **Resumable Downloads**: 
    *   Implemented robust resumable downloads for large models using HTTP Range requests.
    *   Added persistent `.meta` files to track download progress across app restarts.
*   **Enhanced Download UI**:
    *   Refined the `ModelCard` with a visual **Pause/Resume toggle**.
    *   Added a **Trash icon** in the card header for full cancellation and data discard of active or partial downloads.
    *   Improved progress feedback with clear "Paused" and "Downloading" states.
*   **Multimodal Support (Vision & Audio)**: Integrated the experimental `mtmd` module from `llama.cpp` for native platforms.
    *   Added `loadMultimodalProjector` to `LlamaEngine`.
    *   Introduced `LlamaChatMessage.multimodal` and `LlamaContentPart` (Text, Image, Audio).
    *   **Fix**: Resolved missing multimodal symbols in native builds by properly linking the `mtmd` module.
*   **Moondream 2 & Phi-2 Optimization**: 
    *   Implemented a specialized `Question: / Answer:` chat template fallback for Moondream models.
    *   Added dynamic BOS token handling: Automatically disables BOS injection for models where BOS == EOS (like Moondream) to prevent immediate "End of Generation".
*   **ChatSession Manager**: Introduced a new high-level `ChatSession` class to automatically manage conversation history and system prompts.
*   **Context Window Management**: `ChatSession` now implements an automated sliding window to truncate history when the model's context limit is approached.
*   **Windows Robustness**:
    *   Improved export management for MSVC to ensure symbol visibility.
    *   Added Sccache support for Windows builds to significantly improve CI performance.
*   **Automated Lifecycle**: 
    *   Implemented GitHub Actions to automate `llama.cpp` updates, regression testing, and release artifact generation.
*   **[BREAKING] API Changes**:
    *   `LlamaChatMessage.role` now returns a `LlamaChatRole` enum instead of a `String`. All manual role string comparisons should be updated to use the enum.
*   **[DEPRECATED] API Changes**:
    *   Default `LlamaChatMessage` constructor (string-based) is now deprecated; use `.text()` or `.multimodal()` instead.
    *   `LlamaChatMessage.roleString` is deprecated and will be removed in v1.0.
*   **Engine Upgrades**: Upgraded core `llama.cpp` to tag `b7898`.
*   **Robust Media Loading**: Support for loading images and audio via both file paths and raw byte buffers.
*   **Bug Fixes**: Improved native resource cleanup and fixed potential null-pointer crashes in the multimodal pipeline.

## 0.3.0
*   **[BREAKING] Removal of `LlamaService`**: The legacy `LlamaService` facade has been removed. Use `LlamaEngine` with `LlamaBackend()` instead for all platforms.
*   **LoRA Support**: Added full support for Low-Rank Adaptation (LoRA) on all native platforms (iOS, Android, macOS, Linux, Windows).
*   **Web Improvements**: Significantly enhanced the web implementation using `wllama` v2 features, including native chat templating and threading info.
*   **Logging Refactor**: Implemented a unified logging architecture.
    *   **Native Platforms**: Simplified to an on/off toggle to ensure stability. `LlamaLogLevel.none` suppresses all output; other levels enable default stderr logging.
    *   **Web**: Supports full granular filtering (Debug, Info, Warn, Error).
*   **Stability Fixes**: Resolved frequent "Cannot invoke native callback from a leaf call" crashes during Flutter Hot Restarts by refactoring native resource lifecycle.
*   **Improved Lifecycle**: Removed `NativeFinalizer` dependency to avoid race conditions. Explicitly call `dispose()` to release native resources.
*   **Robust Loading**: Improved model loading on all platforms with better instance cleanup, script injection, and URL-based loading support.
*   **Dynamic Adapters**: Implemented APIs to dynamically add, update scale, or remove LoRA adapters at runtime.
*   **LoRA Training Pipeline**: Added a comprehensive Jupyter Notebook for fine-tuning models and converting adapters to GGUF format.
*   **API Enhancements**: Updated `ModelParams` to include initial LoRA configurations and introduced `supportsUrlLoading` for better platform abstraction.
*   **CLI Tooling**: Updated the `basic_app` example to support testing LoRA adapters via the `--lora` flag.

## 0.2.0+b7883
*   **Project Rebrand**: Renamed package from `llama_dart` to `llamadart`.
*   **Pure Native Assets**: Migrated to the modern Dart Native Assets mechanism (`hook/build.dart`).
*   **Zero Setup**: Native binaries are now automatically downloaded and bundled at runtime based on the target platform and architecture.
*   **Version Alignment**: Aligned package versioning and binary distribution with `llama.cpp` release tags (starting with `b7883`).
*   **Logging Control**: Implemented comprehensive logging interception for both `llama` and `ggml` backends with configurable log levels.
*   **Performance Optimization**: Added token caching to message processing, significantly reducing latency in long conversations.
*   **Architecture Overhaul**:
    *   Refactored Flutter Chat Example into a clean, layered architecture (Models, Services, Providers, Widgets).
    *   Rebuilt CLI Basic Example into a robust conversation tool with interactive and single-response modes.
*   **Cross-Platform GPU**: Verified and improved hardware acceleration on macOS/iOS (Metal) and Android/Linux/Windows (Vulkan).
*   **New Build System**: Consolidated all native source and build infrastructure into a unified `third_party/` directory.
*   **Windows Support**: Added robust MinGW + Vulkan cross-compilation pipeline.
*   **UI Enhancements**: Added fine-grained rebuilds using Selectors and isolated painting with RepaintBoundaries.

## 0.1.0
*   **WASM Support**: Full support for running the Flutter app and LLM inference in WASM on the web.
*   **Performance Improvements**: Optimized memory usage and loading times for web models.
*   **Enhanced Web Interop**: Improved `wllama` integration with better error handling and progress reporting.
*   **Bug Fixes**: Resolved minor UI issues on mobile and web layouts.

## 0.0.1
*   Initial release.
*   Supported platforms: iOS, macOS, Android, Linux, Windows, Web.
*   Features:
    *   Text generation with `llama.cpp` backend.
    *   GGUF model support.
    *   Hardware acceleration (Metal, Vulkan).
    *   Flutter Chat Example.
    *   CLI Basic Example.
