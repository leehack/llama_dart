#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
OUT_DIR="${WEBGPU_BRIDGE_OUT_DIR:-$ROOT_DIR/example/chat_app/web/webgpu_bridge}"
ASSETS_REPO="${WEBGPU_BRIDGE_ASSETS_REPO:-leehack/llama-web-bridge-assets}"
ASSETS_TAG="${WEBGPU_BRIDGE_ASSETS_TAG:-v0.1.0}"
CDN_BASE="${WEBGPU_BRIDGE_CDN_BASE:-https://cdn.jsdelivr.net/gh/${ASSETS_REPO}@${ASSETS_TAG}}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Downloads prebuilt WebGPU bridge assets into the chat_app web directory.

Default source:
  https://cdn.jsdelivr.net/gh/leehack/llama-web-bridge-assets@v0.1.0

Environment variables:
  WEBGPU_BRIDGE_ASSETS_REPO   Asset repo in owner/repo format
  WEBGPU_BRIDGE_ASSETS_TAG    Asset version/tag (recommended: pinned release tag)
  WEBGPU_BRIDGE_CDN_BASE      Full base URL override (advanced)
  WEBGPU_BRIDGE_OUT_DIR       Destination directory

Usage:
  ./scripts/fetch_webgpu_bridge_assets.sh

Examples:
  WEBGPU_BRIDGE_ASSETS_TAG=v0.1.0 ./scripts/fetch_webgpu_bridge_assets.sh
  WEBGPU_BRIDGE_ASSETS_REPO=acme/llama-web-bridge-assets WEBGPU_BRIDGE_ASSETS_TAG=v2 ./scripts/fetch_webgpu_bridge_assets.sh
USAGE
  exit 0
fi

mkdir -p "$OUT_DIR"

download_required() {
  local file_name="$1"
  local source_url="$CDN_BASE/$file_name"
  local target_path="$OUT_DIR/$file_name"

  echo "[webgpu-assets] downloading $source_url"
  curl -fL --retry 3 --retry-delay 1 "$source_url" -o "$target_path"
}

download_optional() {
  local file_name="$1"
  local source_url="$CDN_BASE/$file_name"
  local target_path="$OUT_DIR/$file_name"

  if curl -fsI "$source_url" >/dev/null; then
    echo "[webgpu-assets] downloading optional $source_url"
    curl -fL --retry 3 --retry-delay 1 "$source_url" -o "$target_path"
  fi
}

download_required "llama_webgpu_bridge.js"
download_required "llama_webgpu_core.js"
download_required "llama_webgpu_core.wasm"
download_optional "manifest.json"
download_optional "sha256sums.txt"

if [[ -f "$OUT_DIR/sha256sums.txt" ]]; then
  echo "[webgpu-assets] verifying checksums"
  (
    cd "$OUT_DIR"
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum -c sha256sums.txt
    elif command -v shasum >/dev/null 2>&1; then
      shasum -a 256 -c sha256sums.txt
    else
      echo "[webgpu-assets] warning: no sha256 tool found; skipping checksum verification"
    fi
  )
fi

echo "[webgpu-assets] done"
echo "  repo: $ASSETS_REPO"
echo "  tag : $ASSETS_TAG"
echo "  out : $OUT_DIR"
