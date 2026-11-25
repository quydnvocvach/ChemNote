import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A single continuous laser stroke that remains visible while the pen is held down,
/// then smoothly fades out after the pen lifts (Huawei Notes behavior).
class LaserStroke {
  final List<Offset> points;
  bool isActive;
  int? releasedAtMs;

  LaserStroke({
    required this.points,
    this.isActive = true,
    this.releasedAtMs,
  });
}

/// Manages 144Hz zero-delay laser pointer strokes without rebuilding
/// the underlying page canvas.
class LaserPointerController extends ChangeNotifier {
  final List<LaserStroke> _strokes = [];
  Timer? _fadeTimer;
  Color color;
  String? _activePageId;

  static const int holdAfterReleaseMs = 220;
  static const int fadeOutDurationMs = 700;
  static const int totalReleaseFadeMs = holdAfterReleaseMs + fadeOutDurationMs;

  LaserPointerController({this.color = const Color(0xFFEF4444)});

  List<LaserStroke> get strokes => List.unmodifiable(_strokes);
  String? get activePageId => _activePageId;
  bool get hasPoints => _strokes.isNotEmpty;

  void beginStroke(Offset pos, {String? pageId}) {
    if (pageId != null && _activePageId != null && _activePageId != pageId) {
      _strokes.clear();
    }
    if (pageId != null) _activePageId = pageId;
    for (final s in _strokes) {
      if (s.isActive) {
        s.isActive = false;
        s.releasedAtMs ??= DateTime.now().millisecondsSinceEpoch;
      }
    }
    _strokes.add(LaserStroke(points: [pos], isActive: true));
    notifyListeners();
  }

  void addPoint(Offset pos, {String? pageId}) {
    if (_strokes.isEmpty ||
        !_strokes.last.isActive ||
        (pageId != null && _activePageId != null && _activePageId != pageId)) {
      beginStroke(pos, pageId: pageId);
      return;
    }
    final active = _strokes.last;
    if ((pos - active.points.last).distance < 1.5) return;
    active.points.add(pos);
    notifyListeners();
  }

  void endStroke() {
    final now = DateTime.now().millisecondsSinceEpoch;
    bool endedAny = false;
    for (final s in _strokes) {
      if (s.isActive) {
        s.isActive = false;
        s.releasedAtMs = now;
        endedAny = true;
      }
    }
    if (endedAny || _strokes.isNotEmpty) {
      _ensureTimer();
      notifyListeners();
    }
  }

  void clear() {
    _strokes.clear();
    _activePageId = null;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    notifyListeners();
  }

  void _ensureTimer() {
    _fadeTimer ??= Timer.periodic(const Duration(milliseconds: 8), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _pruneExpired(now);
      if (_strokes.isEmpty || _strokes.every((s) => s.isActive)) {
        _fadeTimer?.cancel();
        _fadeTimer = null;
      }
      notifyListeners();
    });
  }

  void _pruneExpired(int nowMs) {
    _strokes.removeWhere((s) {
      if (s.isActive || s.releasedAtMs == null) return false;
      return nowMs - s.releasedAtMs! > totalReleaseFadeMs;
    });
    if (_strokes.isEmpty) {
      _activePageId = null;
    }
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }
}

/// Paints smooth glowing laser pointer strokes on top of the active page
/// with minimal GPU draw calls at 144Hz.
class LaserPointerPainter extends CustomPainter {
  final LaserPointerController controller;
  final String? pageId;

