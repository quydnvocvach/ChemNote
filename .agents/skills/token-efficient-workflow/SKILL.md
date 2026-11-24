---
name: token-efficient-workflow
description: Token-saving and fast execution workflow for Antigravity when editing, debugging, or refactoring ChemNote.
---
# Token-Efficient Workflow for ChemNote

## 1. Surgical Context Only
- Locate exact line numbers with grep/search before reading a file. Never dump entire large files (like `index.html` > 9,000 lines) into context.
- When patching large single-file HTML/JS deliverables, apply targeted edits or a small verified patch script instead of regenerating the full file.

## 2. Shift Verification Left
- After every JS edit, extract `<script>` blocks and run `node --check` + targeted unit tests immediately.
- After every Dart/Flutter edit, run `flutter analyze` and `flutter test` before triggering any APK build or browser preview.
- Save expensive browser/UI smoke tests for the final check of a milestone.

## 3. Clean Recovery & No Fake Implementations
- If a multi-step edit drifts, revert cleanly rather than layering patches on top of broken code.
- Never replace a requested real integration with a fake/demo stub while claiming it works.
- When updating PWA files, always update both `index.html` (visible version badge) and `sw.js` (`CACHE_NAME`) in the same commit.
