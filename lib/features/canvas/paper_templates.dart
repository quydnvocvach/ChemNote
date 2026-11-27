import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/models/drawing_elements.dart';

/// Standard logical page dimensions (A4 at 96 DPI, matching PdfExportService)
/// and Infinite Whiteboard virtual canvas dimensions (6000 × 6000).
class PaperMetrics {
  static const double portraitWidth = 794.0;
  static const double portraitHeight = 1123.0;
  static const Size whiteboardSize = Size(6000.0, 6000.0);
  static const Offset whiteboardCenter = Offset(3000.0, 3000.0);

  static Size pageSize({
    required bool isLandscape,
    bool isInfiniteWhiteboard = false,
  }) {
    if (isInfiniteWhiteboard) return whiteboardSize;
    return isLandscape
        ? const Size(portraitHeight, portraitWidth)
        : const Size(portraitWidth, portraitHeight);
  }
}

/// Color palette derived from [PaperColorType].
class PaperPalette {
  final Color background;
  final Color line;
  final Color majorLine;
  final Color marginLine;
  final Color labelText;
  final Color headerFill;

  const PaperPalette({
    required this.background,
    required this.line,
    required this.majorLine,
    required this.marginLine,
    required this.labelText,
    required this.headerFill,
  });

  static PaperPalette of(PaperColorType colorType) {
    switch (colorType) {
      case PaperColorType.white:
        return const PaperPalette(
          background: Color(0xFFFFFFFF),
          line: Color(0xFFDCE3EC),
          majorLine: Color(0xFFB4C3D6),
          marginLine: Color(0xFFE5989B),
          labelText: Color(0xFF64748B),
          headerFill: Color(0xFFF4F7FB),
        );
      case PaperColorType.cream:
        return const PaperPalette(
          background: Color(0xFFFAF6EC),
          line: Color(0xFFDFD7C5),
          majorLine: Color(0xFFC5B99E),
          marginLine: Color(0xFFD88C8C),
          labelText: Color(0xFF786E5E),
          headerFill: Color(0xFFF2EBDC),
        );
      case PaperColorType.dark:
        return const PaperPalette(
          background: Color(0xFF1E1E24),
          line: Color(0xFF31313D),
          majorLine: Color(0xFF474759),
          marginLine: Color(0xFF8C4A56),
          labelText: Color(0xFF94A3B8),
          headerFill: Color(0xFF262630),
        );
    }
  }
}

/// Metadata helpers for Vietnamese UI pickers (10 curated templates).
class PaperTemplateInfo {
  /// Display order featuring aesthetic Huawei Notes / study templates first.
  static const List<PaperTemplateType> orderedTemplates = [
    PaperTemplateType.sageRibbon,
    PaperTemplateType.pastelGrid,
    PaperTemplateType.vintageCream,
    PaperTemplateType.twoColumnStudy,
    PaperTemplateType.hexagonal,
    PaperTemplateType.cornell,
    PaperTemplateType.ruled,
    PaperTemplateType.grid,
    PaperTemplateType.dotted,
    PaperTemplateType.blank,
  ];

  static String templateLabel(PaperTemplateType type) {
    switch (type) {
      case PaperTemplateType.sageRibbon:
        return 'Kẻ ngang ruy-băng xanh';
      case PaperTemplateType.pastelGrid:
        return 'Ô ly tiêu đề pastel';
      case PaperTemplateType.vintageCream:
        return 'Giấy cổ điển viền khung';
      case PaperTemplateType.twoColumnStudy:
        return 'Chia 2 cột bài tập';
      case PaperTemplateType.hexagonal:
        return 'Lưới lục giác hữu cơ';
      case PaperTemplateType.cornell:
        return 'Giấy Cornell';
      case PaperTemplateType.ruled:
        return 'Kẻ ngang cổ điển';
      case PaperTemplateType.grid:
        return 'Ô ly vuông';
      case PaperTemplateType.dotted:
        return 'Chấm dot tối giản';
      case PaperTemplateType.blank:
        return 'Giấy trắng trơn';
    }
  }

