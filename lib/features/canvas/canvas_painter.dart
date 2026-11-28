import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/models/drawing_elements.dart';
import '../../core/models/note_page.dart';
import '../chemistry/widgets/stencil_painter.dart';
import 'lasso_controller.dart';
import 'paper_templates.dart';
import 'stroke_engine.dart';

class _WidthPathRun {
  final double width;
  final Path path;

  const _WidthPathRun(this.width, this.path);
}

class _CachedStrokeGeometry {
  final List<StrokePoint> filteredPts;
  Path? centerPath;
  Path? highlighterPath;
  List<_WidthPathRun>? widthRuns;

  _CachedStrokeGeometry(this.filteredPts);
}

/// Layer 1 (Cached in RepaintBoundary): Renders committed elements of a [NotePage]:
/// 1. Paper template background (8 templates × 3 colors)
/// 2. Optional rasterized PDF background image
/// 3. Highlighter ink layer
/// 4. Chemistry vector stencils via [StencilPainter]
/// 5. Committed pen, brush, and graphite pencil strokes
/// 6. Study Tape elements ([TapeElement])
/// 7. Lasso selection bounding box
class CanvasPainter extends CustomPainter {
  static final Expando<_CachedStrokeGeometry> _geometryCache =
      Expando<_CachedStrokeGeometry>('stroke_geom');
  static final Expando<Rect> _boundsCache = Expando<Rect>('stroke_bounds');

