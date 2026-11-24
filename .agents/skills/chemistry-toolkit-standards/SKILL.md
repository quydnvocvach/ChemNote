---
name: chemistry-toolkit-standards
description: Chemistry tools, ionic equation balancing, Vietnamese nomenclature, and paper template design standards for ChemNote.
---
# Chemistry Toolkit & Paper Design Standards

## 1. Equation Balancer (Ionic + Molecular)
- Use exact rational `BigInt` Gauss-Jordan elimination (RREF) with:
  - One row per element.
  - One **charge conservation row** whenever any ion (`Fe2+`, `MnO4-`, `Cr2O7^2-`, `H+`) or electron (`e-`) is present.
- Split species smartly so ion charges (`Fe2+ + H+`) are never confused with `+` separators.
- Warn clearly if nullspace dimension > 1 (underdetermined system).
- Format output cleanly with Unicode subscripts (`₀–₉`) and superscripts (`⁺`, `⁻`, `²⁺`, `³⁺`, `²⁻`).

## 2. Molar Mass & Chemistry Data
- Support hydrates (`.`, `·`, `•`, `*`) and nested brackets `()`, `[]`, `{}`.
- Keep Vietnamese element names, formulas, constants, and 21 vector lab/organic stencils 100% offline.

## 3. Aesthetic Paper Templates
- **`sageRibbon` (Mint/Sage Ribbon):** Clean `#A8B9A0` top (`78px`) and bottom (`54px`) bands with `#5F715A` border, flat pastel peach swallowtail ribbon (`#FCD7BE`) at top-left extending below the header band, NO `DATE:` text, spacious edge-to-edge ruled lines (`42px` spacing), and interactive page bookmark ribbon placed at top-right.