  static String colorLabel(PaperColorType type) {
    switch (type) {
      case PaperColorType.white:
        return 'Trắng';
      case PaperColorType.cream:
        return 'Kem dịu mắt';
      case PaperColorType.dark:
        return 'Tối';
    }
  }

  static Color previewColor(PaperColorType type) =>
      PaperPalette.of(type).background;
}

/// CustomPainter rendering all 10 curated [PaperTemplateType] layouts with
/// [PaperColorType] styling and portrait/landscape support.
class PaperTemplatePainter extends CustomPainter {
  final PaperTemplateType templateType;
  final PaperColorType paperColor;
  final bool isLandscape;
  final bool isInfiniteWhiteboard;

  const PaperTemplatePainter({
    required this.templateType,
    required this.paperColor,
    this.isLandscape = false,
    this.isInfiniteWhiteboard = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final palette = PaperPalette.of(paperColor);

    if (isInfiniteWhiteboard) {
      if (size.width < 1200.0) {
        const Size thumbCanonical = Size(794.0, 1123.0);
        final double sx = size.width / thumbCanonical.width;
        final double sy = size.height / thumbCanonical.height;
        final double lineBoost =
            sx < 0.45 ? (0.45 / sx).clamp(1.0, 1.9) : 1.0;
        canvas.save();
        canvas.clipRect(Offset.zero & size);
        canvas.scale(sx, sy);
        canvas.drawRect(
          Offset.zero & thumbCanonical,
          Paint()..color = palette.background,
        );
        _paintInfiniteWhiteboard(
          canvas,
          thumbCanonical,
          palette,
          lineBoost: lineBoost,
        );
        canvas.restore();
        return;
      }
      canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);
      _paintInfiniteWhiteboard(canvas, size, palette);
      return;
    }

    final Size canonical = PaperMetrics.pageSize(isLandscape: isLandscape);
    final bool needsScale = (size.width - canonical.width).abs() > 1.0 ||
        (size.height - canonical.height).abs() > 1.0;
    final double sx = size.width / canonical.width;
    final double sy = size.height / canonical.height;
    final double lineBoost =
        (needsScale && sx < 0.45) ? (0.45 / sx).clamp(1.0, 1.9) : 1.0;
    final Size paintSize = needsScale ? canonical : size;

    if (needsScale) {
      canvas.save();
      canvas.clipRect(Offset.zero & size);
      canvas.scale(sx, sy);
    }

    // Fill paper background
    canvas.drawRect(
      Offset.zero & paintSize,
      Paint()..color = palette.background,
    );

    switch (templateType) {
      case PaperTemplateType.blank:
        break;
      case PaperTemplateType.ruled:
        _paintRuled(canvas, paintSize, palette, lineBoost: lineBoost);
        break;
      case PaperTemplateType.grid:
        _paintGrid(canvas, paintSize, palette, lineBoost: lineBoost);
        break;
      case PaperTemplateType.dotted:
        _paintDotted(canvas, paintSize, palette, lineBoost: lineBoost);
        break;
      case PaperTemplateType.cornell:
        _paintCornell(canvas, paintSize, palette, lineBoost: lineBoost);
        break;
      case PaperTemplateType.hexagonal:
        _paintHexagonal(canvas, paintSize, palette, lineBoost: lineBoost);
        break;
      case PaperTemplateType.sageRibbon:
        _paintSageRibbon(canvas, paintSize, palette, lineBoost: lineBoost);
        break;
      case PaperTemplateType.pastelGrid:
        _paintPastelGrid(canvas, paintSize, palette, lineBoost: lineBoost);
        break;
      case PaperTemplateType.vintageCream:
        _paintVintageCream(canvas, paintSize, palette, lineBoost: lineBoost);
        break;
      case PaperTemplateType.twoColumnStudy:
        _paintTwoColumnStudy(canvas, paintSize, palette, lineBoost: lineBoost);
        break;
    }

    if (needsScale) {
      canvas.restore();
    }
  }

