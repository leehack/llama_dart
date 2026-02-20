---
title: Migration Status
description: Current status and milestones for Docusaurus to Jaspr docs migration.
---

## Status

- Branch created: `feat/docs-jaspr`.
- Content migration from `website/docs`: complete.
- Sidebar/navigation parity: complete.
- Mermaid and syntax highlighting support: complete.
- Release-tag-based deploy flow on Jaspr output: complete.

## Completed milestones

1. Import and structure all existing markdown pages from `website/docs`.
2. Implement navigation parity with docs categories.
3. Restore diagram visibility and code syntax highlighting.
4. Replace docs build/deploy workflows to use `website_jaspr/build/jaspr`.
5. Add link validation for generated Jaspr output.

## Remaining cutover note

Legacy Docusaurus files remain in `website/` during transition. Remove them only
after final production smoke checks pass on the Jaspr deploy.
