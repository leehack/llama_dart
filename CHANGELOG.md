## Unreleased

*   **llama.cpp parity expansion (Dart-native template/parser pipeline)**:
    *   Reworked template detection/render/parse routing to align with llama.cpp semantics across supported chat formats, including format-specific tool-call parsing and fallback behavior.
    *   Added PEG parity components in Dart (`peg_parser_builder`, `peg_chat_parser`) and integrated parser-carrying render/parse flow for PEG-native/constructed formats.
    *   Removed brittle fallback coercions that could mutate valid tool names/argument keys, preserving model-emitted tool payloads for dispatch parity.
    *   Hardened template capability detection with Jinja AST + execution probing, while preventing typed-content false positives caused by raw content stringification.
    *   **[BREAKING]** Removed legacy custom template-handler APIs:
        `ChatTemplateMatcher`, `ChatTemplateRoutingContext`,
        `ChatTemplateEngine.registerHandler(...)`,
        `ChatTemplateEngine.unregisterHandler(...)`,
        `ChatTemplateEngine.clearCustomHandlers(...)`,
        `ChatTemplateEngine.registerTemplateOverride(...)`,
        `ChatTemplateEngine.unregisterTemplateOverride(...)`,
        `ChatTemplateEngine.clearTemplateOverrides(...)`, and
        per-call `customHandlerId` / parse `handlerId` routing.
    *   Removed silent render/parse fallback paths so handler/parser failures are surfaced instead of downgraded to content-only output.
    *   Added llama.cpp-equivalent per-call template globals/time injection via `chatTemplateKwargs` and `templateNow`.
*   **Parity test coverage and tooling**:
    *   Added vendored llama.cpp template parity integration coverage for detection + render + parse paths.
    *   Added upstream llama.cpp chat/template suite runners and local E2E harness (`run_llama_cpp_chat_tests.sh`, `run_template_parity_suites.sh`).
    *   Added mirrored unit tests for new internal template components (`peg_parser_builder`, `template_internal_metadata`) to satisfy structure guards.
*   **Test cleanup and maintainability**:
    *   Reduced noisy diagnostics in template integration tests and centralized format sample parse payload fixtures for easier parity maintenance.
*   **Native integration cleanup (llamadart-native migration)**:
    *   Added `tool/testing/prepare_llama_cpp_source.sh` to fetch/refresh `ggml-org/llama.cpp` into `.dart_tool/llama_cpp` (or `LLAMA_CPP_SOURCE_DIR`) pinned to a resolved ref (`LLAMA_CPP_REF`, default `latest` release tag).
    *   Updated `tool/testing/run_llama_cpp_chat_tests.sh` to use prepared `.dart_tool` source instead of `third_party/llama_cpp`, so local upstream chat-suite runs no longer depend on vendored source.
    *   Updated template parity tests to resolve fixtures from `LLAMA_CPP_TEMPLATES_DIR` or `.dart_tool/llama_cpp/models/templates` instead of `third_party/llama_cpp`.
    *   Clarified README backend matrix notes: `KleidiAI`/`ZenDNN` are CPU-path optimizations, not selectable runtime backend modules.
    *   Runtime backend probing for split-module bundles now runs during backend initialization (not only after first model load), so device/backend availability is visible earlier in app flows.
    *   Native-assets hook output now refreshes emitted native files per build to prevent stale backend module carryover when backend config changes.
*   **Linux runtime/link validation and backend loader hardening**:
    *   Hardened split-module backend loading to avoid probing backends that are not bundled for the active platform/arch, reducing noisy optional-backend load failures.
    *   Added failed-backend memoization so missing optional modules are not retried on every model load.
    *   Tightened Linux cache source selection to the current ABI bundle (`linux-arm64` vs `linux-x64`) when preparing runtime dependencies.
    *   Added Linux backend/runtime setup guidance in README, including distro-specific package baselines (Ubuntu/Debian, Fedora/RHEL/CentOS, Arch).
    *   Added reproducible Docker link-check flows for baseline (`cpu`/`vulkan`/`blas`) and optional `cuda`/`hip` module dependency resolution.
    *   Added `scripts/check_native_link_deps.sh` helper plus dedicated validation images:
        `docker/validation/Dockerfile.cuda-linkcheck` and
        `docker/validation/Dockerfile.hip-linkcheck`.
