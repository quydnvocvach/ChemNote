import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A single timed point in a fading laser pointer trail.
class LaserTrailPoint {
  final Offset position;
  final int timestampMs;

  const LaserTrailPoint(this.position, this.timestampMs);
}

/// Manages a glowing, auto-fading laser pointer trail without rebuilding
/// the underlying page canvas.
class LaserPointerController extends ChangeNotifier {
  final List<LaserTrailPoint> _points = [];
  Timer? _fadeTimer;
  Color color;
  static const int trailDurationMs = 950;

  LaserPointerController({this.color = const Color(0xFFEF4444)});

  List<LaserTrailPoint> get points => List.unmodifiable(_points);
  bool get hasPoints => _points.isNotEmpty;

  void addPoint(Offset pos) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _points.add(LaserTrailPoint(pos, now));
    _pruneExpired(now);
    _ensureTimer();
    notifyListeners();
  }

  void endStroke() {
    _ensureTimer();
  }

  void clear() {
    _points.clear();
    _fadeTimer?.cancel();
    _fadeTimer = null;
    notifyListeners();
  }

  void _ensureTimer() {
    _fadeTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _pruneExpired(now);
      if (_points.isEmpty) {
        _fadeTimer?.cancel();
        _fadeTimer = null;
      }
      notifyListeners();
    });
  }

  void _pruneExpired(int nowMs) {
    _points.removeWhere((p) => nowMs - p.timestampMs > trailDurationMs);
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }
}

/// Paints the glowing fading laser pointer trail on top of the active page.
class LaserPointerPainter extends CustomPainter {
  final LaserPointerController controller;

  LaserPointerPainter({required this.controller}) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = controller.points;
    if (pts.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final baseColor = controller.color;

    for (int i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      // Skip large jumps between separate laser strokes
      if ((b.position - a.position).distance > 90) continue;

      final age = now - b.timestampMs;
      final t = (1.0 - age / LaserPointerController.trailDurationMs)
          .clamp(0.0, 1.0);
      if (t <= 0.01) continue;

      // Outer glow
      canvas.drawLine(
        a.position,
        b.position,
        Paint()
          ..color = baseColor.withAlpha((t * 95).round())
          ..strokeWidth = 10.0 * t + 3.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
      );

      // Bright core
      canvas.drawLine(
        a.position,
        b.position,
        Paint()
          ..color = Color.lerp(baseColor, Colors.white, 0.55)!
              .withAlpha((t * 245).round())
          ..strokeWidth = 3.2 * t + 1.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // Glowing tip dot
    final tip = pts.last;
    final tipT = (1.0 - (now - tip.timestampMs) / LaserPointerController.trailDurationMs)
        .clamp(0.0, 1.0);
    if (tipT > 0.05) {
      canvas.drawCircle(
        tip.position,
        6.5 * tipT,
        Paint()
          ..color = baseColor.withAlpha((tipT * 200).round())
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );
      canvas.drawCircle(
        tip.position,
        3.0 * tipT,
        Paint()..color = Colors.white.withAlpha((tipT * 245).round()),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LaserPointerPainter oldDelegate) => false;
}

/// Interactive translucent ruler with millimeter ticks, angle readout,
/// magnetic angle snapping (0°, 30°, 45°, 60°, 90°), and stroke-edge snapping.
class RulerState {
  Offset center;
  double angleRad;
  final double length;
  final double thickness;

  RulerState({
    this.center = const Offset(397, 420),
    this.angleRad = 0.0,
    this.length = 560.0,
    this.thickness = 64.0,
  });

  double get degrees => (angleRad * 180.0 / math.pi) % 360.0;

  /// Snaps an incoming drawing point [pt] onto the ruler's top or bottom edge
  /// if it is within [snapThreshold] logical pixels of the edge.
  Offset snapPointIfNearEdge(Offset pt, {double snapThreshold = 22.0}) {
    final dx = pt.dx - center.dx;
    final dy = pt.dy - center.dy;
    final cosA = math.cos(-angleRad);
    final sinA = math.sin(-angleRad);
    // Transform into ruler local space
    final localX = dx * cosA - dy * sinA;
    final localY = dx * sinA + dy * cosA;

    final halfL = length * 0.5 + 16.0;
    final halfT = thickness * 0.5;
    if (localX.abs() > halfL) return pt;

    double? snappedLocalY;
    if ((localY - (-halfT)).abs() <= snapThreshold) {
      snappedLocalY = -halfT - 1.5;
    } else if ((localY - halfT).abs() <= snapThreshold) {
      snappedLocalY = halfT + 1.5;
    }
    if (snappedLocalY == null) return pt;

    // Transform back to page space
    final cosB = math.cos(angleRad);
    final sinB = math.sin(angleRad);
    return Offset(
      center.dx + localX * cosB - snappedLocalY * sinB,
      center.dy + localX * sinB + snappedLocalY * cosB,
    );
  }
}

/// Visual + interactive widget for the translucent chemistry/drafting ruler.
class InteractiveRulerOverlay extends StatelessWidget {
  final RulerState ruler;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  const InteractiveRulerOverlay({
    super.key,
    required this.ruler,
    required this.onChanged,
    required this.onClose,
  });

  void _rotateBy(double deltaRad) {
    double next = ruler.angleRad + deltaRad;
    // Magnetic snap to 0°, 30°, 45°, 60°, 90°, 120°, 135°, 150°, 180°
    final deg = (next * 180.0 / math.pi) % 180.0;
    const snapTargets = [0.0, 30.0, 45.0, 60.0, 90.0, 120.0, 135.0, 150.0, 180.0];
    for (final t in snapTargets) {
      if ((deg - t).abs() < 2.2) {
        next = t * math.pi / 180.0;
        break;
      }
    }
    ruler.angleRad = next;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final degNormalized = ((ruler.angleRad * 180.0 / math.pi) % 180.0 + 180.0) % 180.0;
    final displayDeg = degNormalized > 90 ? 180 - degNormalized : degNormalized;

    return Positioned(
      left: ruler.center.dx - ruler.length * 0.5,
      top: ruler.center.dy - ruler.thickness * 0.5,
      child: Transform.rotate(
        angle: ruler.angleRad,
        child: GestureDetector(
          onPanUpdate: (details) {
            // Rotate delta back to page coordinates
            final cosA = math.cos(ruler.angleRad);
            final sinA = math.sin(ruler.angleRad);
            final pageDx = details.delta.dx * cosA - details.delta.dy * sinA;
            final pageDy = details.delta.dx * sinA + details.delta.dy * cosA;
            ruler.center += Offset(pageDx, pageDy);
            onChanged();
          },
          child: SizedBox(
            width: ruler.length,
            height: ruler.thickness,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RulerBodyPainter(
                      angleLabel: '${displayDeg.toStringAsFixed(0)}°',
                    ),
                  ),
                ),
                // Left rotate -15° button
                Positioned(
                  left: 10,
                  top: (ruler.thickness - 28) * 0.5,
                  child: _RulerMiniBtn(
                    icon: Icons.rotate_left_rounded,
                    tooltip: 'Xoay -15°',
                    onTap: () => _rotateBy(-math.pi / 12),
                  ),
                ),
                // Right rotate +15° & close buttons
                Positioned(
                  right: 10,
                  top: (ruler.thickness - 28) * 0.5,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RulerMiniBtn(
                        icon: Icons.rotate_right_rounded,
                        tooltip: 'Xoay +15°',
                        onTap: () => _rotateBy(math.pi / 12),
                      ),
                      const SizedBox(width: 6),
                      _RulerMiniBtn(
                        icon: Icons.close_rounded,
                        tooltip: 'Ẩn thước',
                        onTap: onClose,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RulerMiniBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RulerMiniBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF16181D).withAlpha(205),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, size: 15, color: Colors.white),
        ),
      ),
    );
  }
}

class _RulerBodyPainter extends CustomPainter {
  final String angleLabel;

  const _RulerBodyPainter({required this.angleLabel});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

    // Translucent frosted ruler body
    canvas.drawRRect(
      rrect,
      Paint()..color = const Color(0xFF1E293B).withAlpha(185),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF60A5FA).withAlpha(190)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Millimeter & centimeter ticks along top & bottom edges
    final tickPaint = Paint()
      ..color = Colors.white.withAlpha(200)
      ..strokeWidth = 1.0;

    const double pxPerMm = 4.0;
    final int totalMm = ((size.width - 100) / pxPerMm).floor();
    const double startX = 50.0;

    for (int mm = 0; mm <= totalMm; mm++) {
      final x = startX + mm * pxPerMm;
      final isCm = mm % 10 == 0;
      final isHalf = mm % 5 == 0;
      final len = isCm ? 13.0 : (isHalf ? 9.0 : 5.5);

      canvas.drawLine(Offset(x, 0), Offset(x, len), tickPaint);
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - len),
        tickPaint,
      );
    }

    // Center angle badge
    final tp = TextPainter(
      text: TextSpan(
        text: angleLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final cx = (size.width - tp.width) * 0.5;
    final cy = (size.height - tp.height) * 0.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 10, cy - 4, tp.width + 20, tp.height + 8),
        const Radius.circular(12),
      ),
      Paint()..color = const Color(0xFF3B82F6).withAlpha(220),
    );
    tp.paint(canvas, Offset(cx, cy));
  }

  @override
  bool shouldRepaint(covariant _RulerBodyPainter oldDelegate) {
    return oldDelegate.angleLabel != angleLabel;
  }
}

