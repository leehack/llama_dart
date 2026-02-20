---
title: Platform & Backend Matrix
description: Seeded migration page copied from current docs baseline.
---

This is a seeded page used to verify markdown rendering parity during migration.

For the canonical current version, see:

- `website/docs/platforms/support-matrix.md`

## Snapshot

- Apple targets support `cpu` + `metal` via consolidated runtime libs and are
  non-configurable in hook backend-module selection.
- Configurable non-Apple bundles use `llamadart_native_backends` with
  bundle-aware fallback behavior.

## Next step

Replace this seed summary with the full migrated content once sidebar + cross
link mapping is finalized.