  LaserPointerPainter({
    required this.controller,
    this.pageId,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    if (pageId != null &&
        controller.activePageId != null &&
        controller.activePageId != pageId) {
      return;
    }
    final strokes = controller.strokes;
    if (strokes.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final baseColor = controller.color;

    for (final stroke in strokes) {
      final pts = stroke.points;
      if (pts.isEmpty) continue;

      double t = 1.0;
      if (!stroke.isActive && stroke.releasedAtMs != null) {
        final ageAfterRelease = now - stroke.releasedAtMs!;
        if (ageAfterRelease > LaserPointerController.holdAfterReleaseMs) {
          final fadeElapsed =
              ageAfterRelease - LaserPointerController.holdAfterReleaseMs;
          t = (1.0 -
                  fadeElapsed / LaserPointerController.fadeOutDurationMs)
              .clamp(0.0, 1.0);
        }
      }
      if (t <= 0.01) continue;

      if (pts.length >= 2) {
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (int i = 1; i < pts.length - 1; i++) {
          final mid = Offset(
            (pts[i].dx + pts[i + 1].dx) * 0.5,
            (pts[i].dy + pts[i + 1].dy) * 0.5,
          );
          path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
        }
        path.lineTo(pts.last.dx, pts.last.dy);

        // Outer neon halo (single drawPath call)
        canvas.drawPath(
          path,
          Paint()
            ..color = baseColor.withAlpha((t * 105).round())
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9.0 * (0.4 + 0.6 * t)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );

        // Bright inner laser core (single drawPath call)
        canvas.drawPath(
          path,
          Paint()
            ..color = Color.lerp(baseColor, Colors.white, 0.55)!
                .withAlpha((t * 245).round())
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.6 * (0.4 + 0.6 * t)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }

      if (stroke.isActive || t > 0.25) {
        final tip = pts.last;
        canvas.drawCircle(
          tip,
          7.0 * t,
          Paint()..color = baseColor.withAlpha((t * 130).round()),
        );
        canvas.drawCircle(
          tip,
          3.4 * t,
          Paint()..color = Colors.white.withAlpha((t * 250).round()),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant LaserPointerPainter oldDelegate) =>
      oldDelegate.pageId != pageId;
}

/// Interactive translucent ruler with centimeter/millimeter ticks (1 cm = 37.8 px,
/// matching A4 794 px = 21 cm), adjustable length (6 cm .. 20 cm), angle readout,
/// magnetic angle snapping (0°, 30°, 45°, 60°, 90°), and stroke-edge snapping.
class RulerState {
  static const double pxPerCm = 37.8;
  static const double minCm = 6.0;
  static const double maxCm = 20.0;
  static const double endPaddingPx = 42.0;

  Offset center;
  double angleRad;
  double lengthCm;
  final double thickness;

  RulerState({
    this.center = const Offset(420, 320),
    this.angleRad = 0.0,
    this.lengthCm = 14.0,
    this.thickness = 68.0,
  });

  double get length => lengthCm * pxPerCm + endPaddingPx * 2;
  double get degrees => (angleRad * 180.0 / math.pi) % 360.0;

  void setLengthCm(double cm) {
    lengthCm = cm.clamp(minCm, maxCm);
  }

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

    // Transform back to caller coordinate space
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
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const InteractiveRulerOverlay({
    super.key,
    required this.ruler,
    required this.onChanged,
    required this.onClose,
    this.onDragStart,
    this.onDragEnd,
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
    final degNormalized =
        ((ruler.angleRad * 180.0 / math.pi) % 180.0 + 180.0) % 180.0;
    final displayDeg = degNormalized > 90 ? 180 - degNormalized : degNormalized;

    return Positioned(
      left: ruler.center.dx - ruler.length * 0.5,
      top: ruler.center.dy - ruler.thickness * 0.5,
      child: Transform.rotate(
        angle: ruler.angleRad,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => onDragStart?.call(),
          onPanUpdate: (details) {
            final cosA = math.cos(ruler.angleRad);
            final sinA = math.sin(ruler.angleRad);
            final pageDx = details.delta.dx * cosA - details.delta.dy * sinA;
            final pageDy = details.delta.dx * sinA + details.delta.dy * cosA;
            ruler.center += Offset(pageDx, pageDy);
            onChanged();
          },
          onPanEnd: (_) => onDragEnd?.call(),
          onPanCancel: () => onDragEnd?.call(),
          child: SizedBox(
            width: ruler.length,
            height: ruler.thickness,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _RulerBodyPainter(
                        angleLabel: '${displayDeg.toStringAsFixed(0)}°',
                        lengthCm: ruler.lengthCm,
                      ),
                    ),
                  ),
                ),
                // Left edge drag-to-resize handle
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => onDragStart?.call(),
                    onPanUpdate: (d) {
                      ruler.setLengthCm(
                        ruler.lengthCm - (d.delta.dx * 2.0) / RulerState.pxPerCm,
                      );
                      onChanged();
                    },
                    onPanEnd: (_) => onDragEnd?.call(),
                    onPanCancel: () => onDragEnd?.call(),
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white54,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                // Right edge drag-to-resize handle
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => onDragStart?.call(),
                    onPanUpdate: (d) {
                      ruler.setLengthCm(
                        ruler.lengthCm + (d.delta.dx * 2.0) / RulerState.pxPerCm,
                      );
                      onChanged();
                    },
                    onPanEnd: (_) => onDragEnd?.call(),
                    onPanCancel: () => onDragEnd?.call(),
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white54,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                // Left controls: rotate -15° & shorten (-2 cm)
                Positioned(
                  left: 16,
                  top: (ruler.thickness - 26) * 0.5,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RulerMiniBtn(
                        icon: Icons.rotate_left_rounded,
                        tooltip: 'Xoay -15°',
                        onTap: () => _rotateBy(-math.pi / 12),
                      ),
                      const SizedBox(width: 4),
                      _RulerMiniBtn(
                        icon: Icons.remove_rounded,
                        tooltip: 'Thu ngắn (-2 cm)',
                        onTap: () {
                          ruler.setLengthCm((ruler.lengthCm - 2.0).roundToDouble());
                          onChanged();
                        },
                      ),
                    ],
                  ),
                ),
                // Right controls: lengthen (+2 cm), rotate +15° & close
                Positioned(
                  right: 16,
                  top: (ruler.thickness - 26) * 0.5,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RulerMiniBtn(
                        icon: Icons.add_rounded,
                        tooltip: 'Kéo dài (+2 cm)',
                        onTap: () {
                          ruler.setLengthCm((ruler.lengthCm + 2.0).roundToDouble());
                          onChanged();
                        },
                      ),
                      const SizedBox(width: 4),
                      _RulerMiniBtn(
                        icon: Icons.rotate_right_rounded,
                        tooltip: 'Xoay +15°',
                        onTap: () => _rotateBy(math.pi / 12),
                      ),
                      const SizedBox(width: 4),
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
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0xFF16181D).withAlpha(210),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}

class _RulerBodyPainter extends CustomPainter {
  final String angleLabel;
  final double lengthCm;

  const _RulerBodyPainter({
    required this.angleLabel,
    required this.lengthCm,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

    // Translucent frosted ruler body
    canvas.drawRRect(
      rrect,
      Paint()..color = const Color(0xFF1E293B).withAlpha(192),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF60A5FA).withAlpha(195)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Calibrated cm & mm ticks along top & bottom edges (1 cm = 37.8 px)
    final cmTickPaint = Paint()
      ..color = Colors.white.withAlpha(235)
      ..strokeWidth = 1.25;
    final mmTickPaint = Paint()
      ..color = Colors.white.withAlpha(165)
      ..strokeWidth = 0.85;

    const double pxPerMm = RulerState.pxPerCm / 10.0;
    const double startX = RulerState.endPaddingPx;
    final int totalCm = lengthCm.floor();
    final int totalMm = (lengthCm * 10.0).round();

    for (int mm = 0; mm <= totalMm; mm++) {
      final x = startX + mm * pxPerMm;
      if (x > size.width - RulerState.endPaddingPx + 1.0) break;
      final isCm = mm % 10 == 0;
      final isHalf = mm % 5 == 0;
      final len = isCm ? 13.0 : (isHalf ? 8.5 : 5.0);
      final p = isCm ? cmTickPaint : mmTickPaint;

      canvas.drawLine(Offset(x, 0), Offset(x, len), p);
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - len),
        p,
      );

      if (isCm) {
        final cmVal = mm ~/ 10;
        final label = cmVal == totalCm ? '${cmVal}cm' : '$cmVal';
        final numTp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: Colors.white.withAlpha(220),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        numTp.paint(canvas, Offset(x - numTp.width * 0.5, 13.5));
      }
    }

    // Center angle & length badge
    final tp = TextPainter(
      text: TextSpan(
        text: '$angleLabel · ${lengthCm.toStringAsFixed(0)} cm',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final cx = (size.width - tp.width) * 0.5;
    final cy = (size.height - tp.height) * 0.5 + 4.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 10, cy - 3, tp.width + 20, tp.height + 6),
        const Radius.circular(11),
      ),
      Paint()..color = const Color(0xFF3B82F6).withAlpha(225),
    );
    tp.paint(canvas, Offset(cx, cy));
  }

  @override
  bool shouldRepaint(covariant _RulerBodyPainter oldDelegate) {
    return oldDelegate.angleLabel != angleLabel ||
        oldDelegate.lengthCm != lengthCm;
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
