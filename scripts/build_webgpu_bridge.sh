#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
BRIDGE_DIR="$ROOT_DIR/webgpu_bridge"

DEFAULT_LLAMA_CPP_DIR="$ROOT_DIR/third_party/llama_cpp"
SIBLING_LLAMA_CPP_DIR="$ROOT_DIR/../llama.cpp"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$DEFAULT_LLAMA_CPP_DIR}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.dart_tool/webgpu_bridge/build}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/example/chat_app/web/webgpu_bridge}"
CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Builds the experimental llama.cpp WebGPU prototype bridge.

Environment variables:
  LLAMA_CPP_DIR      Path to llama.cpp source (default: third_party/llama_cpp)
  BUILD_DIR          CMake build directory (default: .dart_tool/webgpu_bridge/build)
  OUT_DIR            Output asset directory (default: example/chat_app/web/webgpu_bridge)
  CMAKE_BUILD_TYPE   CMake build type (default: Release)

Example:
  LLAMA_CPP_DIR="$PWD/third_party/llama_cpp" ./scripts/build_webgpu_bridge.sh
USAGE
  exit 0
fi

if ! command -v emcmake >/dev/null 2>&1; then
  echo "error: emcmake not found in PATH"
  echo "Install and activate emsdk first: https://emscripten.org/docs/getting_started/downloads.html"
  exit 1
fi

if ! command -v emcc >/dev/null 2>&1; then
  echo "error: emcc not found in PATH"
  echo "Install and activate emsdk first: https://emscripten.org/docs/getting_started/downloads.html"
  exit 1
fi

if [[ ! -f "$LLAMA_CPP_DIR/CMakeLists.txt" && -f "$SIBLING_LLAMA_CPP_DIR/CMakeLists.txt" ]]; then
  LLAMA_CPP_DIR="$SIBLING_LLAMA_CPP_DIR"
fi

if [[ ! -f "$LLAMA_CPP_DIR/CMakeLists.txt" ]]; then
  echo "error: llama.cpp source not found at: $LLAMA_CPP_DIR"
  echo "Clone llama.cpp into third_party/llama_cpp or set LLAMA_CPP_DIR explicitly."
  exit 1
fi

mkdir -p "$BUILD_DIR"
mkdir -p "$OUT_DIR"

echo "[webgpu-bridge] configuring with emcmake"
emcmake cmake \
  -S "$BRIDGE_DIR" \
  -B "$BUILD_DIR" \
  -DLLAMA_CPP_DIR="$LLAMA_CPP_DIR" \
  -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE"

echo "[webgpu-bridge] building"
cmake --build "$BUILD_DIR" -j "$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"

CORE_JS="$BUILD_DIR/artifacts/llama_webgpu_core.js"
CORE_WASM="$BUILD_DIR/artifacts/llama_webgpu_core.wasm"
BRIDGE_JS="$BRIDGE_DIR/js/llama_webgpu_bridge.js"

if [[ ! -f "$CORE_JS" || ! -f "$CORE_WASM" ]]; then
  echo "error: build completed but expected artifacts were not found"
  echo "expected: $CORE_JS"
  echo "expected: $CORE_WASM"
  exit 1
fi

cp "$CORE_JS" "$OUT_DIR/llama_webgpu_core.js"
cp "$CORE_WASM" "$OUT_DIR/llama_webgpu_core.wasm"
cp "$BRIDGE_JS" "$OUT_DIR/llama_webgpu_bridge.js"

echo "[webgpu-bridge] done"
echo "  - $OUT_DIR/llama_webgpu_core.js"
echo "  - $OUT_DIR/llama_webgpu_core.wasm"
echo "  - $OUT_DIR/llama_webgpu_bridge.js"