*   **Chat example backend UX cleanup**:
    *   Removed user-facing `Auto` backend option from settings; only concrete runtime-detected backends are shown.
    *   Added migration behavior that resolves legacy saved `Auto` preference to the best detected backend at runtime.

## 0.5.4

*   **llama.cpp parity hardening**:
    *   `ChatTemplateEngine` now preserves handler-provided tokens even when grammar is attached via params, avoiding token-loss regressions in tool/thinking formats.
    *   Native stop-sequence handling now skips preserved tokens so parser-critical markers are not terminated early.
    *   Generic tool-instruction system injection now follows llama.cpp semantics more closely (replace first system content when supported, otherwise prepend to first message content).
    *   LFM2 output parsing now extracts reasoning more consistently across tool and non-tool output shapes.
*   **Chat example loop/lifecycle hardening**:
    *   Improved tool-loop guards (first-turn force-only behavior, duplicate/equivalent call suppression, per-tool budget, and loop-stop messaging).
    *   Added response fallback that can ground final answers from recent tool results when the model emits stale real-time disclaimers.
    *   Added assistant debug badges (`fmt:*`, `think:*`, `content:json`, `fallback:tool-result`) and strengthened detach/exit disposal paths.
*   **Parity/integration test robustness**:
    *   `tool_calling_integration_test` now accepts both structured `tool_calls` deltas and XML-style `<tool_call>` payloads.
    *   llama.cpp template-detection integration expectations were updated for current Ministral-family routing outcomes.
*   **Documentation updates**:
    *   Clarified chat app behavior when models return JSON-shaped assistant content (for example `{"response":"..."}`) and documented `content:json` diagnostics.
    *   Documented example server sampling defaults (`penalty=1.0`, `top_p=0.95`, `min_p=0.05`) and added a CLI README batch parity-matrix usage example.

*   **Chat app backend/status fixes**:
    *   Backend switching now preserves configured `gpuLayers` while still allowing load-time CPU enforcement.
    *   Runtime backend labeling and GPU activity diagnostics now follow effective user selection, preventing false "VULKAN active" status when CPU mode is selected.
*   **Context size auto mode**:
    *   Restored support for `Context Size: Auto` by preserving `0` in persisted settings and passing auto behavior through to session context-limit resolution.
*   **Tool-call parsing fixes (Hermes)**:
    *   Introduced staged double-brace recovery: parse as-is first, unwrap one outer `{{...}}` layer second, and only fall back to full `_normalizeDoubleBraces` when all braces are consistently doubled.
    *   Added a consistency gate to `_normalizeDoubleBraces` that bails out on mixed single/double brace payloads to prevent corruption of valid nested JSON.
*   **Tool-call parsing fixes (Magistral)**:
    *   Broadened whitespace skipping in `_extractJsonObject` to handle `\n`, `\r`, and `\t` between `[ARGS]` and the JSON body.
*   **Example app (basic\_app)**:
    *   Replaced `toList()` buffering with `await for` streaming for real-time token yield.
    *   Added `tools` parameter to every follow-up `create()` call and bounded tool-execution loop with `_maxToolRounds = 10`.
*   **Test coverage**:
    *   Added chat app regression tests for backend switching behavior and context-size auto persistence.
    *   Added regression tests for Hermes wrapped+nested double-brace payloads and Magistral `[ARGS]` with newline/nested arguments.
*   **Example rename (server)**:
    *   Renamed `example/api_server` to `example/llamadart_server`.
    *   Renamed the example package/bin entrypoint to `llamadart_server`.
    *   Updated llama.cpp tool-call parity defaults/docs to target `example/llamadart_server`.
