import 'dart:math' as math;
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
    final palette = PaperPalette.of(paperColor);

    // Fill paper background
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);

    if (isInfiniteWhiteboard) {
      _paintInfiniteWhiteboard(canvas, size, palette);
      return;
    }

    switch (templateType) {
      case PaperTemplateType.blank:
        break;
      case PaperTemplateType.ruled:
        _paintRuled(canvas, size, palette);
        break;
      case PaperTemplateType.grid:
        _paintGrid(canvas, size, palette);
        break;
      case PaperTemplateType.dotted:
        _paintDotted(canvas, size, palette);
        break;
      case PaperTemplateType.cornell:
        _paintCornell(canvas, size, palette);
        break;
      case PaperTemplateType.hexagonal:
        _paintHexagonal(canvas, size, palette);
        break;
      case PaperTemplateType.sageRibbon:
        _paintSageRibbon(canvas, size, palette);
        break;
      case PaperTemplateType.pastelGrid:
        _paintPastelGrid(canvas, size, palette);
        break;
      case PaperTemplateType.vintageCream:
        _paintVintageCream(canvas, size, palette);
        break;
      case PaperTemplateType.twoColumnStudy:
        _paintTwoColumnStudy(canvas, size, palette);
        break;
    }
  }

  /// Seamless full-bleed tiled pattern for Infinite Whiteboard pages (6000×6000).
  void _paintInfiniteWhiteboard(
    Canvas canvas,
    Size size,
    PaperPalette palette,
  ) {
    switch (templateType) {
      case PaperTemplateType.blank:
        break;
      case PaperTemplateType.grid:
      case PaperTemplateType.pastelGrid:
        const double step = 32.0;
        final minorPaint = Paint()
          ..color = palette.line
          ..strokeWidth = 0.85;
        final majorPaint = Paint()
          ..color = palette.majorLine
          ..strokeWidth = 1.2;
        int col = 0;
        for (double x = 0; x <= size.width; x += step) {
          canvas.drawLine(
            Offset(x, 0),
            Offset(x, size.height),
            col % 5 == 0 ? majorPaint : minorPaint,
          );
          col++;
        }
        int row = 0;
        for (double y = 0; y <= size.height; y += step) {
          canvas.drawLine(
            Offset(0, y),
            Offset(size.width, y),
            row % 5 == 0 ? majorPaint : minorPaint,
          );
          row++;
        }
        break;
      case PaperTemplateType.hexagonal:
        final hexPaint = Paint()
          ..color = palette.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        const double radius = 26.0;
        final double hexWidth = math.sqrt(3) * radius;
        const double verticalStep = radius * 1.5;
        final Path path = Path();
        int row = 0;
        for (double cy = 0; cy <= size.height + radius; cy += verticalStep) {
          final double xOffset = row.isOdd ? hexWidth * 0.5 : 0.0;
          for (double cx = xOffset; cx <= size.width + hexWidth; cx += hexWidth) {
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
        break;
      case PaperTemplateType.ruled:
      case PaperTemplateType.sageRibbon:
      case PaperTemplateType.vintageCream:
      case PaperTemplateType.cornell:
      case PaperTemplateType.twoColumnStudy:
        final linePaint = Paint()
          ..color = palette.line
          ..strokeWidth = 1.0;
        for (double y = 36.0; y < size.height; y += 36.0) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
        break;
      case PaperTemplateType.dotted:
        final dotPaint = Paint()
          ..color = palette.majorLine
          ..style = PaintingStyle.fill;
        const double step = 32.0;
        for (double y = step; y < size.height; y += step) {
          for (double x = step; x < size.width; x += step) {
            canvas.drawCircle(Offset(x, y), 1.45, dotPaint);
          }
        }
        break;
    }

    // Subtle center origin crosshair at (3000, 3000)
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final originPaint = Paint()
      ..color = palette.majorLine.withAlpha(180)
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(cx - 14, cy), Offset(cx + 14, cy), originPaint);
    canvas.drawLine(Offset(cx, cy - 14), Offset(cx, cy + 14), originPaint);
  }

  /// Huawei Notes signature sage-green header/footer paper with pastel peach
  /// swallowtail bookmark ribbon at top-left and crisp ruled lines.
  void _paintSageRibbon(Canvas canvas, Size size, PaperPalette palette) {
    final bool isDark = paperColor == PaperColorType.dark;
    final Color sageFill =
        isDark ? const Color(0xFF334034) : const Color(0xFFAEBDA7);
    final Color sageBorder =
        isDark ? const Color(0xFF566B58) : const Color(0xFF6E7F68);
    final Color ribbonFill =
        isDark ? const Color(0xFFC89B82) : const Color(0xFFFBD7C1);
    final Color ribbonStroke =
        isDark ? const Color(0xFF9C725B) : const Color(0xFFE3B79E);
    final Color ruledColor =
        isDark ? const Color(0xFF303532) : const Color(0xFFDFE4DF);

    final double headerH = isLandscape ? 62.0 : 72.0;
    final double footerH = isLandscape ? 44.0 : 52.0;

    // Top sage header band
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, headerH),
      Paint()..color = sageFill,
    );
    canvas.drawLine(
      Offset(0, headerH),
      Offset(size.width, headerH),
      Paint()
        ..color = sageBorder
        ..strokeWidth = 1.4,
    );

    // Bottom sage footer band
    final double footerTop = size.height - footerH;
    canvas.drawRect(
      Rect.fromLTWH(0, footerTop, size.width, footerH),
      Paint()..color = sageFill,
    );
    canvas.drawLine(
      Offset(0, footerTop),
      Offset(size.width, footerTop),
      Paint()
        ..color = sageBorder
        ..strokeWidth = 1.4,
    );

    // Pastel peach bookmark ribbon with swallowtail V-notch at top-left
    const double ribX = 44.0;
    const double ribW = 30.0;
    final double ribH = headerH + 22.0;
    final ribbonPath = Path()
      ..moveTo(ribX, 0)
      ..lineTo(ribX + ribW, 0)
      ..lineTo(ribX + ribW, ribH)
      ..lineTo(ribX + ribW * 0.5, ribH - 12.0)
      ..lineTo(ribX, ribH)
      ..close();
    canvas.drawPath(ribbonPath, Paint()..color = ribbonFill);
    canvas.drawPath(
      ribbonPath,
      Paint()
        ..color = ribbonStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Crisp horizontal ruled lines between header and footer
    final linePaint = Paint()
      ..color = ruledColor
      ..strokeWidth = 1.05;
    const double spacing = 32.0;
    const double sidePad = 36.0;
    for (double y = headerH + 40.0; y < footerTop - 16.0; y += spacing) {
      canvas.drawLine(
        Offset(sidePad, y),
        Offset(size.width - sidePad, y),
        linePaint,
      );
    }
  }

  /// Soft sky-lavender header banner with Ngày / Chủ đề fields + delicate 5mm grid.
  void _paintPastelGrid(Canvas canvas, Size size, PaperPalette palette) {
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
        ..strokeWidth = 1.2,
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
          ..strokeWidth = col % 5 == 0 ? 1.05 : 0.7,
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
          ..strokeWidth = row % 5 == 0 ? 1.05 : 0.7,
      );
      row++;
    }
  }

  /// Warm vintage parchment with refined double-line border frame, Date/No.
  /// header, and sepia ruled lines.
  void _paintVintageCream(Canvas canvas, Size size, PaperPalette palette) {
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
      ..strokeWidth = 1.4;
    final innerPaint = Paint()
      ..color = frameColor.withAlpha(165)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

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
      ..strokeWidth = 1.0;
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
  void _paintTwoColumnStudy(Canvas canvas, Size size, PaperPalette palette) {
    const double pad = 32.0;
    const double headerBottom = 92.0;
    final double midX = size.width * 0.5;

    final majorPaint = Paint()
      ..color = palette.majorLine
      ..strokeWidth = 1.3;
    final linePaint = Paint()
      ..color = palette.line
      ..strokeWidth = 0.95;

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

  void _paintRuled(Canvas canvas, Size size, PaperPalette palette) {
    final linePaint = Paint()
      ..color = palette.line
      ..strokeWidth = 1.0;
    final marginPaint = Paint()
      ..color = palette.marginLine
      ..strokeWidth = 1.4;

    const double topHeader = 88.0;
    const double lineSpacing = 32.0;
    final double leftMargin = isLandscape ? 92.0 : 76.0;

    canvas.drawLine(
      Offset(0, topHeader - 4),
      Offset(size.width, topHeader - 4),
      Paint()
        ..color = palette.majorLine
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      Offset(0, topHeader),
      Offset(size.width, topHeader),
      Paint()
        ..color = palette.majorLine
        ..strokeWidth = 1.2,
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

  void _paintGrid(Canvas canvas, Size size, PaperPalette palette) {
    final minorPaint = Paint()
      ..color = palette.line
      ..strokeWidth = 0.85;
    final majorPaint = Paint()
      ..color = palette.majorLine
      ..strokeWidth = 1.25;

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

  void _paintDotted(Canvas canvas, Size size, PaperPalette palette) {
    final dotPaint = Paint()
      ..color = palette.majorLine
      ..style = PaintingStyle.fill;

    const double step = 24.0;
    const double margin = 28.0;
    const double radius = 1.35;

    for (double y = margin; y <= size.height - margin; y += step) {
      for (double x = margin; x <= size.width - margin; x += step) {
        canvas.drawCircle(Offset(x, y), radius, dotPaint);
      }
    }
  }

  void _paintCornell(Canvas canvas, Size size, PaperPalette palette) {
    final majorPaint = Paint()
      ..color = palette.majorLine
      ..strokeWidth = 1.5;
    final linePaint = Paint()
      ..color = palette.line
      ..strokeWidth = 0.9;
    final marginPaint = Paint()
      ..color = palette.marginLine
      ..strokeWidth = 1.5;

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

  void _paintHexagonal(Canvas canvas, Size size, PaperPalette palette) {
    final hexPaint = Paint()
      ..color = palette.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05;

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
        ..strokeWidth = 1.0,
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
