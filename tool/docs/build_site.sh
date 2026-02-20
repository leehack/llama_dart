#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEBSITE_DIR="$ROOT_DIR/website_jaspr"

if [[ ! -d "$WEBSITE_DIR" ]]; then
  echo "[docs] ERROR: missing website_jaspr directory at $WEBSITE_DIR"
  exit 1
fi

echo "[docs] Resolving website_jaspr dependencies"
(
  cd "$WEBSITE_DIR"
  dart pub get
)

echo "[docs] Building Jaspr site"
(
  cd "$WEBSITE_DIR"
  dart run jaspr_cli:jaspr build
)

if [[ ! -f "$WEBSITE_DIR/build/jaspr/index.html" ]]; then
  echo "[docs] ERROR: site build did not produce build/jaspr/index.html" >&2
  exit 1
fi

echo "[docs] Site build ready: $WEBSITE_DIR/build/jaspr"