/// Docked GoodNotes-style Zoom Window panel shown at the bottom when Zoom Window
/// mode is enabled, allowing comfortable close-up handwriting with auto-advance.
class ZoomWindowDock extends StatelessWidget {
  final Rect focusRect;
  final Size pageSize;
  final Widget Function(Rect focusRect) magnifiedPageBuilder;
  final VoidCallback onStepLeft;
  final VoidCallback onStepRight;
  final VoidCallback onNewLine;
  final VoidCallback onClose;

  const ZoomWindowDock({
    super.key,
    required this.focusRect,
    required this.pageSize,
    required this.magnifiedPageBuilder,
    required this.onStepLeft,
    required this.onStepRight,
    required this.onNewLine,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF16181D) : Colors.white;
    final border = isDark ? Colors.white12 : Colors.black12;

    return Container(
      height: 215,
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: const Color(0xFF3B82F6), width: 2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(70),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.zoom_in_rounded,
                  size: 16,
                  color: Color(0xFF3B82F6),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Cửa sổ phóng to (Viết cận cảnh)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Lùi trái',
                  icon: const Icon(Icons.chevron_left_rounded, size: 19),
                  visualDensity: VisualDensity.compact,
                  onPressed: onStepLeft,
                ),
                IconButton(
                  tooltip: 'Tiến phải',
                  icon: const Icon(Icons.chevron_right_rounded, size: 19),
                  visualDensity: VisualDensity.compact,
                  onPressed: onStepRight,
                ),
                IconButton(
                  tooltip: 'Xuống dòng mới',
                  icon: const Icon(Icons.keyboard_return_rounded, size: 17),
                  visualDensity: VisualDensity.compact,
                  onPressed: onNewLine,
                ),
                IconButton(
                  tooltip: 'Đóng cửa sổ phóng to',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRect(
              child: magnifiedPageBuilder(focusRect),
            ),
          ),
        ],
      ),
    );
  }
}
