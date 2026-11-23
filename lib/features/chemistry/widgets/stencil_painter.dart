import 'dart:math' as math;
import 'package:flutter/material.dart';

/// CustomPainter vẽ vector sắc nét cho các khuôn hóa học & dụng cụ thí nghiệm.
///
/// Các module khác (như `canvas_painter.dart` hoặc `pdf_export_service.dart`)
/// có thể gọi trực tiếp [StencilPainter.paintStencil] để vẽ khuôn lên bất kỳ [Canvas] nào.
class StencilPainter extends CustomPainter {
  final String stencilId;
  final Color color;
  final double strokeWidth;

  const StencilPainter({
    required this.stencilId,
    this.color = const Color(0xFF1E293B),
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    paintStencil(canvas, size, stencilId, color, strokeWidth);
  }

  @override
  bool shouldRepaint(covariant StencilPainter oldDelegate) {
    return oldDelegate.stencilId != stencilId ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }

  /// Hàm tĩnh dùng chung để vẽ vector một khuôn hóa học theo [stencilId]
  /// vừa khít trong khung [size] với màu [color] và độ dày nét [strokeWidth].
  static void paintStencil(
    Canvas canvas,
    Size size,
    String stencilId,
    Color color,
    double strokeWidth,
  ) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final pad = strokeWidth * 1.2 + math.min(size.width, size.height) * 0.06;
    final rect = Rect.fromLTWH(
      pad,
      pad,
      math.max(1, size.width - pad * 2),
      math.max(1, size.height - pad * 2),
    );

    switch (stencilId) {
      case 'benzene_ring':
        _paintBenzeneRing(canvas, rect, paint);
        break;
      case 'benzene_kekule':
        _paintBenzeneKekule(canvas, rect, paint);
        break;
      case 'cyclohexane_chair':
        _paintCyclohexaneChair(canvas, rect, paint);
        break;
      case 'cyclohexane_boat':
        _paintCyclohexaneBoat(canvas, rect, paint);
        break;
      case 'cyclopentane':
        _paintRegularPolygon(canvas, rect, paint, 5, -math.pi / 2);
        break;
      case 'cyclobutane':
        _paintRegularPolygon(canvas, rect, paint, 4, -math.pi / 4);
        break;
      case 'wedge_bond':
        _paintWedgeBond(canvas, rect, fillPaint);
        break;
      case 'dash_bond':
        _paintDashBond(canvas, rect, paint);
        break;
      case 'arrow_reaction':
        _paintArrowReaction(canvas, rect, paint);
        break;
      case 'arrow_equilibrium':
        _paintArrowEquilibrium(canvas, rect, paint);
        break;
      case 'arrow_resonance':
        _paintArrowResonance(canvas, rect, paint);
        break;
      case 'arrow_curved':
        _paintArrowCurved(canvas, rect, paint);
        break;
      case 'erlenmeyer_flask':
        _paintErlenmeyerFlask(canvas, rect, paint);
        break;
      case 'beaker':
        _paintBeaker(canvas, rect, paint);
        break;
      case 'round_bottom_flask':
        _paintRoundBottomFlask(canvas, rect, paint);
        break;
      case 'test_tube':
        _paintTestTube(canvas, rect, paint);
        break;
      case 'burette':
        _paintBurette(canvas, rect, paint);
        break;
      case 'pipette':
        _paintPipette(canvas, rect, paint);
        break;
      case 'condenser':
        _paintCondenser(canvas, rect, paint);
        break;
      case 'bunsen_burner':
        _paintBunsenBurner(canvas, rect, paint);
        break;
      case 'funnel':
        _paintFunnel(canvas, rect, paint);
        break;
      default:
        // Fallback: vẽ vòng lục giác chuẩn
        _paintRegularPolygon(canvas, rect, paint, 6, -math.pi / 2);
        break;
    }
  }

