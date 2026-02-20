---
title: Legacy Docusaurus Notes
description: Source-of-truth references while migration is in progress.
---

During migration, the current Docusaurus implementation remains the reference:

- Content: `website/docs`
- Config: `website/docusaurus.config.ts`
- Sidebar: `website/sidebars.ts`
- Deploy workflows:
  - `.github/workflows/docs_pages.yml`
  - `.github/workflows/docs_version_cut.yml`

Production docs currently resolve through:

- [llamadart.leehack.com]({{links.current_docs}})

Use this page to track parity gaps until final cutover.
