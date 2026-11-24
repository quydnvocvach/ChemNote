# ChemNote Project Rules (Antigravity Workspace)

- **Target Hardware:** Huawei MatePad 11.5"S (144Hz PaperMatte, M-Pencil 3) + Windows Laptop.
- **Branches:** Flutter APK (`lib/`, package `com.chemnote.app`) and Web/PWA (`index.html`, `sw.js`, `manifest.json`).
- **Rule #1 — STRICT SCOPE LOCK (NEVER DELETE OR ALTER UNRELATED FEATURES):**
  - Only modify files, functions, UI controls, CSS, and data schemas explicitly requested in the current prompt.
  - NEVER delete, hide, rename, simplify, or refactor any existing feature, button, modal, paper template, shortcut, or chemistry tool the user did not ask to change.
  - Before finishing, check your diff to guarantee zero regressions or accidental removals.
- **Token Discipline:**
  - Read only the exact target function/file; never scan unrelated folders or rewrite entire multi-thousand-line files.
  - Verify locally (`node --check` for JS, `flutter analyze` / unit tests for Dart) BEFORE UI checks.
- **Technical Guardrails:**
  1. Never store notebooks, images, or PDFs in `localStorage` (5MB limit). Use IndexedDB (Web) or local files + DB (Flutter).
  2. Never use `{ desynchronized: true }` on transparent overlay canvases or leave un-erased `getPredictedEvents()` strokes.
  3. Never place imported PDF slides in the movable `images` array; lock them in the immutable background layer (`pdfBg`).
  4. Always bump `CACHE_NAME` in `sw.js` (Network-First for HTML) whenever updating `index.html`.
- **Skills:** Automatically load the matching skill(s) in `.agents/skills/` before making edits.