  static List<Offset> _polygonVertices(
    Rect rect,
    int sides,
    double startAngle,
  ) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final r = math.min(rect.width, rect.height) * 0.48;
    return List<Offset>.generate(sides, (i) {
      final angle = startAngle + (2 * math.pi * i) / sides;
      return Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
    });
  }

  static void _paintRegularPolygon(
    Canvas canvas,
    Rect rect,
    Paint paint,
    int sides,
    double startAngle,
  ) {
    final verts = _polygonVertices(rect, sides, startAngle);
    final path = Path()..moveTo(verts[0].dx, verts[0].dy);
    for (int i = 1; i < verts.length; i++) {
      path.lineTo(verts[i].dx, verts[i].dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  static void _paintBenzeneRing(Canvas canvas, Rect rect, Paint paint) {
    _paintRegularPolygon(canvas, rect, paint, 6, -math.pi / 2);
    final r = math.min(rect.width, rect.height) * 0.48;
    canvas.drawCircle(rect.center, r * 0.62, paint);
  }

  static void _paintBenzeneKekule(Canvas canvas, Rect rect, Paint paint) {
    final verts = _polygonVertices(rect, 6, -math.pi / 2);
    final path = Path()..moveTo(verts[0].dx, verts[0].dy);
    for (int i = 1; i < 6; i++) {
      path.lineTo(verts[i].dx, verts[i].dy);
    }
    path.close();
    canvas.drawPath(path, paint);

    // 3 liên kết đôi xen kẽ bên trong vòng
    final center = rect.center;
    for (final idx in [0, 2, 4]) {
      final a = verts[idx];
      final b = verts[(idx + 1) % 6];
      final insetA = Offset.lerp(a, center, 0.2)!;
      final insetB = Offset.lerp(b, center, 0.2)!;
      final p1 = Offset.lerp(insetA, insetB, 0.1)!;
      final p2 = Offset.lerp(insetA, insetB, 0.9)!;
      canvas.drawLine(p1, p2, paint);
    }
  }

  static void _paintCyclohexaneChair(Canvas canvas, Rect rect, Paint paint) {
    Offset pt(double fx, double fy) =>
        Offset(rect.left + rect.width * fx, rect.top + rect.height * fy);

    final path = Path()
      ..moveTo(pt(0.05, 0.62).dx, pt(0.05, 0.62).dy)
      ..lineTo(pt(0.32, 0.26).dx, pt(0.32, 0.26).dy)
      ..lineTo(pt(0.68, 0.42).dx, pt(0.68, 0.42).dy)
      ..lineTo(pt(0.95, 0.32).dx, pt(0.95, 0.32).dy)
      ..lineTo(pt(0.68, 0.74).dx, pt(0.68, 0.74).dy)
      ..lineTo(pt(0.32, 0.58).dx, pt(0.32, 0.58).dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void _paintCyclohexaneBoat(Canvas canvas, Rect rect, Paint paint) {
    Offset pt(double fx, double fy) =>
        Offset(rect.left + rect.width * fx, rect.top + rect.height * fy);

    final path = Path()
      ..moveTo(pt(0.06, 0.28).dx, pt(0.06, 0.28).dy)
      ..lineTo(pt(0.30, 0.74).dx, pt(0.30, 0.74).dy)
      ..lineTo(pt(0.70, 0.74).dx, pt(0.70, 0.74).dy)
      ..lineTo(pt(0.94, 0.28).dx, pt(0.94, 0.28).dy)
      ..lineTo(pt(0.68, 0.50).dx, pt(0.68, 0.50).dy)
      ..lineTo(pt(0.32, 0.50).dx, pt(0.32, 0.50).dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void _paintWedgeBond(Canvas canvas, Rect rect, Paint fillPaint) {
    final cy = rect.center.dy;
    final halfH = rect.height * 0.24;
    final path = Path()
      ..moveTo(rect.left, cy)
      ..lineTo(rect.right, cy - halfH)
      ..lineTo(rect.right, cy + halfH)
      ..close();
    canvas.drawPath(path, fillPaint);
  }

  static void _paintDashBond(Canvas canvas, Rect rect, Paint paint) {
    final cy = rect.center.dy;
    final maxHalfH = rect.height * 0.24;
    const steps = 6;
    for (int i = 0; i < steps; i++) {
      final t = (i + 0.5) / steps;
      final x = rect.left + rect.width * t;
      final halfH = maxHalfH * t;
      canvas.drawLine(
        Offset(x, cy - halfH),
        Offset(x, cy + halfH),
        paint,
      );
    }
  }

  static void _paintArrowReaction(Canvas canvas, Rect rect, Paint paint) {
    final cy = rect.center.dy;
    final headLen = math.min(rect.width * 0.2, rect.height * 0.35);
    canvas.drawLine(Offset(rect.left, cy), Offset(rect.right, cy), paint);
    canvas.drawLine(
      Offset(rect.right - headLen, cy - headLen * 0.65),
      Offset(rect.right, cy),
      paint,
    );
    canvas.drawLine(
      Offset(rect.right - headLen, cy + headLen * 0.65),
      Offset(rect.right, cy),
      paint,
    );
  }

  static void _paintArrowEquilibrium(Canvas canvas, Rect rect, Paint paint) {
    final cy = rect.center.dy;
    final gap = math.max(paint.strokeWidth * 1.8, rect.height * 0.14);
    final headLen = math.min(rect.width * 0.18, rect.height * 0.32);

    // Mũi tên trên (trái -> phải, nửa đầu mũi tên phía trên)
    final topY = cy - gap;
    canvas.drawLine(Offset(rect.left, topY), Offset(rect.right, topY), paint);
    canvas.drawLine(
      Offset(rect.right - headLen, topY - headLen * 0.6),
      Offset(rect.right, topY),
      paint,
    );

    // Mũi tên dưới (phải -> trái, nửa đầu mũi tên phía dưới)
    final botY = cy + gap;
    canvas.drawLine(Offset(rect.right, botY), Offset(rect.left, botY), paint);
    canvas.drawLine(
      Offset(rect.left + headLen, botY + headLen * 0.6),
      Offset(rect.left, botY),
      paint,
    );
  }

  static void _paintArrowResonance(Canvas canvas, Rect rect, Paint paint) {
    final cy = rect.center.dy;
    final headLen = math.min(rect.width * 0.18, rect.height * 0.34);
    canvas.drawLine(Offset(rect.left, cy), Offset(rect.right, cy), paint);

    // Đầu phải
    canvas.drawLine(
      Offset(rect.right - headLen, cy - headLen * 0.65),
      Offset(rect.right, cy),
      paint,
    );
    canvas.drawLine(
      Offset(rect.right - headLen, cy + headLen * 0.65),
      Offset(rect.right, cy),
      paint,
    );

    // Đầu trái
    canvas.drawLine(
      Offset(rect.left + headLen, cy - headLen * 0.65),
      Offset(rect.left, cy),
      paint,
    );
    canvas.drawLine(
      Offset(rect.left + headLen, cy + headLen * 0.65),
      Offset(rect.left, cy),
      paint,
    );
  }

  static void _paintArrowCurved(Canvas canvas, Rect rect, Paint paint) {
    final start = Offset(rect.left + rect.width * 0.08, rect.bottom - rect.height * 0.22);
    final ctrl = Offset(rect.center.dx, rect.top - rect.height * 0.05);
    final end = Offset(rect.right - rect.width * 0.08, rect.bottom - rect.height * 0.22);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);

    // Tiếp tuyến tại điểm cuối (t = 1): end - ctrl
    final angle = math.atan2(end.dy - ctrl.dy, end.dx - ctrl.dx);
    final headLen = math.min(rect.width, rect.height) * 0.22;
    const spread = 0.55;
    canvas.drawLine(
      end,
      Offset(
        end.dx - headLen * math.cos(angle - spread),
        end.dy - headLen * math.sin(angle - spread),
      ),
      paint,
    );
    canvas.drawLine(
      end,
      Offset(
        end.dx - headLen * math.cos(angle + spread),
        end.dy - headLen * math.sin(angle + spread),
      ),
      paint,
    );
  }

  static void _paintErlenmeyerFlask(Canvas canvas, Rect rect, Paint paint) {
    Offset pt(double fx, double fy) =>
        Offset(rect.left + rect.width * fx, rect.top + rect.height * fy);

    // Miệng bình loe nhẹ
    canvas.drawLine(pt(0.34, 0.05), pt(0.66, 0.05), paint);

    final body = Path()
      ..moveTo(pt(0.38, 0.05).dx, pt(0.38, 0.05).dy)
      ..lineTo(pt(0.38, 0.34).dx, pt(0.38, 0.34).dy)
      ..lineTo(pt(0.10, 0.88).dx, pt(0.10, 0.88).dy)
      ..quadraticBezierTo(
        pt(0.08, 0.96).dx,
        pt(0.08, 0.96).dy,
        pt(0.18, 0.96).dx,
        pt(0.18, 0.96).dy,
      )
      ..lineTo(pt(0.82, 0.96).dx, pt(0.82, 0.96).dy)
      ..quadraticBezierTo(
        pt(0.92, 0.96).dx,
        pt(0.92, 0.96).dy,
        pt(0.90, 0.88).dx,
        pt(0.90, 0.88).dy,
      )
      ..lineTo(pt(0.62, 0.34).dx, pt(0.62, 0.34).dy)
      ..lineTo(pt(0.62, 0.05).dx, pt(0.62, 0.05).dy);
    canvas.drawPath(body, paint);

    // Mực chất lỏng minh họa
    final liquidPaint = Paint()
      ..color = paint.color.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, paint.strokeWidth * 0.75)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pt(0.24, 0.68), pt(0.76, 0.68), liquidPaint);
  }

  static void _paintBeaker(Canvas canvas, Rect rect, Paint paint) {
    Offset pt(double fx, double fy) =>
        Offset(rect.left + rect.width * fx, rect.top + rect.height * fy);

    final path = Path()
      ..moveTo(pt(0.12, 0.08).dx, pt(0.12, 0.08).dy)
      ..lineTo(pt(0.20, 0.16).dx, pt(0.20, 0.16).dy)
      ..lineTo(pt(0.20, 0.88).dx, pt(0.20, 0.88).dy)
      ..quadraticBezierTo(
        pt(0.20, 0.95).dx,
        pt(0.20, 0.95).dy,
        pt(0.28, 0.95).dx,
        pt(0.28, 0.95).dy,
      )
      ..lineTo(pt(0.76, 0.95).dx, pt(0.76, 0.95).dy)
      ..quadraticBezierTo(
        pt(0.84, 0.95).dx,
        pt(0.84, 0.95).dy,
        pt(0.84, 0.88).dx,
        pt(0.84, 0.88).dy,
      )
      ..lineTo(pt(0.84, 0.10).dx, pt(0.84, 0.10).dy)
      ..lineTo(pt(0.12, 0.08).dx, pt(0.12, 0.08).dy);
    canvas.drawPath(path, paint);

    // Vạch chia thể tích
    final tickPaint = Paint()
      ..color = paint.color.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, paint.strokeWidth * 0.75)
      ..strokeCap = StrokeCap.round;
    for (final fy in [0.34, 0.50, 0.66, 0.80]) {
      canvas.drawLine(pt(0.64, fy), pt(0.78, fy), tickPaint);
    }
  }

  static void _paintRoundBottomFlask(Canvas canvas, Rect rect, Paint paint) {
    final cx = rect.center.dx;
    final radius = math.min(rect.width * 0.42, rect.height * 0.32);
    final circleCenter = Offset(cx, rect.bottom - radius - rect.height * 0.03);
    final neckHalfW = radius * 0.30;
    final neckTop = rect.top + rect.height * 0.05;
    final neckJoinY =
        circleCenter.dy - math.sqrt(math.max(0, radius * radius - neckHalfW * neckHalfW));

    // Miệng bình
    canvas.drawLine(
      Offset(cx - neckHalfW * 1.25, neckTop),
      Offset(cx + neckHalfW * 1.25, neckTop),
      paint,
    );
    // Cổ bình
    canvas.drawLine(
      Offset(cx - neckHalfW, neckTop),
      Offset(cx - neckHalfW, neckJoinY),
      paint,
    );
    canvas.drawLine(
      Offset(cx + neckHalfW, neckTop),
      Offset(cx + neckHalfW, neckJoinY),
      paint,
    );
    // Thân cầu (cung mở ở cổ bình)
    final openAngle = math.asin((neckHalfW / radius).clamp(0.0, 1.0));
    final startAngle = -math.pi / 2 + openAngle;
    final sweepAngle = 2 * math.pi - 2 * openAngle;
    canvas.drawArc(
      Rect.fromCircle(center: circleCenter, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  static void _paintTestTube(Canvas canvas, Rect rect, Paint paint) {
    final cx = rect.center.dx;
    final halfW = math.min(rect.width * 0.34, rect.height * 0.16);
    final topY = rect.top + rect.height * 0.06;
    final arcCenterY = rect.bottom - halfW - rect.height * 0.04;

    // Miệng ống loe nhẹ
    canvas.drawLine(
      Offset(cx - halfW * 1.3, topY),
      Offset(cx + halfW * 1.3, topY),
      paint,
    );

    final path = Path()
      ..moveTo(cx - halfW, topY)
      ..lineTo(cx - halfW, arcCenterY)
      ..arcToPoint(
        Offset(cx + halfW, arcCenterY),
        radius: Radius.circular(halfW),
        clockwise: false,
      )
      ..lineTo(cx + halfW, topY);
    canvas.drawPath(path, paint);

    // Mực dung dịch
    final liquidY = rect.top + rect.height * 0.56;
    canvas.drawLine(
      Offset(cx - halfW * 0.85, liquidY),
      Offset(cx + halfW * 0.85, liquidY),
      paint..strokeWidth = math.max(1.0, paint.strokeWidth * 0.75),
    );
  }

  static void _paintBurette(Canvas canvas, Rect rect, Paint paint) {
    final cx = rect.center.dx;
    final halfW = math.min(rect.width * 0.24, rect.height * 0.09);
    final topY = rect.top + rect.height * 0.04;
    final taperStartY = rect.top + rect.height * 0.72;
    final stopcockY = rect.top + rect.height * 0.82;
    final tipY = rect.bottom - rect.height * 0.03;

    // Miệng trên
    canvas.drawLine(
      Offset(cx - halfW * 1.35, topY),
      Offset(cx + halfW * 1.35, topY),
      paint,
    );

    // Thân buret + phần thuôn xuống đầu nhỏ giọt
    final path = Path()
      ..moveTo(cx - halfW, topY)
      ..lineTo(cx - halfW, taperStartY)
      ..lineTo(cx - halfW * 0.32, stopcockY)
      ..lineTo(cx - halfW * 0.22, tipY)
      ..moveTo(cx + halfW, topY)
      ..lineTo(cx + halfW, taperStartY)
      ..lineTo(cx + halfW * 0.32, stopcockY)
      ..lineTo(cx + halfW * 0.22, tipY);
    canvas.drawPath(path, paint);

    // Khóa vặn buret
    canvas.drawLine(
      Offset(cx - halfW * 1.8, stopcockY),
      Offset(cx + halfW * 1.8, stopcockY),
      paint,
    );
    canvas.drawCircle(Offset(cx + halfW * 1.8, stopcockY), halfW * 0.45, paint);

    // Vạch chia độ
    final tickPaint = Paint()
      ..color = paint.color.withOpacity(0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, paint.strokeWidth * 0.7);
    for (int i = 1; i <= 6; i++) {
      final y = topY + (taperStartY - topY) * (i / 7);
      final len = i.isEven ? halfW * 0.9 : halfW * 0.55;
      canvas.drawLine(Offset(cx + halfW - len, y), Offset(cx + halfW, y), tickPaint);
    }
  }

  static void _paintPipette(Canvas canvas, Rect rect, Paint paint) {
    final cx = rect.center.dx;
    final stemW = math.min(rect.width * 0.14, rect.height * 0.045);
    final bulbW = math.min(rect.width * 0.36, rect.height * 0.13);
    final topY = rect.top + rect.height * 0.04;
    final bulbTopY = rect.top + rect.height * 0.32;
    final bulbBotY = rect.top + rect.height * 0.64;
    final tipY = rect.bottom - rect.height * 0.04;

    // Ống trên
    canvas.drawLine(Offset(cx - stemW, topY), Offset(cx - stemW, bulbTopY), paint);
    canvas.drawLine(Offset(cx + stemW, topY), Offset(cx + stemW, bulbTopY), paint);
    // Vạch định mức
    canvas.drawLine(
      Offset(cx - stemW * 1.7, rect.top + rect.height * 0.18),
      Offset(cx + stemW * 1.7, rect.top + rect.height * 0.18),
      paint,
    );

    // Bầu pipet
    final bulb = Path()
      ..moveTo(cx - stemW, bulbTopY)
      ..quadraticBezierTo(cx - bulbW * 1.35, (bulbTopY + bulbBotY) / 2, cx - stemW, bulbBotY)
      ..moveTo(cx + stemW, bulbTopY)
      ..quadraticBezierTo(cx + bulbW * 1.35, (bulbTopY + bulbBotY) / 2, cx + stemW, bulbBotY);
    canvas.drawPath(bulb, paint);

    // Đầu nhọn dưới
    canvas.drawLine(Offset(cx - stemW, bulbBotY), Offset(cx - stemW * 0.35, tipY), paint);
    canvas.drawLine(Offset(cx + stemW, bulbBotY), Offset(cx + stemW * 0.35, tipY), paint);
  }

  static void _paintCondenser(Canvas canvas, Rect rect, Paint paint) {
    final cy = rect.center.dy;
    final innerHalfH = rect.height * 0.11;
    final jacketHalfH = rect.height * 0.28;
    final jLeft = rect.left + rect.width * 0.18;
    final jRight = rect.right - rect.width * 0.18;

    // Ống trong chạy suốt
    canvas.drawLine(
      Offset(rect.left, cy - innerHalfH),
      Offset(rect.right, cy - innerHalfH),
      paint,
    );
    canvas.drawLine(
      Offset(rect.left, cy + innerHalfH),
      Offset(rect.right, cy + innerHalfH),
      paint,
    );

    // Áo nước làm mát (jacket)
    canvas.drawRect(
      Rect.fromLTRB(jLeft, cy - jacketHalfH, jRight, cy + jacketHalfH),
      paint,
    );

    // Nhánh nước vào (dưới phải) & nước ra (trên trái)
    final nozzleLen = rect.height * 0.22;
    canvas.drawLine(
      Offset(jLeft + rect.width * 0.08, cy - jacketHalfH),
      Offset(jLeft + rect.width * 0.08, cy - jacketHalfH - nozzleLen),
      paint,
    );
    canvas.drawLine(
      Offset(jRight - rect.width * 0.08, cy + jacketHalfH),
      Offset(jRight - rect.width * 0.08, cy + jacketHalfH + nozzleLen),
      paint,
    );
  }

  static void _paintBunsenBurner(Canvas canvas, Rect rect, Paint paint) {
    final cx = rect.center.dx;
    final baseY = rect.bottom - rect.height * 0.06;
    final tubeHalfW = rect.width * 0.11;
    final tubeTopY = rect.top + rect.height * 0.38;
    final baseTopY = rect.bottom - rect.height * 0.18;

    // Ngọn lửa
    final flame = Path()
      ..moveTo(cx, rect.top + rect.height * 0.05)
      ..quadraticBezierTo(
        cx + tubeHalfW * 2.0,
        rect.top + rect.height * 0.24,
        cx,
        tubeTopY - rect.height * 0.03,
      )
      ..quadraticBezierTo(
        cx - tubeHalfW * 2.0,
        rect.top + rect.height * 0.24,
        cx,
        rect.top + rect.height * 0.05,
      );
    canvas.drawPath(flame, paint);

    // Ống đốt đứng
    canvas.drawRect(
      Rect.fromLTRB(cx - tubeHalfW, tubeTopY, cx + tubeHalfW, baseTopY),
      paint,
    );

    // Ống dẫn khí ngang
    canvas.drawLine(
      Offset(cx + tubeHalfW, baseTopY - rect.height * 0.08),
      Offset(rect.right - rect.width * 0.10, baseTopY - rect.height * 0.08),
      paint,
    );

    // Đế đèn
    final base = Path()
      ..moveTo(rect.left + rect.width * 0.16, baseY)
      ..lineTo(rect.left + rect.width * 0.26, baseTopY)
      ..lineTo(rect.right - rect.width * 0.26, baseTopY)
      ..lineTo(rect.right - rect.width * 0.16, baseY)
      ..close();
    canvas.drawPath(base, paint);
  }

  static void _paintFunnel(Canvas canvas, Rect rect, Paint paint) {
    Offset pt(double fx, double fy) =>
        Offset(rect.left + rect.width * fx, rect.top + rect.height * fy);

    // Miệng phễu trên
    canvas.drawLine(pt(0.08, 0.10), pt(0.92, 0.10), paint);

    // Thân hình nón + cuống phễu cắt vát
    final path = Path()
      ..moveTo(pt(0.08, 0.10).dx, pt(0.08, 0.10).dy)
      ..lineTo(pt(0.43, 0.56).dx, pt(0.43, 0.56).dy)
      ..lineTo(pt(0.43, 0.94).dx, pt(0.43, 0.94).dy)
      ..lineTo(pt(0.57, 0.86).dx, pt(0.57, 0.86).dy)
      ..lineTo(pt(0.57, 0.56).dx, pt(0.57, 0.56).dy)
      ..lineTo(pt(0.92, 0.10).dx, pt(0.92, 0.10).dy);
    canvas.drawPath(path, paint);
  }
}
