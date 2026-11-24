---
name: offline-storage-and-pdf
description: Zero-data-loss IndexedDB/file storage, lightweight Undo/Redo, locked multi-page PDF annotation, and clean PNG/PDF export for ChemNote.
---
# Offline Storage, Multi-Page PDF & Export Standards

## 1. Storage & Memory Safety
- **Web/PWA:** Persist state in **IndexedDB** with ~550ms debounce plus immediate flush on `visibilitychange`/`pagehide`. Never rely on 5MB `localStorage` (only migrate legacy data once).
- **Binary Deduplication:** Never duplicate base64 strings across `origSrc`, `dataUrl`, and `recentImages` (store compact ≤320px JPEG thumbnails in `recentImages`).
- **Lightweight Undo/Redo:** Intern large base64 blobs (`>= 2KB`) into a pool or use command deltas before pushing snapshots to Undo/Redo stacks.

## 2. Multi-Page PDF Annotation
- Import PDF pages (via PDF.js on Web or `pdfrx`/`pdfx` on Flutter) as individual notebook pages.
- **Lock PDF Slides:** Store rendered slide backgrounds in an immutable `page.pdfBg` layer drawn on the paper background canvas—NEVER inside `page.images`—so Image and Lasso tools cannot accidentally drag or resize slides.

## 3. Accurate PNG & Print/PDF Export
- Composite strictly in Z-order: `paper template -> page.pdfBg -> page.images -> ink strokes & stencils -> wrapped text boxes -> unrevealed study tapes`. Never draw images twice.
- Always word-wrap text boxes to `t.w` when drawing to Canvas (`drawWrappedTextToCtx`); never split solely on `\n`.
- Hash notebook PINs before saving; never store raw plaintext PINs.
- Include `attachments` in all Lasso selection, move, and delete operations.