  /// Computes and caches the padded bounding box of a [Stroke] in O(1) after first lookup.
  static Rect strokeBounds(Stroke stroke) {
    final cached = _boundsCache[stroke];
    if (cached != null) return cached;
    final pts = stroke.points;
    if (pts.isEmpty) return Rect.zero;
    double minX = pts.first.x, maxX = minX;
    double minY = pts.first.y, maxY = minY;
    for (int i = 1; i < pts.length; i++) {
      final p = pts[i];
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final pad = stroke.width * 0.5;
    final rect = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
    _boundsCache[stroke] = rect;
    return rect;
  }

  static _CachedStrokeGeometry _getOrBuildGeometry(
    Stroke stroke, {
    required bool cacheable,
  }) {
    if (cacheable) {
      final existing = _geometryCache[stroke];
      if (existing != null) return existing;
    }
    final geom = _CachedStrokeGeometry(_filterRenderPoints(stroke.points));
    if (cacheable) {
      _geometryCache[stroke] = geom;
    }
    return geom;
  }

  final NotePage page;
  final ui.Image? pdfBackgroundImage;
  final Map<String, ui.Image> elementImageCache;
  final LassoSelection lassoSelection;
  final Rect? lassoSelectionBounds;
  final ValueListenable<Offset>? lassoDragOffset;
  final ValueListenable<({String pageId, List<Stroke> strokes})?>?
      erasingStrokesNotifier;
  final String? hiddenImageId;
  final String? playingAudioId;
  final int? playingAudioTimeMs;
  final ValueListenable<int>? playingAudioTimeMsNotifier;
  final int repaintVersion;
  final bool drawBackground;
  final bool drawOverlays;
  final bool drawTapes;
  final int? minZExclusive;
  final int? maxZInclusive;

  CanvasPainter({
    required this.page,
    this.pdfBackgroundImage,
    this.elementImageCache = const {},
    this.lassoSelection = const LassoSelection(),
    this.lassoSelectionBounds,
    this.lassoDragOffset,
    this.erasingStrokesNotifier,
    this.hiddenImageId,
    this.playingAudioId,
    this.playingAudioTimeMs,
    this.playingAudioTimeMsNotifier,
    this.repaintVersion = 0,
    this.drawBackground = true,
    this.drawOverlays = true,
    this.drawTapes = true,
    this.minZExclusive,
    this.maxZInclusive,
  }) : super(
          repaint: Listenable.merge([
            if (lassoDragOffset != null) lassoDragOffset,
            if (erasingStrokesNotifier != null) erasingStrokesNotifier,
            if (playingAudioTimeMsNotifier != null) playingAudioTimeMsNotifier,
          ]),
        );

  bool _inZRange(int z) {
    if (minZExclusive != null && z <= minZExclusive!) return false;
    if (maxZInclusive != null && z > maxZInclusive!) return false;
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Paper template layer (A4 or seamless Infinite Whiteboard)
    if (drawBackground) {
      PaperTemplatePainter(
        templateType: page.templateType,
        paperColor: page.paperColor,
        isLandscape: page.isLandscape,
        isInfiniteWhiteboard: page.isInfiniteWhiteboard,
      ).paint(canvas, size);

      // 2. Optional PDF page background image
      if (pdfBackgroundImage != null) {
        _paintPdfBackground(canvas, size, pdfBackgroundImage!);
      }
    }

    // 3. Chronological Z-Index Layering across Images, Stencils, Highlighters & Pen Strokes
    // Tie-break order for legacy zIndex == 0: 0=image, 1=highlighter, 2=stencil, 3=ink
    final bool isDarkPaper = page.paperColor == PaperColorType.dark;
    final items = <({int z, int tie, int seq, Object item})>[];
    int seq = 0;

    final erasingOverride = erasingStrokesNotifier?.value;
    final List<Stroke> activeStrokes =
        (erasingOverride != null && erasingOverride.pageId == page.id)
            ? erasingOverride.strokes
            : page.strokes;

    for (final img in page.imageElements) {
      if (_inZRange(img.zIndex)) {
        items.add((z: img.zIndex, tie: 0, seq: seq++, item: img));
      }
    }
    for (final stroke in activeStrokes) {
      if (_inZRange(stroke.zIndex)) {
        final tie = stroke.toolType == ToolType.highlighter ? 1 : 3;
        items.add((z: stroke.zIndex, tie: tie, seq: seq++, item: stroke));
      }
    }
    for (final stencil in page.stencilElements) {
      if (_inZRange(stencil.zIndex)) {
        items.add((z: stencil.zIndex, tie: 2, seq: seq++, item: stencil));
      }
    }

    items.sort((a, b) {
      final c = a.z.compareTo(b.z);
      if (c != 0) return c;
      final t = a.tie.compareTo(b.tie);
      if (t != 0) return t;
      return a.seq.compareTo(b.seq);
    });

    final Offset dragDelta = lassoDragOffset?.value ?? Offset.zero;
    final bool hasDragDelta = dragDelta != Offset.zero;

    for (final entry in items) {
      final obj = entry.item;
      if (obj is ImageElement) {
        if (obj.id == hiddenImageId) continue;
        final uiImg = elementImageCache[obj.filePath];
        if (uiImg != null) {
          final bool sel = lassoSelection.imageIds.contains(obj.id);
          if (sel && hasDragDelta) {
            canvas.save();
            canvas.translate(dragDelta.dx, dragDelta.dy);
          }
          _paintHighResImageElement(
            canvas,
            obj,
            uiImg,
            isSelected: sel,
          );
          if (sel && hasDragDelta) canvas.restore();
        }
      } else if (obj is StencilElement) {
        final bool sel = lassoSelection.stencilIds.contains(obj.id);
        if (sel && hasDragDelta) {
          canvas.save();
          canvas.translate(dragDelta.dx, dragDelta.dy);
        }
        _paintStencilElement(
          canvas,
          obj,
          isSelected: sel,
        );
        if (sel && hasDragDelta) canvas.restore();
      } else if (obj is Stroke) {
        final bool sel = lassoSelection.strokeIds.contains(obj.id);
        final audioState = _audioVisualForStroke(obj);
        if (sel && hasDragDelta) {
          canvas.save();
          canvas.translate(dragDelta.dx, dragDelta.dy);
        }
        if (obj.toolType == ToolType.highlighter) {
          paintHighlighterStroke(
            canvas,
            obj,
            isDarkPaper: isDarkPaper,
            isSelected: sel,
            opacityMultiplier: audioState.opacityMultiplier,
            isAudioHighlighted: audioState.isHighlighted,
          );
        } else {
          paintInkStroke(
            canvas,
            obj,
            isSelected: sel,
            opacityMultiplier: audioState.opacityMultiplier,
            isAudioHighlighted: audioState.isHighlighted,
          );
        }
        if (sel && hasDragDelta) canvas.restore();
      }
    }

    if (drawOverlays) {
      // 4. Study Tape elements (100% opaque in thumbnails/static pass; interactive widget handles live editor)
      if (drawTapes) {
        for (final tape in page.tapeElements) {
          paintStudyTape(
            canvas,
            tape,
            isSelected: lassoSelection.tapeIds.contains(tape.id),
          );
        }
      }

      // 5. Lasso selection bounding box (translated live at 144fps during drag)
      if (lassoSelectionBounds != null && lassoSelection.isNotEmpty) {
        final Rect liveBounds = hasDragDelta
            ? lassoSelectionBounds!.shift(dragDelta)
            : lassoSelectionBounds!;
        _paintSelectionBounds(canvas, liveBounds);
      }
    }
  }

  void _paintPdfBackground(Canvas canvas, Size size, ui.Image image) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(image.width.toDouble(), image.height.toDouble()),
      size,
    );
    final dst = Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );
  }

  /// Renders an [ImageElement] directly from the full-resolution source
  /// [ui.Image] using normalized non-destructive crop coordinates and optional
  /// freehand clip polygon with [FilterQuality.high] so tiny cropped regions
  /// never blur or pixelate.
  void _paintHighResImageElement(
    Canvas canvas,
    ImageElement element,
    ui.Image image, {
    required bool isSelected,
  }) {
    canvas.save();
    final cx = element.x + element.width * 0.5;
    final cy = element.y + element.height * 0.5;
    canvas.translate(cx, cy);
    if (element.rotation != 0.0) {
      canvas.rotate(element.rotation);
    }
    canvas.translate(-element.width * 0.5, -element.height * 0.5);

    final dst = Rect.fromLTWH(0, 0, element.width, element.height);
    final src = Rect.fromLTRB(
      (element.cropLeft.clamp(0.0, 0.995)) * image.width,
      (element.cropTop.clamp(0.0, 0.995)) * image.height,
      (element.cropRight.clamp(0.005, 1.0)) * image.width,
      (element.cropBottom.clamp(0.005, 1.0)) * image.height,
    );

    if (element.freehandClipPath.length >= 3) {
      final clip = Path()
        ..moveTo(
          element.freehandClipPath.first.x * element.width,
          element.freehandClipPath.first.y * element.height,
        );
      for (int i = 1; i < element.freehandClipPath.length; i++) {
        clip.lineTo(
          element.freehandClipPath[i].x * element.width,
          element.freehandClipPath[i].y * element.height,
        );
      }
      clip.close();
      canvas.clipPath(clip);
    }

    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );

    if (isSelected) {
      canvas.drawRect(
        dst,
        Paint()
          ..color = const Color(0xFF3B82F6).withAlpha(55)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.restore();
  }

  ({double opacityMultiplier, bool isHighlighted}) _audioVisualForStroke(
    Stroke stroke,
  ) {
    final int? activeTimeMs =
        playingAudioTimeMsNotifier?.value ?? playingAudioTimeMs;
    if (playingAudioId == null ||
        activeTimeMs == null ||
        stroke.audioId != playingAudioId ||
        stroke.audioTimeMs == null) {
      return (opacityMultiplier: 1.0, isHighlighted: false);
    }
    final diff = stroke.audioTimeMs! - activeTimeMs;
    if (diff > 0) {
      return (opacityMultiplier: 0.22, isHighlighted: false);
    }
    if (diff.abs() < 1200) {
      return (opacityMultiplier: 1.0, isHighlighted: true);
    }
    return (opacityMultiplier: 1.0, isHighlighted: false);
  }

  static void paintHighlighterStroke(
    Canvas canvas,
    Stroke stroke, {
    required bool isDarkPaper,
    required bool isSelected,
    double opacityMultiplier = 1.0,
    bool isAudioHighlighted = false,
    bool isLive = false,
  }) {
    if (stroke.points.isEmpty) return;

    final baseColor = Color(stroke.colorValue);
    final alpha = ((isDarkPaper ? 95 : 108) * opacityMultiplier)
        .round()
        .clamp(12, 255);
    final paint = Paint()
      ..color = baseColor.withAlpha(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round
      ..blendMode = isDarkPaper ? BlendMode.srcOver : BlendMode.multiply
      ..isAntiAlias = true;

    final Path path;
    if (isLive) {
      path = StrokeEngine.buildCenterlinePath(stroke.points);
    } else {
      final geom = _getOrBuildGeometry(stroke, cacheable: true);
      path = geom.highlighterPath ??=
          StrokeEngine.buildCenterlinePath(stroke.points);
    }
    if (isAudioHighlighted) {
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF3B82F6).withAlpha(115)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.width + 6.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.drawPath(path, paint);

    if (isSelected) {
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF3B82F6).withAlpha(110)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.width + 4.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  static void paintInkStroke(
    Canvas canvas,
    Stroke stroke, {
    required bool isSelected,
    double opacityMultiplier = 1.0,
    bool isAudioHighlighted = false,
    bool isLive = false,
  }) {
    if (stroke.points.isEmpty) return;

    final baseColor = Color(stroke.colorValue);
    final baseAlpha = (stroke.colorValue >> 24) & 0xFF;
    final color = opacityMultiplier >= 0.99
        ? baseColor
        : baseColor.withAlpha(
            (baseAlpha * opacityMultiplier).round().clamp(16, 255),
          );

    // Recognized geometric shapes render as pure exact geometry (ZERO chord lines or Bezier deformation!)
    if (stroke.shapeType != ShapeType.none) {
      final pts = stroke.points;
      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      void drawShapeWithPaint(Paint p) {
        if (stroke.shapeType == ShapeType.line) {
          canvas.drawLine(
            Offset(pts.first.x, pts.first.y),
            Offset(pts.last.x, pts.last.y),
            p,
          );
          return;
        }
        if (stroke.shapeType == ShapeType.circle) {
          double minX = pts.first.x, maxX = pts.first.x;
          double minY = pts.first.y, maxY = pts.first.y;
          for (final pt in pts) {
            if (pt.x < minX) minX = pt.x;
            if (pt.x > maxX) maxX = pt.x;
            if (pt.y < minY) minY = pt.y;
            if (pt.y > maxY) maxY = pt.y;
          }
          canvas.drawOval(Rect.fromLTRB(minX, minY, maxX, maxY), p);
          return;
        }
        final path = Path()..moveTo(pts.first.x, pts.first.y);
        for (int i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].x, pts[i].y);
        }
        path.close();
        canvas.drawPath(path, p);
      }

      if (isAudioHighlighted) {
        drawShapeWithPaint(
          Paint()
            ..color = const Color(0xFF3B82F6).withAlpha(135)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.width + 8.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
        );
      }
      if (isSelected) {
        drawShapeWithPaint(
          Paint()
            ..color = const Color(0xFF3B82F6).withAlpha(75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.width + 6.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      drawShapeWithPaint(strokePaint);
      return;
    }

    // 1. Filter consecutive micro-points (< 0.75 px) once and cache per committed Stroke
    final _CachedStrokeGeometry geom =
        _getOrBuildGeometry(stroke, cacheable: !isLive);
    final List<StrokePoint> pts = geom.filteredPts;
    if (pts.isEmpty) return;

    final bool isPencil = stroke.toolType == ToolType.pencil;
    final Color inkColor = isPencil
        ? color.withAlpha((195 * opacityMultiplier).round().clamp(16, 255))
        : color;

    // Single-point tap: crisp anti-aliased dot
    if (pts.length == 1) {
      final r = math.max(0.8, stroke.width * 0.5);
      final dotCenter = Offset(pts.first.x, pts.first.y);
      if (isAudioHighlighted) {
        canvas.drawCircle(
          dotCenter,
          r + 3.5,
          Paint()
            ..color = const Color(0xFF3B82F6).withAlpha(140)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
        );
      }
      if (isSelected) {
        canvas.drawCircle(
          dotCenter,
          r + 2.5,
          Paint()..color = const Color(0xFF3B82F6).withAlpha(75),
        );
      }
      canvas.drawCircle(
        dotCenter,
        r,
        Paint()
          ..color = inkColor
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
      return;
    }

    // Build smooth quadratic midpoint centerline path ONLY when needed
    final bool needsCenterPath = isAudioHighlighted ||
        isSelected ||
        stroke.toolType == ToolType.ballpointPen;
    Path? smoothCenterPath;
    if (needsCenterPath) {
      smoothCenterPath = isLive
          ? _buildQuadraticMidpointPath(pts)
          : (geom.centerPath ??= _buildQuadraticMidpointPath(pts));
    }

    if (isAudioHighlighted && smoothCenterPath != null) {
      canvas.drawPath(
        smoothCenterPath,
        Paint()
          ..color = const Color(0xFF3B82F6).withAlpha(140)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.width + 7.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );
    }

    if (isSelected && smoothCenterPath != null) {
      canvas.drawPath(
        smoothCenterPath,
        Paint()
          ..color = const Color(0xFF3B82F6).withAlpha(75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.width + 5.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Ballpoint Pen: crisp uniform-width quadratic Bezier stroke
    if (stroke.toolType == ToolType.ballpointPen) {
      canvas.drawPath(
        smoothCenterPath!,
        Paint()
          ..color = inkColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.width.clamp(0.6, 40.0)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
      return;
    }

    // Fountain Pen / Brush Pen / Pencil: Quantized width-batched quadratic midpoint runs
    // cached for committed strokes to slash drawPath calls 4x-15x at 144Hz.
    final segPaint = Paint()
      ..color = inkColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    if (isPencil) {
      segPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.45);
    }

    final List<_WidthPathRun> runs = isLive
        ? _buildWidthBatchedRuns(pts, stroke)
        : (geom.widthRuns ??= _buildWidthBatchedRuns(pts, stroke));

    for (final run in runs) {
      segPaint.strokeWidth = run.width;
      canvas.drawPath(run.path, segPaint);
    }
  }

  static List<_WidthPathRun> _buildWidthBatchedRuns(
    List<StrokePoint> pts,
    Stroke stroke,
  ) {
    final widths = _computeSmoothedStrokeWidths(pts, stroke);
    if (pts.length == 2) {
      final w = (widths[0] + widths[1]) * 0.5;
      final p = Path()
        ..moveTo(pts[0].x, pts[0].y)
        ..lineTo(pts[1].x, pts[1].y);
      return [_WidthPathRun(w, p)];
    }

    final runs = <_WidthPathRun>[];
    const double bucketThreshold = 0.14;

    final firstMid = Offset(
      (pts[0].x + pts[1].x) * 0.5,
      (pts[0].y + pts[1].y) * 0.5,
    );
    double bucketWidth =
        (((widths[0] + widths[1]) * 0.5) * 10.0).roundToDouble() / 10.0;
    Path activePath = Path()
      ..moveTo(pts[0].x, pts[0].y)
      ..lineTo(firstMid.dx, firstMid.dy);
    Offset prevMid = firstMid;

    void switchRunIfNeeded(double rawWidth, Offset segStart) {
      if ((rawWidth - bucketWidth).abs() > bucketThreshold) {
        runs.add(_WidthPathRun(bucketWidth, activePath));
        bucketWidth = (rawWidth * 10.0).roundToDouble() / 10.0;
        activePath = Path()..moveTo(segStart.dx, segStart.dy);
      }
    }

    for (int i = 1; i < pts.length - 1; i++) {
      final p = pts[i];
      final next = pts[i + 1];
      final nextMid = Offset((p.x + next.x) * 0.5, (p.y + next.y) * 0.5);
      switchRunIfNeeded(widths[i], prevMid);
      activePath.quadraticBezierTo(p.x, p.y, nextMid.dx, nextMid.dy);
      prevMid = nextMid;
    }

    final lastWidth = (widths[pts.length - 2] + widths[pts.length - 1]) * 0.5;
    switchRunIfNeeded(lastWidth, prevMid);
    activePath.lineTo(pts.last.x, pts.last.y);
    runs.add(_WidthPathRun(bucketWidth, activePath));
    return runs;
  }

  /// Filters out consecutive micro-points closer than 0.75 px while preserving endpoints.
  static List<StrokePoint> _filterRenderPoints(List<StrokePoint> raw) {
    if (raw.length <= 2) return raw;
    const double minDistSq = 0.75 * 0.75;
    final out = <StrokePoint>[raw.first];
    for (int i = 1; i < raw.length - 1; i++) {
      final prev = out.last;
      final cur = raw[i];
      final dx = cur.x - prev.x;
      final dy = cur.y - prev.y;
      if (dx * dx + dy * dy >= minDistSq) {
        out.add(cur);
      }
    }
    final last = raw.last;
    final prev = out.last;
    final dx = last.x - prev.x;
    final dy = last.y - prev.y;
    if (dx * dx + dy * dy >= 0.04 || out.length == 1) {
      out.add(last);
    } else {
      out[out.length - 1] = last;
    }
    return out;
  }

  static Path _buildQuadraticMidpointPath(List<StrokePoint> pts) {
    final path = Path()..moveTo(pts.first.x, pts.first.y);
    if (pts.length == 2) {
      path.lineTo(pts[1].x, pts[1].y);
      return path;
    }
    for (int i = 1; i < pts.length - 1; i++) {
      final p = pts[i];
      final next = pts[i + 1];
      path.quadraticBezierTo(
        p.x,
        p.y,
        (p.x + next.x) * 0.5,
        (p.y + next.y) * 0.5,
      );
    }
    path.lineTo(pts.last.x, pts.last.y);
    return path;
  }

  /// Computes a 3-point smoothed calligraphic width envelope combining
  /// M-Pencil 3 pressure, subtle velocity thinning, and gentle rounded start/end tapers.
  static List<double> _computeSmoothedStrokeWidths(
    List<StrokePoint> pts,
    Stroke stroke,
  ) {
    final int n = pts.length;
    final raw = List<double>.filled(n, stroke.width);
    final double base = stroke.width.clamp(0.6, 40.0);

    for (int i = 0; i < n; i++) {
      final p = pts[i];
      final double press = p.pressure.clamp(0.08, 1.0);
      double w;

      if (stroke.toolType == ToolType.fountainPen) {
        // Authentic fountain pen: smooth pressure curve + subtle velocity thinning
        double velFactor = 1.0;
        if (i > 0) {
          final prev = pts[i - 1];
          final dt = math.max(1, p.timestamp - prev.timestamp);
          final dx = p.x - prev.x;
          final dy = p.y - prev.y;
          final dist = math.sqrt(dx * dx + dy * dy);
          final speed = dist / dt; // px per ms
          // Fast strokes slightly crisper (0.88), slow downstrokes slightly richer (1.06)
          velFactor = (1.06 - speed * 0.14).clamp(0.88, 1.06);
        }
        w = base * (0.58 + 0.72 * press) * velFactor;
      } else if (stroke.toolType == ToolType.brushPen) {
        w = base * (0.32 + 1.33 * press);
      } else if (stroke.toolType == ToolType.pencil) {
        w = StrokeEngine.radiusForPoint(
              p,
              baseWidth: base,
              toolType: ToolType.pencil,
            ) *
            2.0;
      } else {
        w = base;
      }

      // Gentle natural rounded start/end taper (NEVER sharp needle spikes!)
      if (n >= 5) {
        if (i == 0) {
          w *= 0.76;
        } else if (i == 1) {
          w *= 0.89;
        } else if (i == n - 1) {
          w *= 0.75;
        } else if (i == n - 2) {
          w *= 0.83;
        } else if (i == n - 3) {
          w *= 0.91;
        }
      }

      raw[i] = w.clamp(0.55, base * 2.2);
    }

    // 2 passes of 3-point binomial smoothing: 0.25*r[i-1] + 0.5*r[i] + 0.25*r[i+1]
    // Ping-pong between two buffers to eliminate per-frame allocations at 144Hz.
    var cur = raw;
    if (n >= 3) {
      var next = List<double>.filled(n, 0.0);
      for (int pass = 0; pass < 2; pass++) {
        next[0] = cur[0];
        next[n - 1] = cur[n - 1];
        for (int i = 1; i < n - 1; i++) {
          next[i] = 0.25 * cur[i - 1] + 0.50 * cur[i] + 0.25 * cur[i + 1];
        }
        final tmp = cur;
        cur = next;
        next = tmp;
      }
    }
    return cur;
  }

  static void paintStudyTape(
    Canvas canvas,
    TapeElement tape, {
    required bool isSelected,
  }) {
    final rect = Rect.fromLTWH(tape.x, tape.y, tape.width, tape.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    final baseColor = Color(tape.colorValue);

    if (tape.isRevealed) {
      // Revealed state: faint dashed outline so user can tap again to re-cover
      canvas.drawRRect(
        rrect,
        Paint()..color = baseColor.withAlpha(24),
      );
      _drawDashedPath(
        canvas,
        Path()..addRRect(rrect),
        Paint()
          ..color = baseColor.withAlpha(160)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
        dashLength: 5.0,
        gapLength: 4.0,
      );
    } else {
      // Covered state: 100% solid opaque tape strip (zero ink bleed-through!)
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(rect, Paint()..color = baseColor.withAlpha(255));
      final stripePaint = Paint()
        ..color = Colors.white.withAlpha(42)
        ..strokeWidth = 4.0;
      for (double x = rect.left - rect.height; x < rect.right + rect.height; x += 14.0) {
        canvas.drawLine(
          Offset(x, rect.bottom),
          Offset(x + rect.height, rect.top),
          stripePaint,
        );
      }
      canvas.restore();
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isSelected ? const Color(0xFF3B82F6) : Colors.black.withAlpha(40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.2 : 1.0,
      );
    }
  }

  void _paintStencilElement(
    Canvas canvas,
    StencilElement stencil, {
    required bool isSelected,
  }) {
    canvas.save();
    final centerX = stencil.x + stencil.width * 0.5;
    final centerY = stencil.y + stencil.height * 0.5;
    canvas.translate(centerX, centerY);
    if (stencil.rotation != 0.0) {
      canvas.rotate(stencil.rotation);
    }
    canvas.translate(-stencil.width * 0.5, -stencil.height * 0.5);

    if (isSelected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-4, -4, stencil.width + 8, stencil.height + 8),
          const Radius.circular(6),
        ),
        Paint()
          ..color = const Color(0xFF3B82F6).withAlpha(38)
          ..style = PaintingStyle.fill,
      );
    }

    StencilPainter.paintStencil(
      canvas,
      Size(stencil.width, stencil.height),
      stencil.stencilId,
      Color(stencil.colorValue),
      stencil.strokeWidth,
    );

    canvas.restore();
  }

  void _paintSelectionBounds(Canvas canvas, Rect bounds) {
    canvas.drawRect(
      bounds,
      Paint()
        ..color = const Color(0xFF3B82F6).withAlpha(20)
        ..style = PaintingStyle.fill,
    );

    _drawDashedPath(
      canvas,
      Path()..addRect(bounds),
      Paint()
        ..color = const Color(0xFF3B82F6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
      dashLength: 6.0,
      gapLength: 4.0,
    );

    final handleFill = Paint()..color = Colors.white;
    final handleStroke = Paint()
      ..color = const Color(0xFF3B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    for (final c in [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ]) {
      canvas.drawCircle(c, 5.5, handleFill);
      canvas.drawCircle(c, 5.5, handleStroke);
    }
  }

  static void _drawDashedPath(
    Canvas canvas,
    Path source,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    for (final metric in source.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) {
    return oldDelegate.repaintVersion != repaintVersion ||
        oldDelegate.page != page ||
        oldDelegate.pdfBackgroundImage != pdfBackgroundImage ||
        oldDelegate.lassoSelection != lassoSelection ||
        oldDelegate.lassoSelectionBounds != lassoSelectionBounds ||
        oldDelegate.lassoDragOffset != lassoDragOffset ||
        oldDelegate.hiddenImageId != hiddenImageId ||
        oldDelegate.playingAudioId != playingAudioId ||
        oldDelegate.playingAudioTimeMs != playingAudioTimeMs ||
        oldDelegate.playingAudioTimeMsNotifier != playingAudioTimeMsNotifier ||
        oldDelegate.drawBackground != drawBackground ||
        oldDelegate.drawOverlays != drawOverlays ||
        oldDelegate.minZExclusive != minZExclusive ||
        oldDelegate.maxZInclusive != maxZInclusive;
  }
}

/// Layer 2 (144Hz Ultra-Low-Latency Overlay): Repaints directly from
/// [ValueListenable]s without rebuilding the Flutter widget tree!
/// Draws the live in-progress stroke using a zero-lag raw path during
/// pointermove (smoothing runs once on pointerup), eraser cursor, active lasso
/// marquee, and active study-tape drag preview. Floating hover circle removed.
class ActiveStrokePainter extends CustomPainter {
  final ValueListenable<Stroke?> activeStroke;
  final ValueListenable<Offset?> eraserCursor;
  final ValueListenable<List<Offset>> lassoPath;
  final ValueListenable<Rect?> tapeDraftRect;
  final bool isDarkPaper;
  final double eraserRadius;
  final Color tapeColor;

  ActiveStrokePainter({
    required this.activeStroke,
    required this.eraserCursor,
    required this.lassoPath,
    required this.tapeDraftRect,
    required this.isDarkPaper,
    this.eraserRadius = 18.0,
    this.tapeColor = const Color(0xFF6366F1),
  }) : super(
          repaint: Listenable.merge([
            activeStroke,
            eraserCursor,
            lassoPath,
            tapeDraftRect,
          ]),
        );

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Live in-progress stroke (exact same silky quadratic midpoint renderer as committed ink!)
    final stroke = activeStroke.value;
    if (stroke != null && stroke.points.isNotEmpty) {
      if (stroke.toolType == ToolType.highlighter) {
        CanvasPainter.paintHighlighterStroke(
          canvas,
          stroke,
          isDarkPaper: isDarkPaper,
          isSelected: false,
          isLive: true,
        );
      } else {
        CanvasPainter.paintInkStroke(
          canvas,
          stroke,
          isSelected: false,
          isLive: true,
        );
      }
    }

    // 2. Active study-tape drag preview
    final draftTape = tapeDraftRect.value;
    if (draftTape != null && draftTape.width > 4 && draftTape.height > 4) {
      CanvasPainter.paintStudyTape(
        canvas,
        TapeElement(
          id: 'draft',
          x: draftTape.left,
          y: draftTape.top,
          width: draftTape.width,
          height: draftTape.height,
          // ignore: deprecated_member_use
          colorValue: tapeColor.value,
          isRevealed: false,
        ),
        isSelected: true,
      );
    }

    // 3. Active freeform lasso marquee
    final lPts = lassoPath.value;
    if (lPts.length >= 2) {
      final path = Path()..moveTo(lPts.first.dx, lPts.first.dy);
      for (int i = 1; i < lPts.length; i++) {
        path.lineTo(lPts[i].dx, lPts[i].dy);
      }
      final fillPath = Path.from(path)..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..color = const Color(0xFF3B82F6).withAlpha(24)
          ..style = PaintingStyle.fill,
      );
      CanvasPainter._drawDashedPath(
        canvas,
        path,
        Paint()
          ..color = const Color(0xFF3B82F6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
        dashLength: 7.0,
        gapLength: 5.0,
      );
    }

    // 4. Eraser cursor circle (only shown while actively erasing)
    final ePos = eraserCursor.value;
    if (ePos != null) {
      canvas.drawCircle(
        ePos,
        eraserRadius,
        Paint()
          ..color = const Color(0xFFEF4444).withAlpha(28)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        ePos,
        eraserRadius,
        Paint()
          ..color = const Color(0xFFEF4444).withAlpha(190)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ActiveStrokePainter oldDelegate) {
    return oldDelegate.isDarkPaper != isDarkPaper ||
        oldDelegate.eraserRadius != eraserRadius;
  }
}