*   **GLM 4.5 template parity**:
    *   Added XML tool-call grammar generation for `<tool_call>` payloads with `<arg_key>/<arg_value>` pairs.
    *   Added GLM-specific preserved tokens and `<|user|>` stop handling for tool-call flows.
    *   Updated parser extraction to handle GLM XML tool calls from assistant content and reasoning blocks.
*   **Template/native runtime fixes**:
    *   Typed-content template rendering now activates only when messages actually include media parts.
    *   Native context reset now clears llama memory in-place instead of reinitializing the context.

## 0.5.3

*   **Sampling controls**:
    *   Added `minP` to `GenerationParams` with a default value of `0.0` and `copyWith` support.
*   **Native backend parity**:
    *   Added optional llama.cpp `min_p` sampler initialization in `LlamaCppService` when `minP > 0`.
*   **Test coverage**:
    *   Added unit coverage for `GenerationParams.minP` default and `copyWith` behavior.

## 0.5.2

*   **Chat template parity hardening**:
    *   Expanded llama.cpp parity across additional format handlers, including grammar construction, lazy-grammar triggers, preserved tokens, and parser behavior for tool-call payload extraction.
    *   Added shared `ToolCallGrammarUtils` helpers for wrapped object/array tool-call grammar generation and root-rule wrapping.
*   **Crash fix (grammar parsing)**:
    *   Fixed malformed GBNF escaping in Hermes/Command-R string rules that could cause runtime `llama_grammar_init_impl` parse failures during tool-calling generations.
*   **Test coverage expansion**:
    *   Added and expanded handler-level parity tests (Apertus, LFM2, Nemotron V2, Magistral, Seed-OSS, Xiaomi MiMo, DeepSeek R1/V3, Hermes) and mirrored unit tests for new grammar utilities.

## 0.5.1

*   **Documentation fixes**:
    *   Updated README internal links to absolute GitHub URLs so they resolve reliably on pub.dev.
    *   Updated release/migration wording after 0.5.0 publication and refreshed installation/version snippets.
    *   Corrected iOS simulator architecture notes and contributor prerequisites/build target docs.
*   **Publishing hygiene**:
    *   Expanded `.pubignore` to exclude local build outputs, large model/test artifacts, and checked-out `third_party` sources from package uploads.

## 0.5.0

*   **[BREAKING] Public API Changes**:
    *   Root exports were tightened; previously exposed internals such as `ToolRegistry`, `LlamaTokenizer`, and `ChatTemplateProcessor` are no longer part of the public package API.
    *   `ChatSession` now centers on `create(...)` streaming `LlamaCompletionChunk`; legacy `chat(...)` / `chatText(...)` style usage must migrate.
    *   `LlamaChatMessage` constructor names were standardized (`.fromText`, `.withContent`) in place of older named constructors.
    *   Default `maxTokens` in `GenerationParams` increased from `512` to `4096`.
    *   `LlamaChatMessage.toJson()` no longer includes `name` on `tool` role messages.
    *   `ModelParams.logLevel` was removed; logging control now lives on `LlamaEngine` via `setDartLogLevel(...)` and `setNativeLogLevel(...)`.
    *   `LlamaBackend` interface changed for custom backend implementers (notably `getVramInfo` and updated `applyChatTemplate`).
    *   Model reload behavior is stricter: `loadModel(...)` now requires unloading first.
    *   Migration details are documented in `MIGRATION.md`.

*   **Template/Parser Parity Expansion**:
    *   Added llama.cpp-aligned format detection and handlers for additional templates including FireFunction v2, Functionary v3.2, Functionary v3.1 (Llama 3.1), GPT-OSS, Seed-OSS, Nemotron V2, Apertus, Solar Open, EXAONE MoE, Xiaomi MiMo, and TranslateGemma.
    *   Improved parser parity for format-specific tool-calling and reasoning extraction, including `<|python_tag|>` parsing for Llama 3 flows.
    *   Narrowed generic grammar auto-application to generic/content-only routing to avoid interfering with format-specific tool schemas.
