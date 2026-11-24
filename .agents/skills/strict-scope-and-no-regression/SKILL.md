---
name: strict-scope-and-no-regression
description: Mandatory guardrail preventing the agent from deleting, breaking, hiding, or altering any existing feature, UI element, or behavior not explicitly requested by the user.
---
# Strict Scope Lock & Zero-Regression Guardrail

## 1. Golden Rule: Do NOT Touch What Was Not Asked
- Treat every existing feature, toolbar button, popover, modal, keyboard shortcut, gesture, paper template, and chemistry tool as **protected production behavior**.
- When the user asks to fix or upgrade Feature A, you MUST NOT:
  - Delete or comment out Feature B to "simplify" or "clean up" the code.
  - Silently repurpose an existing button/toggle to do something else (e.g., turning Read-Only into Palm Rejection).
  - Rewrite an entire file from scratch and accidentally drop existing features, seed data, or CSS rules.
  - Change unrelated UI layouts, colors, icons, or Vietnamese labels.

## 2. Mandatory Pre-Edit & Post-Edit Verification
1. **Before editing:** Identify the exact narrow scope (file + function/selector) needed for the user's request.
2. **During editing:** Apply minimal, surgical patches (`replace` / targeted diff). Keep all surrounding code byte-for-byte intact.
3. **After editing:** Run a diff check (`git diff --stat` and review removed `-` lines). Every removed line MUST directly belong to the requested change. If any unrelated feature, handler, or UI element was removed or altered, restore it immediately before replying.

## 3. When a Conflict Exists
- If fixing Feature A genuinely requires changing or disabling Feature B, **STOP and ask the user first** with a brief explanation of the tradeoff—never make that destructive decision silently.
