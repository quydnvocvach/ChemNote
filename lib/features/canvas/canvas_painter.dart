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

/// Layer 1 (Cached in RepaintBoundary): Renders committed elements of a [NotePage]:
/// 1. Paper template background (8 templates × 3 colors)
/// 2. Optional rasterized PDF background image
/// 3. Highlighter ink layer
/// 4. Chemistry vector stencils via [StencilPainter]
/// 5. Committed pen, brush, and graphite pencil strokes
/// 6. Study Tape elements ([TapeElement])
/// 7. Lasso selection bounding box
class CanvasPainter extends CustomPainter {
  final NotePage page;
  final ui.Image? pdfBackgroundImage;
  final Map<String, ui.Image> elementImageCache;
  final LassoSelection lassoSelection;
  final Rect? lassoSelectionBounds;
  final int repaintVersion;

  const CanvasPainter({
    required this.page,
    this.pdfBackgroundImage,
    this.elementImageCache = const {},
    this.lassoSelection = const LassoSelection(),
    this.lassoSelectionBounds,
    this.repaintVersion = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Paper template layer
    PaperTemplatePainter(
      templateType: page.templateType,
      paperColor: page.paperColor,
      isLandscape: page.isLandscape,
    ).paint(canvas, size);

    // 2. Optional PDF page background image
    if (pdfBackgroundImage != null) {
      _paintPdfBackground(canvas, size, pdfBackgroundImage!);
    }

    // 2b. High-resolution non-destructive cropped ImageElements
    for (final img in page.imageElements) {
      final uiImg = elementImageCache[img.filePath];
      if (uiImg != null) {
        _paintHighResImageElement(
          canvas,
          img,
          uiImg,
          isSelected: lassoSelection.imageIds.contains(img.id),
        );
      }
    }

    // 3. Highlighter layer (underneath opaque pen ink)
    final bool isDarkPaper = page.paperColor == PaperColorType.dark;
    for (final stroke in page.strokes) {
      if (stroke.toolType == ToolType.highlighter) {
        paintHighlighterStroke(
          canvas,
          stroke,
          isDarkPaper: isDarkPaper,
          isSelected: lassoSelection.strokeIds.contains(stroke.id),
        );
      }
    }

    // 4. Vector chemistry stencils layer
    for (final stencil in page.stencilElements) {
      _paintStencilElement(
        canvas,
        stencil,
        isSelected: lassoSelection.stencilIds.contains(stencil.id),
      );
    }

    // 5. Committed pen / brush / pencil strokes
    for (final stroke in page.strokes) {
      if (stroke.toolType != ToolType.highlighter) {
        paintInkStroke(
          canvas,
          stroke,
          isSelected: lassoSelection.strokeIds.contains(stroke.id),
        );
      }
    }

    // 6. Study Tape elements
    for (final tape in page.tapeElements) {
      paintStudyTape(
        canvas,
        tape,
        isSelected: lassoSelection.tapeIds.contains(tape.id),
      );
    }

    // 7. Lasso selection bounding box
    if (lassoSelectionBounds != null && lassoSelection.isNotEmpty) {
      _paintSelectionBounds(canvas, lassoSelectionBounds!);
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
      Paint()..filterQuality = FilterQuality.medium,
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

  static void paintHighlighterStroke(
    Canvas canvas,
    Stroke stroke, {
    required bool isDarkPaper,
    required bool isSelected,
  }) {
    if (stroke.points.isEmpty) return;

    final baseColor = Color(stroke.colorValue);
    final paint = Paint()
      ..color = baseColor.withAlpha(isDarkPaper ? 95 : 108)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round
      ..blendMode = isDarkPaper ? BlendMode.srcOver : BlendMode.multiply
      ..isAntiAlias = true;

    final path = StrokeEngine.buildCenterlinePath(stroke.points);
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
  }) {
    if (stroke.points.isEmpty) return;

    final color = Color(stroke.colorValue);

    // Recognized geometric shapes render with crisp uniform stroke width
    if (stroke.shapeType != ShapeType.none) {
      final path = StrokeEngine.buildCenterlinePath(stroke.points);
      if (isSelected) {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF3B82F6).withAlpha(75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.width + 6.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
      return;
    }

    // Variable-width ink ribbon for fountain, ballpoint, brush, and pencil
    final ribbonPath = StrokeEngine.buildVariableWidthPath(stroke);

    if (isSelected) {
      canvas.drawPath(
        ribbonPath,
        Paint()
          ..color = const Color(0xFF3B82F6).withAlpha(70)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.0
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final bool isPencil = stroke.toolType == ToolType.pencil;
    final fillPaint = Paint()
      ..color = isPencil ? color.withAlpha(195) : color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    if (isPencil) {
      fillPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.45);
    }
    canvas.drawPath(ribbonPath, fillPaint);
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
      // Covered state: solid tape strip with diagonal hatch texture
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(rect, Paint()..color = baseColor.withAlpha(238));
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
        oldDelegate.lassoSelectionBounds != lassoSelectionBounds;
  }
}

/// Layer 2 (144Hz Ultra-Low-Latency Overlay): Repaints directly from
/// [ValueListenable]s without rebuilding the Flutter widget tree!
/// Draws the live in-progress stroke, M-Pencil 3 hover nib ring, eraser cursor,
/// active lasso marquee, and active study-tape drag preview.
class ActiveStrokePainter extends CustomPainter {
  final ValueListenable<Stroke?> activeStroke;
  final ValueListenable<Offset?> hoverPosition;
  final ValueListenable<Offset?> eraserCursor;
  final ValueListenable<List<Offset>> lassoPath;
  final ValueListenable<Rect?> tapeDraftRect;
  final bool isDarkPaper;
  final double hoverRadius;
  final Color hoverColor;
  final double eraserRadius;
  final Color tapeColor;

  ActiveStrokePainter({
    required this.activeStroke,
    required this.hoverPosition,
    required this.eraserCursor,
    required this.lassoPath,
    required this.tapeDraftRect,
    required this.isDarkPaper,
    this.hoverRadius = 3.0,
    this.hoverColor = const Color(0xFF3B82F6),
    this.eraserRadius = 18.0,
    this.tapeColor = const Color(0xFF6366F1),
  }) : super(
          repaint: Listenable.merge([
            activeStroke,
            hoverPosition,
            eraserCursor,
            lassoPath,
            tapeDraftRect,
          ]),
        );

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Live in-progress stroke
    final stroke = activeStroke.value;
    if (stroke != null) {
      if (stroke.toolType == ToolType.highlighter) {
        CanvasPainter.paintHighlighterStroke(
          canvas,
          stroke,
          isDarkPaper: isDarkPaper,
          isSelected: false,
        );
      } else {
        CanvasPainter.paintInkStroke(canvas, stroke, isSelected: false);
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

    // 4. Eraser cursor circle
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

    // 5. M-Pencil 3 hover cursor ring
    final hPos = hoverPosition.value;
    if (hPos != null && ePos == null) {
      final r = math.max(3.5, hoverRadius);
      canvas.drawCircle(
        hPos,
        r,
        Paint()
          ..color = hoverColor.withAlpha(175)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      canvas.drawCircle(
        hPos,
        1.5,
        Paint()..color = hoverColor.withAlpha(220),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ActiveStrokePainter oldDelegate) {
    return oldDelegate.isDarkPaper != isDarkPaper ||
        oldDelegate.hoverRadius != hoverRadius ||
        oldDelegate.hoverColor != hoverColor ||
        oldDelegate.eraserRadius != eraserRadius;
  }
}