*   **Template Extensibility APIs**:
    *   Added global custom handler registration and template override APIs in `ChatTemplateEngine`.
    *   Added per-call `customTemplate` and `customHandlerId` routing support and threaded handler identity into parse paths.
    *   Added cookbook examples and regression tests for registration precedence and fallback behavior.
*   **Logging Controls**:
    *   Added split logging controls in `LlamaEngine`: `setDartLogLevel` and `setNativeLogLevel`, while keeping `setLogLevel` as a convenience method.
    *   Fixed native `none` log level suppression so llama.cpp/ggml logs are fully muted when requested.
*   **Chat App Improvements**:
    *   Added model capability badges and per-model generation presets.
    *   Added template-aware tool enablement guardrails and separate Dart/native log level settings in the UI.
*   **Test Suite Overhaul**:
    *   Expanded template parity coverage (detection, handlers, grammar, workarounds, registry precedence, and integration scenarios).
    *   Added additional unit tests for exceptions, logging, and core model definitions.

## 0.4.0
*   **Cross-Platform Architecture**: 
    *   Refactored `LlamaBackend` for strict Web isolation using "Native-First" conditional exports, ensuring native performance and full web safety.
    *   Standardized backend instantiation via a unified `LlamaBackend()` factory across all examples and scripts.
*   **Web & Context Stability**:
    *   Resolved "Max Tokens is 0" on Web by implementing `getLoadedContextInfo()` and robust GGUF metadata fallback in `LlamaEngine`.
    *   Improved numeric metadata extraction on Web for better compatibility with varied GGUF exporters.
*   **GBNF Grammar Stability**:
    *   Resolved "Unexpected empty grammar stack" crash by reordering the sampler chain (filtering tokens via GBNF *before* performing probability-based sampling).
*   **Test Suite Overhaul**:
    *   Pivoted from mock-based unit tests to real-world integration tests using the actual `llama.cpp` native backend.
    *   Ensured full verification of model loading, tokenization, text generation, and grammar constraints against physical models.
    *   **Multi-Platform Configuration**: Introduced `dart_test.yaml` and `@TestOn` tags to enable seamless execution of all tests across VM and Chrome with a single `dart test` command.
*   **Robust Log Silencing**:
    *   Implemented FD-level redirection (`dup2` to `/dev/null`) for `LlamaLogLevel.none` on native platforms.
    *   This provides a crash-free alternative to FFI-based log callbacks, which were unstable during low-level native initialization (e.g., Metal).
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
    *   Introduced `LlamaChatMessage.withContent` and `LlamaContentPart` (Text, Image, Audio).
    *   **Fix**: Resolved missing multimodal symbols in native builds by properly linking the `mtmd` module.
*   **Moondream 2 & Phi-2 Optimization**: 
    *   Implemented a specialized `Question: / Answer:` chat template fallback for Moondream models.
    *   Added dynamic BOS token handling: Automatically disables BOS injection for models where BOS == EOS (like Moondream) to prevent immediate "End of Generation".
*   **Chat API Consolidation**: 
    *   Moved high-level `chat()` and `chatWithTools()` logic from `LlamaEngine` to `ChatSession`.
    *   `LlamaEngine` is now a dedicated low-level orchestrator for model loading, tokenization, and raw inference.
*   **Intelligent Tool Flow**:
    *   **Optional Tool Calls**: Tools are no longer forced by default. The model now decides when to use a tool vs. responding directly based on context.
    *   **Final Response Generation**: After a tool returns a result, the model now generates a natural language response (without grammar constraints) to interpret the result for the user.
    *   **forceToolCall**: Added a session-level flag to re-enable strict grammar-constrained tool calls for smaller models (e.g., 0.5B - 1B).
*   **App Stability & Resources**:
    *   Fixed a crash in the Flutter chat app during close/restart by implementing and using an idempotent `dispose()` in `ChatService`.
    *   Added Qwen 2.5 3B and 7B models to the download list with clear RAM/VRAM requirements for testing complex instruction following and tool use.
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
    *   Default `LlamaChatMessage` constructor (string-based) is now deprecated; use `.fromText()` or `.withContent()` instead.
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
