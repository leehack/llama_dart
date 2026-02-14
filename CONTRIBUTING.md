# Contributing into llamadart

Thank you for your interest in contributing to `llamadart`! We welcome contributions from the community to help improve this package.

## Prerequisites

Before you begin, ensure you have the following installed:

-   **Dart SDK**: >= 3.10.7
-   **Flutter SDK**: >= 3.38.0 (optional, for running UI examples)
-   **CMake**: >= 3.10
-   **C++ Compiler**:
    -   **macOS**: Xcode Command Line Tools (`xcode-select --install`)
    -   **Linux**: GCC/G++ (`build-essential`) or Clang
    -   **Windows**: Visual Studio 2022 (Desktop development with C++). 
        -   *Tip*: Install `ccache` or `sccache` via `choco install sccache` to speed up local builds.

## Project Structure

The project follows a modular, decoupled architecture:

-   `lib/src/core/engine/`: Core orchestration (`LlamaEngine`, `ChatSession`).
-   `lib/src/core/template/`: Chat template routing, handlers, parser logic.
-   `lib/src/backends/`: Platform-agnostic backend interface and native/web backends.
-   `lib/src/core/models/`: Shared data models (messages, params, tools, config).
-   `lib/src/core/`: Shared utilities (exceptions, logger, grammar helpers).
-   `third_party/`: `llama.cpp` core engine and build infrastructure.

## 🛡️ Zero-Patch Strategy

This project follows a **Zero-Patch Strategy** for external submodules (like `llama.cpp` and `Vulkan-Headers`):

*   **Zero Direct Modifications**: We never modify the source code inside `third_party/llama_cpp`.
*   **Upgradability**: This allows us to update the core engine by simply bumping the submodule pointer.
*   **Wrappers & Hooks**: Any necessary changes should be implemented in `third_party/CMakeLists.txt` or through compiler flags in the build scripts. We also consolidate experimental modules like `mtmd` by linking them into the core `llamadart` binary.

## 🏗️ Architecture: Native Assets & CI

`llamadart` uses a modern binary distribution lifecycle:

### 1. Binary Production (CI)
Maintainer workflows under `.github/workflows/` use scripts in `third_party/`
to build and validate native binaries for **Android, iOS, macOS, Linux, and Windows**.
Release artifacts are published to **GitHub Releases** and consumed by the build hook.

### 2. Binary Consumption (Hook)
When a user adds `llamadart` as a dependency and runs their app:
- The **`hook/build.dart`** script executes automatically.
- It detects the user's current target OS and architecture.
- It downloads the matching pre-compiled binary from the GitHub Release corresponding to the package version.
- It reports the binary to the Dart VM as a **`CodeAsset`** with the ID `package:llamadart/llamadart`.

### 3. Runtime Resolution (FFI)
- The library uses **`@Native`** top-level bindings in `lib/src/backends/llama_cpp/bindings.dart`.
- The Dart VM automatically resolves these calls to the downloaded binary reported by the hook.
- This provides a "Zero-Setup" experience while maintaining high-performance native execution.

## Setting Up the Development Environment

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/leehack/llamadart.git
    cd llamadart
    ```

2.  **Initialize**:
    ```bash
    dart pub get
    git submodule update --init --recursive
    ```

3.  **Build/Fetch Native Library**:
    In most cases, simply running the examples will handle everything:
    ```bash
    cd example/basic_app
    dart run
    ```
    The `hook/build.dart` will automatically download the correct pre-compiled binaries for your platform.

## 🧪 Testing

We take testing seriously. CI enforces **>=70% line coverage on maintainable `lib/` code**. Auto-generated files are excluded when they are marked with `// coverage:ignore-file`.

### 1. Unified Test Runner
We use `dart_test.yaml` and `@TestOn` tags to manage multi-platform execution.
Running `dart test` will run VM and Chrome-compatible tests. Tests tagged
`local-only` are intentionally skipped in default and CI runs.

```bash
# Run default suite (VM + Chrome-compatible tests)
dart test

# Run local-only E2E tests
dart test --run-skipped -t local-only
```

### 2. Manual Platform Selection
You can still target specific platforms if needed:

```bash
# Run only VM tests
dart test -p vm

# Run only Chrome tests
dart test -p chrome
```

### 3. Coverage
To collect and view coverage reports:

```bash
# 1. Run VM tests with coverage
dart test -p vm --coverage=coverage

# 2. Format into LCOV (respects // coverage:ignore-file)
dart pub global run coverage:format_coverage --lcov --in=coverage/test --out=coverage/lcov.info --report-on=lib --check-ignore

# 3. Enforce >=70% threshold
dart run tool/testing/check_lcov_threshold.dart coverage/lcov.info 70
```

### 4. Testing Standards
- **Structure**:
  - Unit tests live in `test/unit/` and mirror `lib/src/` paths.
  - Generated/native-bridge files are excluded from strict mirroring when marked with `// coverage:ignore-file`.
  - Scenario, regression, and diagnostic tests live in `test/integration/`.
  - Slow, local-machine scenarios live in `test/e2e/` with `@Tags(['local-only'])`.
- **Refactoring**: If you refactor shared logic, ensure both Native and Web tests pass.
- **New Features**: Every new public API or feature must include unit or integration tests.
- **Platform-Safety**: `LlamaEngine` must remain `dart:ffi` and `dart:io` free to maintain web support.

## Maintainer: Building Binaries

If you need to build binaries for a new release:

1.  **Navigate to the build tool**:
    ```bash
    cd third_party
    ```

2.  **Run platform scripts**:
    -   **Android**: `./build_android.sh`
    -   **Apple (macOS)**: `./build_apple.sh macos-arm64` or `./build_apple.sh macos-x86_64`
    -   **Apple (iOS)**: `./build_apple.sh ios-device-arm64`, `./build_apple.sh ios-sim-arm64`, or `./build_apple.sh ios-sim-x86_64`
    -   **Linux**: `./build_linux.sh vulkan`

## Running Examples

### Basic App (CLI)
1.  ```bash
    cd example/basic_app
    dart run
    ```

### Chat App (Flutter)
1.  ```bash
    cd example/chat_app
    flutter run -d macos  # or linux, windows, android, ios
    ```

## Development Guidelines

-   **Code Style**: We follow standard Dart linting rules. Run `dart format .` before committing.
-   **Native Assets**: The package uses the modern **Dart Native Assets** (hooks) mechanism.
-   **Testing**: Add unit tests for new features where possible. Use `dart test` for full integration and unit verification.

## Submitting a Pull Request

1.  Fork the repository.
2.  Create a new branch (`git checkout -b feature/my-feature`).
3.  Commit your changes.
4.  Push to your fork and submit a Pull Request.

Thank you for contributing!
