---
name: matepad-144hz-ink-engine
description: High-FPS 144Hz handwriting, M-Pencil 3 stylus physics, palm rejection, and smooth scrolling standards for Huawei MatePad 11.5"S (Web/Canvas & Flutter).
---
# MatePad 11.5"S 144Hz Ink & Scroll Engine

## Web / Canvas Rules
1. **Zero Black-Screen & Zero Spikes:**
   - Use `getContext('2d', { alpha: true })` on transparent active-stroke layers. NEVER use `{ desynchronized: true }` on transparent overlays (breaks alpha compositing on Huawei Mali/Maleoon GPUs).
   - Sanitize `getCoalescedEvents()`: discard `(0, 0)` points and sudden >90–160px jumps. Do not draw un-erased `getPredictedEvents()` rays.
2. **Crisp, Organic Handwriting (No Jaggies):**
   - Render ink strokes as **filled variable-width Bézier ribbons** (`ctx.fill()`) with pressure/velocity width modulation, light real-time EMA smoothing, and tapered pen-down/pen-lift tips.
   - Cap ink canvas DPR between `2.0` and `2.5`; re-render visible canvases after pinch-zoom finishes.
   - Use `multiply` blend mode for highlighters on light/cream paper (`screen` on dark paper) so dark text stays sharp.
   - Support M-Pencil 3 tilt (`tiltX`/`tiltY`) for graphite pencil shading.
   - Hide hover cursor ring during pen/highlighter writing; show only for Eraser.
3. **Zero-Lag Pointer & Silky Scroll:**
   - Cache `canvas.getBoundingClientRect()` ONCE on `pointerdown`; never call it inside `pointermove`.
   - When Palm Rejection is ON, allow native browser momentum scrolling (`touch-action: pan-x pan-y pinch-zoom`, `-webkit-overflow-scrolling: touch`) for finger touches while capturing `pointerType === 'pen'` for writing.
   - Virtualize off-screen pages with `IntersectionObserver` (`rootMargin: '1600px 0px'`, async `requestAnimationFrame` restore, keep ±3 pages warm) to stay under ~100MB VRAM.

## Flutter APK Rules
- Use raw `Listener` (`PointerDeviceKind.stylus`) for M-Pencil 3 with `requestUnbufferedDispatch` and 144Hz display mode.
- Wrap each page in `RepaintBoundary`, cache committed strokes into an offscreen `ui.Image` / `Picture`, and draw only the active stroke on the top `CustomPainter`.
