---
title: Migration Status
description: Current status and milestones for Docusaurus to Jaspr docs migration.
---

## Status

- Branch created: `feat/docs-jaspr`
- Jaspr docs scaffold: complete
- Latest compatible dependencies: resolved
- Initial branded layout and sidebar: complete

## Planned milestones

1. Import and structure all existing markdown pages from `website/docs`.
2. Implement navigation parity with current docs categories.
3. Verify Mermaid rendering parity on diagram-heavy pages.
4. Add versioning parity (release-tag snapshot flow).
5. Switch production deploy from Docusaurus output to Jaspr output.

## Open technical items

- Map Docusaurus sidebar metadata to Jaspr sidebar groups.
- Confirm preferred markdown extensions required for docs fidelity.
- Implement equivalent broken-link validation in CI.
