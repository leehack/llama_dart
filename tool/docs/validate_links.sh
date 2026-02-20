#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"$ROOT_DIR/tool/docs/build_site.sh"

python3 - <<'PY'
import re
from pathlib import Path

build_dir = Path('website_jaspr/build/jaspr')
if not build_dir.exists():
    raise SystemExit('[docs] ERROR: build output not found at website_jaspr/build/jaspr')

href_re = re.compile(r'href="([^"]+)"')
html_files = list(build_dir.rglob('*.html'))
broken = []
checked = 0

def is_asset(path: str) -> bool:
    return any(
        path.endswith(ext)
        for ext in (
            '.js', '.css', '.svg', '.png', '.jpg', '.jpeg', '.ico',
            '.json', '.txt', '.map', '.yaml', '.md', '.webp',
            '.woff', '.woff2', '.ttf'
        )
    )

for html in html_files:
    text = html.read_text(encoding='utf-8', errors='ignore')
    for href in href_re.findall(text):
        if (
            not href
            or href.startswith('#')
            or href.startswith('http://')
            or href.startswith('https://')
            or href.startswith('mailto:')
            or href.startswith('javascript:')
        ):
            continue

        checked += 1
        href = href.split('#', 1)[0].split('?', 1)[0]
        if not href:
            continue

        if href.startswith('/'):
            path = href.lstrip('/')
            if is_asset(path):
                if not (build_dir / path).exists():
                    broken.append((str(html), href))
                continue

            route = href.rstrip('/') or '/'
            candidates = [
                build_dir / (route.lstrip('/') + '/index.html'),
                build_dir / (route.lstrip('/') + '.html'),
            ]
            if route == '/':
                candidates.append(build_dir / 'index.html')
            if not any(c.exists() for c in candidates):
                broken.append((str(html), href))
        else:
            target = html.parent / href
            if is_asset(href):
                if not target.exists():
                    broken.append((str(html), href))
                continue

            if not any(c.exists() for c in (target / 'index.html', target.with_suffix('.html'))):
                broken.append((str(html), href))

if broken:
    print(f'[docs] ERROR: found {len(broken)} broken internal links after checking {checked} href entries.')
    for source, href in broken[:100]:
        print(f'  - {source} -> {href}')
    raise SystemExit(1)

print(f'[docs] Link validation passed ({checked} internal href entries checked).')
PY