  /// Seamless full-bleed tiled pattern for Infinite Whiteboard pages (6000×6000).
  void _paintInfiniteWhiteboard(
    Canvas canvas,
    Size size,
    PaperPalette palette, {
    double lineBoost = 1.0,
  }) {
    final Rect clip = canvas.getLocalClipBounds();
    final bool hasSubClip = !clip.isEmpty &&
        clip.left.isFinite &&
        clip.top.isFinite &&
        clip.right.isFinite &&
        clip.bottom.isFinite &&
        (clip.width < size.width - 1.0 || clip.height < size.height - 1.0) &&
        clip.right > 0 &&
        clip.bottom > 0 &&
        clip.left < size.width &&
        clip.top < size.height;
    final double visLeft =
        hasSubClip ? clip.left.clamp(0.0, size.width).toDouble() : 0.0;
    final double visTop =
        hasSubClip ? clip.top.clamp(0.0, size.height).toDouble() : 0.0;
    final double visRight =
        hasSubClip ? clip.right.clamp(0.0, size.width).toDouble() : size.width;
    final double visBottom = hasSubClip
        ? clip.bottom.clamp(0.0, size.height).toDouble()
        : size.height;

    switch (templateType) {
      case PaperTemplateType.blank:
        break;
      case PaperTemplateType.grid:
      case PaperTemplateType.pastelGrid:
        const double step = 32.0;
        final minorPaint = Paint()
          ..color = palette.line
          ..strokeWidth = 0.85 * lineBoost;
        final majorPaint = Paint()
          ..color = palette.majorLine
          ..strokeWidth = 1.2 * lineBoost;
        final int startCol = math.max(0, (visLeft / step).floor());
        final int endCol = math.min(
          (size.width / step).floor(),
          (visRight / step).ceil(),
        );
        for (int col = startCol; col <= endCol; col++) {
          final double x = col * step;
          canvas.drawLine(
            Offset(x, visTop),
            Offset(x, visBottom),
            col % 5 == 0 ? majorPaint : minorPaint,
          );
        }
        final int startRow = math.max(0, (visTop / step).floor());
        final int endRow = math.min(
          (size.height / step).floor(),
          (visBottom / step).ceil(),
        );
        for (int row = startRow; row <= endRow; row++) {
          final double y = row * step;
          canvas.drawLine(
            Offset(visLeft, y),
            Offset(visRight, y),
            row % 5 == 0 ? majorPaint : minorPaint,
          );
        }
        break;
      case PaperTemplateType.hexagonal:
        final hexPaint = Paint()
          ..color = palette.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 * lineBoost;
        const double radius = 26.0;
        final double hexWidth = math.sqrt(3) * radius;
        const double verticalStep = radius * 1.5;
        final int startRow =
            math.max(0, ((visTop - radius) / verticalStep).floor());
        final int endRow = math.min(
          ((size.height + radius) / verticalStep).floor(),
          ((visBottom + radius) / verticalStep).ceil(),
        );
        final Path path = Path();
        for (int row = startRow; row <= endRow; row++) {
          final double cy = row * verticalStep;
          final double xOffset = row.isOdd ? hexWidth * 0.5 : 0.0;
          final int startCol = math.max(
            0,
            ((visLeft - xOffset - hexWidth) / hexWidth).floor(),
          );
          final int endCol = math.min(
            ((size.width + hexWidth - xOffset) / hexWidth).floor(),
            ((visRight - xOffset + hexWidth) / hexWidth).ceil(),
          );
          for (int col = startCol; col <= endCol; col++) {
            final double cx = xOffset + col * hexWidth;
            for (int i = 0; i < 6; i++) {
              final double angle = (math.pi / 180.0) * (60 * i - 30);
              final double vx = cx + radius * math.cos(angle);
              final double vy = cy + radius * math.sin(angle);
              if (i == 0) {
                path.moveTo(vx, vy);
              } else {
                path.lineTo(vx, vy);
              }
            }
            path.close();
          }
        }
        canvas.drawPath(path, hexPaint);
        break;
      case PaperTemplateType.ruled:
      case PaperTemplateType.sageRibbon:
      case PaperTemplateType.vintageCream:
      case PaperTemplateType.cornell:
      case PaperTemplateType.twoColumnStudy:
        final linePaint = Paint()
          ..color = palette.line
          ..strokeWidth = 1.0 * lineBoost;
        final int startLine = math.max(1, (visTop / 36.0).floor());
        final int endLine = math.min(
          ((size.height - 0.001) / 36.0).floor(),
          (visBottom / 36.0).ceil(),
        );
        for (int i = startLine; i <= endLine; i++) {
          final double y = i * 36.0;
          canvas.drawLine(Offset(visLeft, y), Offset(visRight, y), linePaint);
        }
        break;
      case PaperTemplateType.dotted:
        const double step = 32.0;
        final int minRow = math.max(1, (visTop / step).floor());
        final int maxRow = math.min(
          ((size.height - 0.001) / step).floor(),
          (visBottom / step).ceil(),
        );
        final int minCol = math.max(1, (visLeft / step).floor());
        final int maxCol = math.min(
          ((size.width - 0.001) / step).floor(),
          (visRight / step).ceil(),
        );
        if (maxRow >= minRow && maxCol >= minCol) {
          final int count = (maxRow - minRow + 1) * (maxCol - minCol + 1);
          final Float32List coords = Float32List(count * 2);
          int idx = 0;
          for (int r = minRow; r <= maxRow; r++) {
            final double y = r * step;
            for (int c = minCol; c <= maxCol; c++) {
              coords[idx++] = c * step;
              coords[idx++] = y;
            }
          }
          final dotPaint = Paint()
            ..color = palette.majorLine
            ..strokeWidth = 2.9 * lineBoost
            ..strokeCap = StrokeCap.round;
          canvas.drawRawPoints(ui.PointMode.points, coords, dotPaint);
        }
        break;
    }

    // Subtle center origin crosshair at (3000, 3000)
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final originPaint = Paint()
      ..color = palette.majorLine.withAlpha(180)
      ..strokeWidth = 1.4 * lineBoost;
    canvas.drawLine(Offset(cx - 14, cy), Offset(cx + 14, cy), originPaint);
    canvas.drawLine(Offset(cx, cy - 14), Offset(cx, cy + 14), originPaint);
  }

