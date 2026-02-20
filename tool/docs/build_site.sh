#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEBSITE_DIR="$ROOT_DIR/website"

if [[ ! -d "$WEBSITE_DIR/node_modules" ]]; then
  echo "[docs] ERROR: website dependencies are missing. Run:"
  echo "  cd website && npm ci"
  exit 1
fi

echo "[docs] Building Docusaurus site"
(
  cd "$WEBSITE_DIR"
  npm run build
)

if [[ ! -f "$WEBSITE_DIR/build/index.html" ]]; then
  echo "[docs] ERROR: site build did not produce build/index.html" >&2
  exit 1
fi

echo "[docs] Site build ready: $WEBSITE_DIR/build"
