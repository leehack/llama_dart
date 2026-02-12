# AGENTS.md

This file provides guidance for agentic coding assistants working in the llamadart repository.

## Build / Lint / Test Commands

### Development Commands
```bash
dart pub get                              # Install dependencies
dart format .                             # Format all Dart files
dart format --output=none --set-exit-if-changed .  # Check only, CI-friendly
dart analyze                              # Run static analysis/linting
dart analyze --fatal-infos              # Treat info-level lints as errors (CI)
```

### Testing Commands
```bash
dart test                                 # Run all platform-compatible tests (VM or browser)
dart test -p vm                           # Run only VM (native) tests
dart test -p chrome                       # Run only Chrome (web) tests
dart test test/path/to/test_file.dart     # Run a single test file
dart test --coverage=coverage             # Run tests and collect coverage
dart pub global run coverage:format_coverage --lcov --in=coverage/test --out=coverage/lcov.info --report-on=lib
```

### CI Standards
- `dart format --output=none --set-exit-if-changed .` checks formatting
- `dart analyze` runs the linter
- `dart test -p vm -j 1` runs native tests sequentially (required for some OS)
- Tests maintain 80%+ global coverage across all platforms

## Code Style Guidelines

### Imports
- Start with Dart SDK imports (`dart:core`, `dart:async`, etc.)
- Follow with package imports from external dependencies
- Use relative path imports for same-package files (`'../backends/backend.dart'`)
- Group imports with blank lines between categories
- No `show`/`hide` unless necessary for deconfliction

### Formatting
- Use `dart format` with default settings (no trailing comma, 80 character line length)
- Single blank line between top-level declarations
- Two blank lines between class-level sections

### Types & Declarations
- Explicit types on all public APIs: parameters, return types, fields
- Type inference (`var`, `final`) can be used for obvious local types
- Immutable data classes use `const` constructors where possible
- Private fields use leading underscore (`_modelHandle`)

### Naming Conventions
- Classes: `PascalCase` (e.g., `LlamaEngine`, `ChatSession`)
- Functions/methods: `camelCase` (e.g., `loadModel`, `setLogLevel`)
- Variables/params: `camelCase` with descriptive names
- Private members: leading underscore (`_isReady`)
- Constants: `lowerCamelCase` (e.g., `contextSize`, `gpuLayers`)
- Files: `snake_case.dart`
- Directories: `snake_case`

### Documentation
- All public members require Dart doc comments (`///`)
- Use triple-slash doc format with proper Markdown
- Include usage examples in class-level documentation
- Parameter and return types documented
- No TODO/FIXME comments in committed code

### Error Handling
- Use custom `LlamaException` hierarchy (defined in `lib/src/core/exceptions.dart`)
- Subtypes: `LlamaModelException`, `LlamaContextException`, `LlamaInferenceException`, `LlamaStateException`, `LlamaUnsupportedException`
- Accept optional `details` parameter for additional context
- Include human-readable message in `toString()`

### Library Structure
- Use `library;` directive in top-level export files
- Export clean public APIs via `lib/llamadart.dart`
- Keep implementation details in `lib/src/` subdirectories

### Platform Compatibility
- Use conditional imports for platform-specific backends (`if (dart.library.js_interop)`)
- Tag tests with `@TestOn('vm')` or `@TestOn('browser')`
- Keep `LlamaEngine` free of `dart:ffi` and `dart:io` for web support

### Architecture Principles
- Zero-Patch Strategy: Never modify code in `third_party/`
- Use wrappers and hooks for necessary integrations
- Modular separation: `engine/`, `backends/`, `models/`, `utils/`
- Abstract interfaces in `backends/backend.dart`

### Testing Standards
- New public APIs require unit or integration tests
- Test both Native (VM) and Web implementations for refactored shared logic
- Use `expect` matchers over `assert`
- Close ports/streams in `setUp`/`tearDown` to avoid hanging
- Use `group` for logical test organization

### File Organization
- Library entry point: `lib/llamadart.dart`
- Public APIs in `lib/src/core/` with clear separation: `engine/`, `models/`, `template/`
- Tests mirror lib structure: `test/unit/` and `test/integration/`
- Native assets hook: `hook/build.dart` (downloads precompiled binaries)

### Const & Immutability
- Use `const` constructors wherever possible for immutable classes
- Data classes should have `const` constructors with `const` fields
- Factory constructors can be used but prefer `const` when feasible

### Async Patterns
- Use `Future<T>` and `Stream<T>` from `dart:async`
- Prefer async/await over chained `.then()` calls
- Use `StreamController` for custom streams with proper cleanup
- Cancel streams in `dispose()` methods

### Import Examples
```dart
// Correct import order:
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/engine/engine.dart';
import '../backends/backend.dart';
```

### Exception Examples
```dart
// Throwing proper exceptions:
throw LlamaModelException('Failed to load model', 'Invalid GGUF format');

// Throwing unsupported:
throw LlamaUnsupportedException('GPU acceleration not available on this platform');
```

### Zero-Patch Strategy Details
- All third-party code lives in `third_party/llama_cpp/` subdirectory
- Never edit `third_party/llama_cpp/` source files directly
- Build modifications go in `third_party/CMakeLists.txt` or build scripts
- Allows seamless upstream updates by updating submodule pointers
- Consolidate experimental modules (e.g., `mtmd`) in build configuration

## Development Workflow

### Before Committing
1. Run `dart format .` to ensure code is properly formatted
2. Run `dart analyze` to fix all warnings and lint errors
3. Run `dart test` to verify all tests pass
4. For new features, add tests to maintain 80%+ coverage

### Rebuilding llama.cpp
When you need to rebuild the native llama.cpp library:
```bash
rm -rf .dart_tool  # Clean Dart cache
cd third_party
# macOS targets: macos-arm64, macos-x86_64
# iOS targets: ios-device-arm64, ios-sim-arm64, ios-sim-x86_64
./build_apple.sh macos-arm64
```

Note: This is only necessary when modifying `third_party/` code or testing native changes.

### Adding New Features
1. Create public API in appropriate `lib/src/` subdirectory
2. Export via `lib/src/api/llamadart.dart` if part of public API
3. Add unit tests in `test/unit/` and integration tests in `test/integration/`
4. Update documentation with examples for new APIs
5. Ensure both VM and web implementations work (for shared logic)

### Code Review Checklist
- Public APIs documented with `///` Dart doc comments
- Types explicitly declared on public APIs
- Imports ordered correctly (SDK, packages, relative)
- Exceptions use `LlamaException` hierarchy
- Tests added for new functionality
- No `@ignore` for lints without clear justification