  /// Exact 1:1 sage-green header/footer paper with pastel peach swallowtail
  /// bookmark ribbon (solid fill, no stroke) and 26 full-width ruled lines.
  void _paintSageRibbon(
    Canvas canvas,
    Size size,
    PaperPalette palette, {
    double lineBoost = 1.0,
  }) {
    final bool isDark = paperColor == PaperColorType.dark;
    final Color sageFill =
        isDark ? const Color(0xFF334034) : const Color(0xFFB4C3AC);
    final Color sageDivider =
        isDark ? const Color(0xFF566B58) : const Color(0xFF798D6E);
    final Color ribbonFill =
        isDark ? const Color(0xFFC89B82) : const Color(0xFFFFD8BE);
    final Color ruledColor =
        isDark ? const Color(0xFF303532) : const Color(0xFFD2D9CF);

    final double headerH = size.height * (163.0 / 2263.0);
    final double topDividerH = size.height * (6.2 / 2263.0);
    final double footerH = size.height * (100.0 / 2263.0);
    final double bottomDividerH = size.height * (4.7 / 2263.0);
    final double footerTop = size.height - footerH;
    final double bottomDividerTop = footerTop - bottomDividerH;

    // 1. Top sage header band & bottom sage footer band
    final bandPaint = Paint()..color = sageFill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, headerH), bandPaint);
    canvas.drawRect(
      Rect.fromLTWH(0, footerTop, size.width, footerH),
      bandPaint,
    );

    // 2. Top & bottom divider bars
    final dividerPaint = Paint()..color = sageDivider;
    canvas.drawRect(
      Rect.fromLTWH(0, headerH, size.width, topDividerH),
      dividerPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, bottomDividerTop, size.width, bottomDividerH),
      dividerPaint,
    );

    // 3. Full-width edge-to-edge ruled horizontal lines
    final linePaint = Paint()
      ..color = ruledColor
      ..strokeWidth = size.height * (2.4 / 2263.0) * lineBoost;
    if (!isLandscape) {
      for (int i = 0; i < 26; i++) {
        final double y = size.height * ((242.5 + i * 75.04) / 2263.0);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
    } else {
      final double lineSpacing = size.width * (75.04 / 2263.0);
      for (double y = headerH + topDividerH + lineSpacing;
          y < bottomDividerTop - lineSpacing * 0.45;
          y += lineSpacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
    }

    // 4. Pastel peach swallowtail bookmark ribbon at top-left (solid fill, no stroke)
    final double ribLeft = size.width * (99.4 / 1600.0);
    final double ribRight = size.width * (204.3 / 1600.0);
    final double ribMidX = (ribLeft + ribRight) * 0.5;
    final double ribBottomY = isLandscape
        ? (headerH + topDividerH + size.height * 0.045)
        : (size.height * (236.0 / 2263.0));
    final double ribNotchY = isLandscape
        ? (headerH + topDividerH + size.height * 0.010)
        : (size.height * (181.0 / 2263.0));
    final ribbonPath = Path()
      ..moveTo(ribLeft, 0)
      ..lineTo(ribRight, 0)
      ..lineTo(ribRight, ribBottomY)
      ..lineTo(ribMidX, ribNotchY)
      ..lineTo(ribLeft, ribBottomY)
      ..close();
    canvas.drawPath(
      ribbonPath,
      Paint()
        ..color = ribbonFill
        ..isAntiAlias = true,
    );
  }

  /// Soft sky-lavender header banner with Ngày / Chủ đề fields + delicate 5mm grid.
  void _paintPastelGrid(
    Canvas canvas,
    Size size,
    PaperPalette palette, {
    double lineBoost = 1.0,
  }) {
    final bool isDark = paperColor == PaperColorType.dark;
    final Color bannerFill =
        isDark ? const Color(0xFF282D3E) : const Color(0xFFE3ECFA);
    final Color bannerLine =
        isDark ? const Color(0xFF475577) : const Color(0xFF9EB5D8);
    final Color gridMinor =
        isDark ? const Color(0xFF2B2E3A) : const Color(0xFFE5EAF2);
    final Color gridMajor =
        isDark ? const Color(0xFF393E4F) : const Color(0xFFC9D5E8);

    const double pad = 28.0;
    const double bannerH = 68.0;
    final Rect bannerRect = Rect.fromLTWH(pad, pad, size.width - pad * 2, bannerH);

    canvas.drawRRect(
      RRect.fromRectAndRadius(bannerRect, const Radius.circular(10)),
      Paint()..color = bannerFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bannerRect, const Radius.circular(10)),
      Paint()
        ..color = bannerLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * lineBoost,
    );

    _drawLabel(
      canvas,
      'CHỦ ĐỀ:',
      Offset(bannerRect.left + 16, bannerRect.top + 14),
      palette,
      fontSize: 10.5,
      bold: true,
    );
    _drawLabel(
      canvas,
      'NGÀY: ____ / ____ / ______',
      Offset(bannerRect.right - 180, bannerRect.top + 14),
      palette,
      fontSize: 10.5,
    );

    final double gridTop = bannerRect.bottom + 18.0;
    final double gridBottom = size.height - pad;
    const double step = 20.0;

    int col = 0;
    for (double x = pad; x <= size.width - pad; x += step) {
      canvas.drawLine(
        Offset(x, gridTop),
        Offset(x, gridBottom),
        Paint()
          ..color = col % 5 == 0 ? gridMajor : gridMinor
          ..strokeWidth = (col % 5 == 0 ? 1.05 : 0.7) * lineBoost,
      );
      col++;
    }
    int row = 0;
    for (double y = gridTop; y <= gridBottom; y += step) {
      canvas.drawLine(
        Offset(pad, y),
        Offset(size.width - pad, y),
        Paint()
          ..color = row % 5 == 0 ? gridMajor : gridMinor
          ..strokeWidth = (row % 5 == 0 ? 1.05 : 0.7) * lineBoost,
      );
      row++;
    }
  }

  /// Warm vintage parchment with refined double-line border frame, Date/No.
  /// header, and sepia ruled lines.
  void _paintVintageCream(
    Canvas canvas,
    Size size,
    PaperPalette palette, {
    double lineBoost = 1.0,
  }) {
    final bool isDark = paperColor == PaperColorType.dark;
    if (!isDark) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFFAF4E6),
      );
    }
    final Color frameColor =
        isDark ? const Color(0xFF6B5E4E) : const Color(0xFFB7A489);
    final Color ruledColor =
        isDark ? const Color(0xFF3A352E) : const Color(0xFFE3D8C3);

    const double outerPad = 24.0;
    const double innerPad = 30.0;
    final framePaint = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * lineBoost;
    final innerPaint = Paint()
      ..color = frameColor.withAlpha(165)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 * lineBoost;

    canvas.drawRect(
      Rect.fromLTRB(
        outerPad,
        outerPad,
        size.width - outerPad,
        size.height - outerPad,
      ),
      framePaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        innerPad,
        innerPad,
        size.width - innerPad,
        size.height - innerPad,
      ),
      innerPaint,
    );

    const double headerBottom = 94.0;
    canvas.drawLine(
      Offset(innerPad + 10, headerBottom),
      Offset(size.width - innerPad - 10, headerBottom),
      framePaint,
    );
    _drawLabel(
      canvas,
      'TIÊU ĐỀ:',
      Offset(innerPad + 16, innerPad + 16),
      palette,
      fontSize: 11,
      bold: true,
    );
    _drawLabel(
      canvas,
      'NGÀY: ___/___/_____   SỐ: ____',
      Offset(size.width - innerPad - 210, innerPad + 16),
      palette,
      fontSize: 10.5,
    );

    final linePaint = Paint()
      ..color = ruledColor
      ..strokeWidth = 1.0 * lineBoost;
    for (double y = headerBottom + 32.0; y < size.height - innerPad - 16; y += 32.0) {
      canvas.drawLine(
        Offset(innerPad + 14, y),
        Offset(size.width - innerPad - 14, y),
        linePaint,
      );
    }
  }

  /// Side-by-side 2-column study sheet (Tóm tắt / Lời giải) with dashed
  /// vertical center divider and clean ruled lines.
  void _paintTwoColumnStudy(
    Canvas canvas,
    Size size,
    PaperPalette palette, {
    double lineBoost = 1.0,
  }) {
    const double pad = 32.0;
    const double headerBottom = 92.0;
    final double midX = size.width * 0.5;

    final majorPaint = Paint()
      ..color = palette.majorLine
      ..strokeWidth = 1.3 * lineBoost;
    final linePaint = Paint()
      ..color = palette.line
      ..strokeWidth = 0.95 * lineBoost;

    // Header band
    canvas.drawRect(
      Rect.fromLTRB(pad, pad, size.width - pad, headerBottom),
      Paint()..color = palette.headerFill,
    );
    canvas.drawRect(
      Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad),
      majorPaint..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      Offset(pad, headerBottom),
      Offset(size.width - pad, headerBottom),
      majorPaint,
    );

    _drawLabel(
      canvas,
      'BÀI TẬP & TÓM TẮT',
      Offset(pad + 14, pad + 18),
      palette,
      fontSize: 11,
      bold: true,
    );
    _drawLabel(
      canvas,
      'LỜI GIẢI CHI TIẾT',
      Offset(midX + 14, pad + 18),
      palette,
      fontSize: 11,
      bold: true,
    );

    // Dashed vertical center divider
    for (double y = headerBottom + 6; y < size.height - pad - 6; y += 12) {
      canvas.drawLine(
        Offset(midX, y),
        Offset(midX, math.min(y + 6, size.height - pad - 6)),
        majorPaint,
      );
    }

    // Horizontal ruled lines across both columns
    for (double y = headerBottom + 32.0; y < size.height - pad - 10; y += 30.0) {
      canvas.drawLine(Offset(pad + 8, y), Offset(midX - 8, y), linePaint);
      canvas.drawLine(
        Offset(midX + 8, y),
        Offset(size.width - pad - 8, y),
        linePaint,
      );
    }
  }

  void _paintRuled(
    Canvas canvas,
    Size size,
    PaperPalette palette, {
    double lineBoost = 1.0,
  }) {
    final linePaint = Paint()
      ..color = palette.line
      ..strokeWidth = 1.0 * lineBoost;
    final marginPaint = Paint()
      ..color = palette.marginLine
      ..strokeWidth = 1.4 * lineBoost;

    const double topHeader = 88.0;
    const double lineSpacing = 32.0;
    final double leftMargin = isLandscape ? 92.0 : 76.0;

    canvas.drawLine(
      Offset(0, topHeader - 4),
      Offset(size.width, topHeader - 4),
      Paint()
        ..color = palette.majorLine
        ..strokeWidth = 1.2 * lineBoost,
    );
    canvas.drawLine(
      Offset(0, topHeader),
      Offset(size.width, topHeader),
      Paint()
        ..color = palette.majorLine
        ..strokeWidth = 1.2 * lineBoost,
    );

    for (double y = topHeader + lineSpacing;
        y < size.height - 28;
        y += lineSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    canvas.drawLine(
      Offset(leftMargin, 0),
      Offset(leftMargin, size.height),
      marginPaint,
    );
  }

  void _paintGrid(
    Canvas canvas,
    Size size,
    PaperPalette palette, {
    double lineBoost = 1.0,
  }) {
    final minorPaint = Paint()
      ..color = palette.line
      ..strokeWidth = 0.85 * lineBoost;
    final majorPaint = Paint()
      ..color = palette.majorLine
      ..strokeWidth = 1.25 * lineBoost;

    const double step = 24.0;
    const double margin = 24.0;

    int col = 0;
    for (double x = margin; x <= size.width - margin; x += step) {
      canvas.drawLine(
        Offset(x, margin),
        Offset(x, size.height - margin),
        col % 5 == 0 ? majorPaint : minorPaint,
      );
      col++;
    }

    int row = 0;
    for (double y = margin; y <= size.height - margin; y += step) {
      canvas.drawLine(
        Offset(margin, y),
        Offset(size.width - margin, y),
        row % 5 == 0 ? majorPaint : minorPaint,
      );
      row++;
    }
  }

  void _paintDotted(
    Canvas canvas,
    Size size,
    PaperPalette palette, {
    double lineBoost = 1.0,
  }) {
    const double step = 24.0;
    const double margin = 28.0;
    final double diameter = 2.7 * lineBoost;
    final int cols = size.width >= margin * 2
        ? ((size.width - margin * 2 + 1e-6) / step).floor() + 1
        : 0;
    final int rows = size.height >= margin * 2
        ? ((size.height - margin * 2 + 1e-6) / step).floor() + 1
        : 0;
    if (cols <= 0 || rows <= 0) return;

    final Float32List coords = Float32List(cols * rows * 2);
    int idx = 0;
    for (int r = 0; r < rows; r++) {
      final double y = margin + r * step;
      for (int c = 0; c < cols; c++) {
        coords[idx++] = margin + c * step;
        coords[idx++] = y;
      }
    }
    final dotPaint = Paint()
      ..color = palette.majorLine
      ..strokeWidth = diameter
      ..strokeCap = StrokeCap.round;
    canvas.drawRawPoints(ui.PointMode.points, coords, dotPaint);
  }

  void _paintCornell(
    Canvas canvas,
    Size size,
    PaperPalette palette, {
    double lineBoost = 1.0,
  }) {
    final majorPaint = Paint()
      ..color = palette.majorLine
      ..strokeWidth = 1.5 * lineBoost;
    final linePaint = Paint()
      ..color = palette.line
      ..strokeWidth = 0.9 * lineBoost;
    final marginPaint = Paint()
      ..color = palette.marginLine
      ..strokeWidth = 1.5 * lineBoost;

    const double pad = 32.0;
    final double headerBottom = isLandscape ? 92.0 : 108.0;
    final double summaryTop = size.height - (isLandscape ? 136.0 : 172.0);
    final double cueRight = pad + (size.width - pad * 2) * 0.28;

    canvas.drawRect(
      Rect.fromLTRB(pad, pad, size.width - pad, headerBottom),
      Paint()..color = palette.headerFill,
    );
    canvas.drawRect(
      Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad),
      majorPaint..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      Offset(pad, headerBottom),
      Offset(size.width - pad, headerBottom),
      majorPaint,
    );
    canvas.drawLine(
      Offset(pad, summaryTop),
      Offset(size.width - pad, summaryTop),
      majorPaint,
    );
    canvas.drawLine(
      Offset(cueRight, headerBottom),
      Offset(cueRight, summaryTop),
      marginPaint,
    );

    const double spacing = 30.0;
    for (double y = headerBottom + spacing; y < summaryTop - 6; y += spacing) {
      canvas.drawLine(
        Offset(cueRight, y),
        Offset(size.width - pad, y),
        linePaint,
      );
    }
    for (double y = summaryTop + 34.0;
        y < size.height - pad - 8;
        y += spacing) {
      canvas.drawLine(Offset(pad, y), Offset(size.width - pad, y), linePaint);
    }

    _drawLabel(canvas, 'CHỦ ĐỀ / BÀI HỌC', Offset(pad + 12, pad + 10), palette);
    _drawLabel(
      canvas,
      'NGÀY: ____/____/______',
      Offset(size.width - pad - 170, pad + 10),
      palette,
    );
    _drawLabel(
      canvas,
      'TỪ KHÓA / CÂU HỎI',
      Offset(pad + 10, headerBottom + 8),
      palette,
    );
    _drawLabel(
      canvas,
      'GHI CHÚ CHI TIẾT',
      Offset(cueRight + 12, headerBottom + 8),
      palette,
    );
    _drawLabel(
      canvas,
      'TÓM TẮT BÀI HỌC',
      Offset(pad + 10, summaryTop + 8),
      palette,
    );
  }

  void _paintHexagonal(
    Canvas canvas,
    Size size,
    PaperPalette palette, {
    double lineBoost = 1.0,
  }) {
    final hexPaint = Paint()
      ..color = palette.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05 * lineBoost;

    const double radius = 22.0;
    final double hexWidth = math.sqrt(3) * radius;
    const double verticalStep = radius * 1.5;
    const double margin = 24.0;

    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(margin, margin, size.width - margin, size.height - margin),
    );

    final Path path = Path();
    int row = 0;
    for (double cy = margin + radius;
        cy <= size.height - margin + radius;
        cy += verticalStep) {
      final double xOffset = (row.isOdd) ? hexWidth / 2 : 0.0;
      for (double cx = margin + xOffset;
          cx <= size.width - margin + hexWidth;
          cx += hexWidth) {
        for (int i = 0; i < 6; i++) {
          final double angle = (math.pi / 180.0) * (60 * i - 30);
          final double vx = cx + radius * math.cos(angle);
          final double vy = cy + radius * math.sin(angle);
          if (i == 0) {
            path.moveTo(vx, vy);
          } else {
            path.lineTo(vx, vy);
          }
        }
        path.close();
      }
      row++;
    }

    canvas.drawPath(path, hexPaint);
    canvas.restore();
    canvas.drawRect(
      Rect.fromLTRB(margin, margin, size.width - margin, size.height - margin),
      Paint()
        ..color = palette.majorLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * lineBoost,
    );
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset offset,
    PaperPalette palette, {
    double fontSize = 10.0,
    bool bold = false,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: palette.labelText,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant PaperTemplatePainter oldDelegate) {
    return oldDelegate.templateType != templateType ||
        oldDelegate.paperColor != paperColor ||
        oldDelegate.isLandscape != isLandscape ||
        oldDelegate.isInfiniteWhiteboard != isInfiniteWhiteboard;
  }
}
