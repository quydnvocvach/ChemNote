import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/models/drawing_elements.dart';

/// Result of attempting to recognize and snap a hand-drawn stroke to a geometric shape.
class ShapeRecognitionResult {
  final ShapeType shapeType;
  final List<StrokePoint> snappedPoints;

  const ShapeRecognitionResult({
    required this.shapeType,
    required this.snappedPoints,
  });

  bool get recognized => shapeType != ShapeType.none;
}

/// Palm rejection filter optimized for Huawei MatePad 11.5"S + Huawei M-Pencil 3
/// (NearLink) and Samsung S-Pen, supporting stylus hover preemption and strict
/// palm rejection while still allowing multi-finger navigation gestures.
class PalmRejectionFilter {
  static const int stylusCooldownMs = 550;

  bool stylusOnlyMode;
  DateTime? _lastStylusEventTime;

  PalmRejectionFilter({this.stylusOnlyMode = false});

  /// Record any stylus hover, down, move, or lift activity so touch palm
  /// events immediately before or after a stroke are suppressed cleanly.
  void notifyStylusActivity() {
    _lastStylusEventTime = DateTime.now();
  }

  /// Call when a stylus hover event is detected to preempt accidental palm rest
  /// before the nib even touches the screen.
  void notifyStylusHover() => notifyStylusActivity();

  bool get isStylusRecentlyActive {
    if (_lastStylusEventTime == null) return false;
    return DateTime.now().difference(_lastStylusEventTime!).inMilliseconds <
        stylusCooldownMs;
  }

  /// Returns true when a touch event carries an extreme palm-sized contact
  /// radius (> 45 logical px). Uncalibrated normalized `size` values are
  /// intentionally ignored because Huawei MatePad panels report `size == 1.0`
  /// for ordinary fingertips.
  static bool isLikelyPalmTouch(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return false;
    return event.radiusMajor > 45.0 && event.radiusMajor < 400.0;
  }

  /// Returns true if the incoming pointer event should be accepted for drawing.
  bool shouldAccept(PointerEvent event) {
    final kind = event.kind;

    if (kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus) {
      notifyStylusActivity();
      return true;
    }

    // Allow mouse for desktop/emulator/testing convenience
    if (kind == PointerDeviceKind.mouse) {
      return true;
    }

    // Strict stylus-only mode rejects all finger/palm touch for drawing
    if (stylusOnlyMode) {
      return false;
    }

    // Heuristic palm rejection when finger drawing is allowed:
    // 1) Ignore touch events while stylus is hovering or recently active
    if (isStylusRecentlyActive) {
      return false;
    }

    // 2) Reject large contact areas typical of a resting palm
    if (isLikelyPalmTouch(event)) {
      return false;
    }

    return true;
  }
}

/// Core 144Hz ink engine handling:
/// - Huawei M-Pencil 3 10,000-level pressure gamma curve + tilt shading
/// - Velocity-based pressure fallback for finger/mouse
/// - Live & post-stroke handwriting smoothing / auto-neatening (GoodNotes-style)
/// - Variable-width ink ribbon path generation (including graphite pencil)
/// - Geometric shape recognition (Line, Circle, Rectangle, Triangle, Hexagon / Benzene ring)
/// - Scribble-to-Erase zig-zag detection
class StrokeEngine {
  /// Applies a smooth response curve tailored for Huawei M-Pencil 3's
  /// 10,000-level pressure sensor. [gamma] < 1.0 makes light strokes fuller;
  /// [gamma] > 1.0 requires firmer pressure for max thickness.
  static double applyMPencilPressureCurve(
    double normalizedPressure, {
    double gamma = 0.85,
  }) {
    final clamped = normalizedPressure.clamp(0.0, 1.0);
    if (clamped <= 0.001) return 0.08;
    // Smooth S-curve blended with configurable gamma for natural PaperMatte feel
    final curved = math.pow(clamped, gamma.clamp(0.4, 2.0)).toDouble();
    return (0.08 + curved * 0.92).clamp(0.08, 1.0);
  }

  /// Extract normalized pressure (0.08..1.0) from a [PointerEvent].
  /// Uses hardware stylus pressure with M-Pencil 3 curve when available;
  /// falls back to velocity-based simulated pressure for finger/mouse input.
  static double computePressure(
    PointerEvent event, {
    StrokePoint? previousPoint,
    double pressureGamma = 0.85,
  }) {
    final bool isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;

    if (isStylus && event.pressureMax > event.pressureMin) {
      final normalized = (event.pressure - event.pressureMin) /
          (event.pressureMax - event.pressureMin);
      return applyMPencilPressureCurve(normalized, gamma: pressureGamma);
    }

    // Velocity fallback for finger / mouse
    if (previousPoint == null) return 0.55;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final dt = math.max(1, nowMs - previousPoint.timestamp);
    final dx = event.localPosition.dx - previousPoint.x;
    final dy = event.localPosition.dy - previousPoint.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    final velocity = dist / dt; // px per ms

    final targetPressure = (0.82 - velocity * 0.24).clamp(0.22, 0.88);
    return previousPoint.pressure * 0.65 + targetPressure * 0.35;
  }

  /// Create a [StrokePoint] from a [PointerEvent] and canvas-space [position].
  static StrokePoint pointFromEvent(
    PointerEvent event,
    Offset position, {
    StrokePoint? previousPoint,
    double pressureGamma = 0.85,
  }) {
    final pressure = computePressure(
      event,
      previousPoint: previousPoint,
      pressureGamma: pressureGamma,
    );
    return StrokePoint(
      x: position.dx,
      y: position.dy,
      pressure: pressure,
      tilt: event.tilt,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Live jitter filter & stabilization when appending a point during drawing.
  /// Returns null if the point is too close (micro-jitter) and should be skipped.
  static StrokePoint? filterLivePoint(
    StrokePoint incoming,
    List<StrokePoint> currentPoints, {
    double stabilization = 0.55,
  }) {
    if (currentPoints.isEmpty) return incoming;

    // 0% smoothing = 100% raw untouched M-Pencil 3 ink (only skip exact duplicate coords)
    if (stabilization <= 0.01) {
      final prev = currentPoints.last;
      if ((incoming.x - prev.x).abs() < 0.2 &&
          (incoming.y - prev.y).abs() < 0.2) {
        return null;
      }
      return incoming;
    }

    final prev = currentPoints.last;
    final dx = incoming.x - prev.x;
    final dy = incoming.y - prev.y;
    final dist = math.sqrt(dx * dx + dy * dy);

    final minDistance = 1.1 + stabilization * 1.3;
    if (dist < minDistance) return null;

    final alpha = (1.0 - stabilization * 0.56).clamp(0.34, 1.0);
    return StrokePoint(
      x: prev.x + dx * alpha,
      y: prev.y + dy * alpha,
      pressure: prev.pressure * 0.38 + incoming.pressure * 0.62,
      tilt: prev.tilt * 0.5 + incoming.tilt * 0.5,
      timestamp: incoming.timestamp,
    );
  }

  /// Post-stroke handwriting smoothing & auto-neatening ("tự nắn lại nét chữ").
  static List<StrokePoint> smoothAndNeatenStroke(
    List<StrokePoint> rawPoints, {
    double stabilization = 0.55,
    bool autoNeaten = true,
    ToolType toolType = ToolType.fountainPen,
  }) {
    // When smoothing is OFF or 0%, bypass ALL smoothing/neatening completely!
    if (!autoNeaten || stabilization <= 0.01 || rawPoints.length < 3) {
      return List<StrokePoint>.from(rawPoints);
    }

    final double strength = stabilization.clamp(0.0, 1.0);
    List<StrokePoint> working = _deduplicatePoints(rawPoints, minDist: 1.5);
    if (working.length < 3) return working;

    // Step 1: At most ONE ultra-gentle micro-tremor pass (<= 0.18 * strength)
    // Preserves sharp corners and NEVER pulls cursive loops inward or shrinks letters!
    if (strength > 0.01) {
      final double gentleWeight = (0.18 * strength).clamp(0.02, 0.18);
      working = _cornerPreservingSmooth(working, weight: gentleWeight);
    }

    // Step 2: Interpolating Catmull-Rom spline passing cleanly THROUGH actual letter
    // peaks & loops (NO baseline squashing!) so handwriting stays 100% full-size & fluid.
    if (working.length >= 4) {
      working = _catmullRomInterpolate(
        working,
        subdivisions: strength > 0.6 ? 3 : 2,
      );
    }

    // Step 3: Smooth pressures gently without needle tapering
    working = _smoothAndTaperPressure(
      working,
      toolType: toolType,
      applyTaper: false,
    );

    return working;
  }

  static List<StrokePoint> _deduplicatePoints(
    List<StrokePoint> points, {
    double minDist = 1.5,
  }) {
    if (points.length <= 2) return List<StrokePoint>.from(points);
    final result = <StrokePoint>[points.first];
    for (int i = 1; i < points.length - 1; i++) {
      final p = points[i];
      final last = result.last;
      if (_dist(last, p) >= minDist) {
        result.add(p);
      }
    }
    result.add(points.last);
    return result;
  }

  static List<StrokePoint> _cornerPreservingSmooth(
    List<StrokePoint> points, {
    required double weight,
  }) {
    if (points.length < 3) return points;
    final out = <StrokePoint>[points.first];

    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];

      final v1x = curr.x - prev.x;
      final v1y = curr.y - prev.y;
      final v2x = next.x - curr.x;
      final v2y = next.y - curr.y;
      final len1 = math.sqrt(v1x * v1x + v1y * v1y);
      final len2 = math.sqrt(v2x * v2x + v2y * v2y);

      double localWeight = weight;
      if (len1 > 0.001 && len2 > 0.001) {
        final dot = ((v1x * v2x + v1y * v2y) / (len1 * len2)).clamp(-1.0, 1.0);
        if (dot < 0.65) {
          localWeight *= ((dot + 1.0) / 1.65).clamp(0.05, 0.35);
        }
      }

      final avgX = (prev.x + next.x) * 0.5;
      final avgY = (prev.y + next.y) * 0.5;
      final avgP = (prev.pressure + curr.pressure + next.pressure) / 3.0;

      out.add(
        StrokePoint(
          x: curr.x * (1.0 - localWeight) + avgX * localWeight,
          y: curr.y * (1.0 - localWeight) + avgY * localWeight,
          pressure: avgP,
          tilt: curr.tilt,
          timestamp: curr.timestamp,
        ),
      );
    }

    out.add(points.last);
    return out;
  }

  static List<StrokePoint> _applySubtleBaselineNeatening(
    List<StrokePoint> points, {
    required double strength,
  }) {
    if (points.length < 4) return points;
    final start = points.first;
    final end = points.last;
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final chord = math.sqrt(dx * dx + dy * dy);
    if (chord < 14.0) return points;

    double maxDev = 0.0;
    for (final p in points) {
      final d = _pointToLineDistance(p, start, end);
      if (d > maxDev) maxDev = d;
    }

    if (maxDev / chord > 0.075) return points;

    final angle = math.atan2(dy, dx);
    double targetEndX = end.x;
    double targetEndY = end.y;
    const double snapRad = 4.0 * math.pi / 180.0;
    if (angle.abs() < snapRad || (angle.abs() - math.pi).abs() < snapRad) {
      targetEndY = start.y * 0.5 + end.y * 0.5;
    } else if ((angle.abs() - math.pi / 2).abs() < snapRad) {
      targetEndX = start.x * 0.5 + end.x * 0.5;
    }

    final pull = (strength * 0.45).clamp(0.0, 0.5);
    final result = <StrokePoint>[];
    for (int i = 0; i < points.length; i++) {
      final t = i / (points.length - 1);
      final idealX = start.x + (targetEndX - start.x) * t;
      final idealY = start.y + (targetEndY - start.y) * t;
      final p = points[i];
      result.add(
        StrokePoint(
          x: p.x * (1.0 - pull) + idealX * pull,
          y: p.y * (1.0 - pull) + idealY * pull,
          pressure: p.pressure,
          tilt: p.tilt,
          timestamp: p.timestamp,
        ),
      );
    }
    return result;
  }

  static List<StrokePoint> _catmullRomInterpolate(
    List<StrokePoint> pts, {
    int subdivisions = 2,
  }) {
    if (pts.length < 4) return pts;
    final out = <StrokePoint>[pts.first];

    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[0] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = (i + 2 < pts.length) ? pts[i + 2] : pts[pts.length - 1];

      for (int s = 1; s <= subdivisions; s++) {
        final t = s / subdivisions;
        final t2 = t * t;
        final t3 = t2 * t;

        final x = 0.5 *
            ((2 * p1.x) +
                (-p0.x + p2.x) * t +
                (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
                (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);
        final y = 0.5 *
            ((2 * p1.y) +
                (-p0.y + p2.y) * t +
                (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
                (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);
        final pressure = p1.pressure + (p2.pressure - p1.pressure) * t;
        final tilt = p1.tilt + (p2.tilt - p1.tilt) * t;
        final ts = (p1.timestamp + (p2.timestamp - p1.timestamp) * t).round();

        out.add(StrokePoint(
          x: x,
          y: y,
          pressure: pressure.clamp(0.05, 1.0),
          tilt: tilt,
          timestamp: ts,
        ));
      }
    }

    return out;
  }

  static List<StrokePoint> _smoothAndTaperPressure(
    List<StrokePoint> points, {
    required ToolType toolType,
    required bool applyTaper,
  }) {
    if (points.length < 3) return points;

    final int n = points.length;
    final int taperCount = applyTaper ? math.min(6, n ~/ 4) : 0;
    final out = <StrokePoint>[];

    for (int i = 0; i < n; i++) {
      final p = points[i];
      double pressure = p.pressure;

      if (i > 0 && i < n - 1) {
        pressure =
            (points[i - 1].pressure + p.pressure * 2 + points[i + 1].pressure) /
                4.0;
      }

      if (applyTaper && taperCount > 0) {
        if (i < taperCount) {
          final factor = 0.45 + 0.55 * (i / taperCount);
          pressure *= factor;
        } else if (i >= n - taperCount) {
          final rem = n - 1 - i;
          final factor = 0.35 + 0.65 * (rem / taperCount);
          pressure *= factor;
        }
      }

      out.add(StrokePoint(
        x: p.x,
        y: p.y,
        pressure: pressure.clamp(0.08, 1.0),
        tilt: p.tilt,
        timestamp: p.timestamp,
      ));
    }

    return out;
  }

  /// Compute effective stroke radius at a given [StrokePoint] for a [ToolType],
  /// incorporating pressure and M-Pencil 3 tilt shading.
  static double radiusForPoint(
    StrokePoint point, {
    required double baseWidth,
    required ToolType toolType,
    Offset? direction,
  }) {
    final p = point.pressure.clamp(0.08, 1.0);
    // Tilt in radians (0 = vertical, ~1.2 = heavily tilted shading)
    final tiltBoost = point.tilt > 0.35
        ? 1.0 + ((point.tilt - 0.35) / 1.0).clamp(0.0, 1.0) * 0.9
        : 1.0;

    double multiplier;

    switch (toolType) {
      case ToolType.fountainPen:
        multiplier = 0.45 + p * 0.85;
        if (direction != null && direction.distanceSquared > 0.001) {
          final angleFactor =
              0.88 + 0.24 * (direction.dy.abs() / direction.distance);
          multiplier *= angleFactor;
        }
        break;
      case ToolType.ballpointPen:
        multiplier = 0.82 + p * 0.28;
        break;
      case ToolType.brushPen:
        multiplier = (0.28 + math.pow(p, 1.25).toDouble() * 1.45) *
            (1.0 + (tiltBoost - 1.0) * 0.4);
        break;
      case ToolType.pencil:
        // Graphite pencil widens naturally when tilted on MatePad PaperMatte!
        multiplier = (0.55 + p * 0.55) * tiltBoost;
        break;
      case ToolType.highlighter:
      case ToolType.studyTape:
      case ToolType.laserPointer:
        multiplier = 1.0;
        break;
    }

    return math.max(0.4, (baseWidth * multiplier) * 0.5);
  }

  /// Builds a smooth, filled variable-width ink ribbon [Path] for high-FPS
  /// rendering of fountain, ballpoint, brush, and pencil strokes.
  static Path buildVariableWidthPath(Stroke stroke) {
    final pts = stroke.points;
    final Path path = Path();
    if (pts.isEmpty) return path;

    if (pts.length == 1) {
      final r = radiusForPoint(
        pts.first,
        baseWidth: stroke.width,
        toolType: stroke.toolType,
      );
      path.addOval(
        Rect.fromCircle(center: Offset(pts.first.x, pts.first.y), radius: r),
      );
      return path;
    }

    final leftSide = <Offset>[];
    final rightSide = <Offset>[];

    for (int i = 0; i < pts.length; i++) {
      final curr = Offset(pts[i].x, pts[i].y);
      Offset tangent;
      if (i == 0) {
        tangent = Offset(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
      } else if (i == pts.length - 1) {
        tangent = Offset(
          pts[i].x - pts[i - 1].x,
          pts[i].y - pts[i - 1].y,
        );
      } else {
        tangent = Offset(
          pts[i + 1].x - pts[i - 1].x,
          pts[i + 1].y - pts[i - 1].y,
        );
      }

      final len = tangent.distance;
      final normal = len > 0.0001
          ? Offset(-tangent.dy / len, tangent.dx / len)
          : const Offset(0, 1);

      final r = radiusForPoint(
        pts[i],
        baseWidth: stroke.width,
        toolType: stroke.toolType,
        direction: tangent,
      );

      leftSide.add(curr + normal * r);
      rightSide.add(curr - normal * r);
    }

    path.moveTo(leftSide.first.dx, leftSide.first.dy);
    for (int i = 1; i < leftSide.length - 1; i++) {
      final mid = Offset(
        (leftSide[i].dx + leftSide[i + 1].dx) * 0.5,
        (leftSide[i].dy + leftSide[i + 1].dy) * 0.5,
      );
      path.quadraticBezierTo(leftSide[i].dx, leftSide[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(leftSide.last.dx, leftSide.last.dy);

    final lastPt = Offset(pts.last.x, pts.last.y);
    final endR = radiusForPoint(
      pts.last,
      baseWidth: stroke.width,
      toolType: stroke.toolType,
    );
    path.arcToPoint(
      rightSide.last,
      radius: Radius.circular(endR),
      clockwise: true,
    );

    for (int i = rightSide.length - 2; i > 0; i--) {
      final mid = Offset(
        (rightSide[i].dx + rightSide[i - 1].dx) * 0.5,
        (rightSide[i].dy + rightSide[i - 1].dy) * 0.5,
      );
      path.quadraticBezierTo(rightSide[i].dx, rightSide[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(rightSide.first.dx, rightSide.first.dy);

    final startR = radiusForPoint(
      pts.first,
      baseWidth: stroke.width,
      toolType: stroke.toolType,
    );
    path.arcToPoint(
      leftSide.first,
      radius: Radius.circular(startR),
      clockwise: true,
    );
    path.close();

    if (pts.length == 2 &&
        (Offset(pts[0].x, pts[0].y) - lastPt).distance < 0.5) {
      path.addOval(Rect.fromCircle(center: lastPt, radius: startR));
    }

    return path;
  }

  /// Builds a centerline [Path] (ideal for highlighter and exact geometric shapes).
  static Path buildCenterlinePath(List<StrokePoint> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.x, pts.first.y);
    if (pts.length == 2) {
      path.lineTo(pts[1].x, pts[1].y);
      return path;
    }
    for (int i = 1; i < pts.length - 1; i++) {
      final midX = (pts[i].x + pts[i + 1].x) * 0.5;
      final midY = (pts[i].y + pts[i + 1].y) * 0.5;
      path.quadraticBezierTo(pts[i].x, pts[i].y, midX, midY);
    }
    path.lineTo(pts.last.x, pts.last.y);
    return path;
  }

  // ===========================================================================
  // SCRIBBLE-TO-ERASE (Huawei Notes & GoodNotes 6 Zig-Zag Erase)
  // ===========================================================================

  /// Detects a rapid back-and-forth scribble/scratch-out gesture used to erase
  /// strokes underneath it without switching to the eraser tool.
  /// Tuned for real MatePad 11.5"S handwriting: requires >= 3 reversals > 130 deg
  /// (4 back-and-forth passes) with segment length >= 16px and overlap ratio >= 1.85x bounding-box diagonal
  /// (reliably erases intentional 4-pass scribbles while rejecting 1-3 pass handwriting waves).
  static bool isScribbleGesture(List<StrokePoint> rawPoints) {
    if (rawPoints.length < 8) return false;

    final bounds = _boundingBox(rawPoints);
    final diag = math.sqrt(
      bounds.width * bounds.width + bounds.height * bounds.height,
    );
    if (diag < 18.0) return false;

    final totalLen = _polylineLength(rawPoints);
    if (totalLen < diag * 1.85) return false;

    final simplified = _douglasPeucker(
      rawPoints,
      epsilon: math.max(3.5, diag * 0.045),
    );
    if (simplified.length < 5) return false;

    // cos(130 deg) ≈ -0.6428 -> use -0.65
    const double minReversalCos = -0.65;
    int sharpReversals = 0;
    for (int i = 1; i < simplified.length - 1; i++) {
      final a = simplified[i - 1];
      final b = simplified[i];
      final c = simplified[i + 1];
      final v1x = b.x - a.x;
      final v1y = b.y - a.y;
      final v2x = c.x - b.x;
      final v2y = c.y - b.y;
      final l1 = math.sqrt(v1x * v1x + v1y * v1y);
      final l2 = math.sqrt(v2x * v2x + v2y * v2y);
      if (l1 < 16.0 || l2 < 16.0) continue;
      final cosAngle = ((v1x * v2x + v1y * v2y) / (l1 * l2)).clamp(-1.0, 1.0);
      if (cosAngle < minReversalCos) {
        sharpReversals++;
      }
    }

    return sharpReversals >= 3;
  }

  /// Alias for [isScribbleGesture] returning the intersected stroke IDs when
  /// [scribblePoints] satisfies the scribble-to-erase threshold.
  static Set<String> detectScribbleToErase(
    List<Stroke> strokes,
    List<StrokePoint> scribblePoints,
  ) {
    if (!isScribbleGesture(scribblePoints)) return const {};
    return findStrokesIntersectedByScribble(strokes, scribblePoints);
  }

  /// Returns IDs of existing strokes intersected by a scribble-to-erase gesture.
  static Set<String> findStrokesIntersectedByScribble(
    List<Stroke> strokes,
    List<StrokePoint> scribblePoints,
  ) {
    if (scribblePoints.isEmpty || strokes.isEmpty) return const {};
    final scribbleBounds = _boundingBox(scribblePoints).inflate(12.0);
    final hitIds = <String>{};

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final sBounds = _boundingBox(stroke.points);
      if (!scribbleBounds.overlaps(sBounds)) continue;

      // Check actual proximity between scribble points and stroke
      for (int i = 0; i < scribblePoints.length; i += 2) {
        final pt = Offset(scribblePoints[i].x, scribblePoints[i].y);
        if (hitTestStroke(stroke, pt, tolerance: 14.0)) {
          hitIds.add(stroke.id);
          break;
        }
      }
    }

    return hitIds;
  }

  // ===========================================================================
  // AUTO SHAPE RECOGNITION (Line, Circle/Ellipse, Triangle, Rectangle, Hexagon)
  // ===========================================================================

  static ShapeRecognitionResult recognizeShape(List<StrokePoint> rawPoints) {
    if (rawPoints.length < 4) {
      return ShapeRecognitionResult(
        shapeType: ShapeType.none,
        snappedPoints: rawPoints,
      );
    }

    final double totalLength = _polylineLength(rawPoints);
    if (totalLength < 24.0) {
      return ShapeRecognitionResult(
        shapeType: ShapeType.none,
        snappedPoints: rawPoints,
      );
    }

    final bounds = _boundingBox(rawPoints);
    final diag = math.sqrt(
      bounds.width * bounds.width + bounds.height * bounds.height,
    );
    if (diag < 18.0) {
      return ShapeRecognitionResult(
        shapeType: ShapeType.none,
        snappedPoints: rawPoints,
      );
    }

    final start = rawPoints.first;
    final end = rawPoints.last;
    final startEndDist = _dist(start, end);

    // 1. Straight Line FIRST (strict open-line check)
    if (startEndDist >= totalLength * 0.86) {
      double maxDev = 0.0;
      for (final p in rawPoints) {
        final d = _pointToLineDistance(p, start, end);
        if (d > maxDev) maxDev = d;
      }
      if (maxDev <= math.max(12.0, startEndDist * 0.08)) {
        final snappedEnd = _snapLineEndpoint(start, end);
        return ShapeRecognitionResult(
          shapeType: ShapeType.line,
          snappedPoints: _generateLinePoints(start, snappedEnd),
        );
      }
    }

    // 2. Closed Shapes ONLY if the stroke actually closes
    final bool isClosed = startEndDist <= math.max(44.0, diag * 0.34);
    if (!isClosed) {
      return ShapeRecognitionResult(
        shapeType: ShapeType.none,
        snappedPoints: rawPoints,
      );
    }

    final center = Offset(bounds.center.dx, bounds.center.dy);
    double sumR = 0.0;
    for (final p in rawPoints) {
      sumR += math.sqrt(
        (p.x - center.dx) * (p.x - center.dx) +
            (p.y - center.dy) * (p.y - center.dy),
      );
    }
    final meanR = sumR / rawPoints.length;
    if (meanR < 8.0) {
      return ShapeRecognitionResult(
        shapeType: ShapeType.none,
        snappedPoints: rawPoints,
      );
    }

    final closedLoop = <StrokePoint>[...rawPoints, rawPoints.first];
    final simplified = _douglasPeucker(
      closedLoop,
      epsilon: math.max(6.0, diag * 0.048),
    );
    final vertices = simplified.length > 1 &&
            _dist(simplified.first, simplified.last) < diag * 0.14
        ? simplified.sublist(0, simplified.length - 1)
        : simplified;

    // Compute filled polygon area ratio (shoelace / bounding-box area)
    final double boxArea = math.max(1.0, bounds.width * bounds.height);
    final double areaRatio = _polygonArea(rawPoints) / boxArea;

    // Evaluate normalized RMS fit error for every eligible candidate and pick the BEST
    ShapeType bestType = ShapeType.none;
    double bestError = 0.21;
    List<StrokePoint>? bestPoints;

    // Candidate A: Triangle (areaRatio ∈ [0.34, 0.64] or 3 DP vertices, angle-sorted)
    if (vertices.length == 3 ||
        (areaRatio >= 0.34 && areaRatio <= 0.64 && vertices.length >= 3 && vertices.length <= 5)) {
      final triVertsRaw = vertices.length == 3
          ? vertices
          : _pickThreeExtremeVertices(vertices);
      final sortedTri = _sortVerticesByAngle(triVertsRaw, center);
      final triErr = _polygonRmsError(
        rawPoints,
        sortedTri.map((v) => Offset(v.x, v.y)).toList(),
        meanR,
      );
      if (triErr < 0.21 && triErr < bestError) {
        bestError = triErr;
        bestType = ShapeType.triangle;
        bestPoints = _generateCleanPolygon(sortedTri);
      }
    }

    // Candidate B: Square / Rectangle (works even with slightly rounded hand-drawn corners!)
    final bool rectAreaOk = areaRatio >= 0.74 && areaRatio <= 1.08;
    if (rectAreaOk || vertices.length == 4) {
      final double aspect =
          bounds.height > 1 ? bounds.width / bounds.height : 1.0;
      final bool isSquare = aspect >= 0.85 && aspect <= 1.18;
      final double halfW = isSquare
          ? (bounds.width + bounds.height) * 0.25
          : bounds.width * 0.5;
      final double halfH = isSquare ? halfW : bounds.height * 0.5;
      final snapBounds = Rect.fromCenter(
        center: center,
        width: halfW * 2,
        height: halfH * 2,
      );
      final rectVerts = [
        Offset(snapBounds.left, snapBounds.top),
        Offset(snapBounds.right, snapBounds.top),
        Offset(snapBounds.right, snapBounds.bottom),
        Offset(snapBounds.left, snapBounds.bottom),
      ];
      final rectErr = _polygonRmsError(rawPoints, rectVerts, meanR);
      if (rectErr < 0.19 && rectErr < bestError) {
        bestError = rectErr;
        bestType = ShapeType.rectangle;
        bestPoints = _generateCleanPolygon([
          StrokePoint(x: snapBounds.left, y: snapBounds.top, pressure: 0.6),
          StrokePoint(x: snapBounds.right, y: snapBounds.top, pressure: 0.6),
          StrokePoint(x: snapBounds.right, y: snapBounds.bottom, pressure: 0.6),
          StrokePoint(x: snapBounds.left, y: snapBounds.bottom, pressure: 0.6),
        ]);
      }
    }

    // Candidate C: Circle / Oval-Ellipse (exact mathematical ellipse, lower error wins over rect)
    final double ellipseErr = _circleEllipseRmsError(rawPoints, bounds);
    if (ellipseErr < 0.18 && ellipseErr < bestError) {
      final double aspect =
          bounds.height > 1 ? bounds.width / bounds.height : 1.0;
      final bool isCircle = aspect > 0.80 && aspect < 1.25;
      final double rx = isCircle
          ? (bounds.width + bounds.height) * 0.25
          : bounds.width * 0.5;
      final double ry = isCircle ? rx : bounds.height * 0.5;
      bestError = ellipseErr;
      bestType = ShapeType.circle;
      bestPoints = _generateEllipsePoints(center, rx, ry);
    }

    if (bestType != ShapeType.none && bestPoints != null) {
      return ShapeRecognitionResult(
        shapeType: bestType,
        snappedPoints: bestPoints,
      );
    }

    return ShapeRecognitionResult(
      shapeType: ShapeType.none,
      snappedPoints: rawPoints,
    );
  }

  /// Shoelace formula for absolute polygon area.
  static double _polygonArea(List<StrokePoint> pts) {
    if (pts.length < 3) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      sum += (a.x * b.y) - (b.x * a.y);
    }
    return sum.abs() * 0.5;
  }

  /// Selects the 3 vertices forming the largest-area triangle from a small vertex set.
  static List<StrokePoint> _pickThreeExtremeVertices(List<StrokePoint> verts) {
    if (verts.length <= 3) return verts;
    double bestArea = -1.0;
    List<StrokePoint> best = verts.sublist(0, 3);
    for (int i = 0; i < verts.length; i++) {
      for (int j = i + 1; j < verts.length; j++) {
        for (int k = j + 1; k < verts.length; k++) {
          final a = verts[i];
          final b = verts[j];
          final c = verts[k];
          final area = ((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))
              .abs();
          if (area > bestArea) {
            bestArea = area;
            best = [a, b, c];
          }
        }
      }
    }
    return best;
  }

  static List<StrokePoint> _sortVerticesByAngle(
    List<StrokePoint> verts,
    Offset center,
  ) {
    final copy = List<StrokePoint>.from(verts);
    copy.sort((a, b) {
      final angA = math.atan2(a.y - center.dy, a.x - center.dx);
      final angB = math.atan2(b.y - center.dy, b.x - center.dx);
      return angA.compareTo(angB);
    });
    return copy;
  }

  static double _polygonRmsError(
    List<StrokePoint> rawPoints,
    List<Offset> polyVerts,
    double normScale,
  ) {
    if (polyVerts.length < 3 || normScale < 1.0) return 1.0;
    double sumSq = 0.0;
    for (final p in rawPoints) {
      final pt = Offset(p.x, p.y);
      double minD = double.infinity;
      for (int i = 0; i < polyVerts.length; i++) {
        final d = _pointToSegmentDistance(
          pt,
          polyVerts[i],
          polyVerts[(i + 1) % polyVerts.length],
        );
        if (d < minD) minD = d;
      }
      final norm = minD / normScale;
      sumSq += norm * norm;
    }
    return math.sqrt(sumSq / rawPoints.length);
  }

  static double _circleEllipseRmsError(List<StrokePoint> points, Rect bounds) {
    final rx = math.max(1.0, bounds.width * 0.5);
    final ry = math.max(1.0, bounds.height * 0.5);
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;

    double sumSq = 0.0;
    for (final p in points) {
      final nx = (p.x - cx) / rx;
      final ny = (p.y - cy) / ry;
      final err = math.sqrt(nx * nx + ny * ny) - 1.0;
      sumSq += err * err;
    }
    return math.sqrt(sumSq / points.length);
  }

  /// Emits clean, non-crossing polygon vertices closed cleanly to [vertices.first].
  static List<StrokePoint> _generateCleanPolygon(List<StrokePoint> vertices) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final v in vertices)
        StrokePoint(x: v.x, y: v.y, pressure: 0.6, tilt: 0.0, timestamp: now),
      StrokePoint(
        x: vertices.first.x,
        y: vertices.first.y,
        pressure: 0.6,
        tilt: 0.0,
        timestamp: now,
      ),
    ];
  }

  static StrokePoint _snapLineEndpoint(StrokePoint start, StrokePoint end) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    final angle = math.atan2(dy, dx);
    const snapTolerance = 6.0 * math.pi / 180.0;

    final snapAngles = <double>[
      0,
      math.pi / 6,
      math.pi / 4,
      math.pi / 3,
      math.pi / 2,
      2 * math.pi / 3,
      3 * math.pi / 4,
      5 * math.pi / 6,
      math.pi,
      -math.pi,
      -5 * math.pi / 6,
      -3 * math.pi / 4,
      -2 * math.pi / 3,
      -math.pi / 2,
      -math.pi / 3,
      -math.pi / 4,
      -math.pi / 6,
    ];

    for (final target in snapAngles) {
      if ((angle - target).abs() < snapTolerance) {
        return StrokePoint(
          x: start.x + dist * math.cos(target),
          y: start.y + dist * math.sin(target),
          pressure: end.pressure,
          tilt: end.tilt,
          timestamp: end.timestamp,
        );
      }
    }
    return end;
  }

  static List<StrokePoint> _generateLinePoints(StrokePoint a, StrokePoint b) {
    const steps = 12;
    return List.generate(steps + 1, (i) {
      final t = i / steps;
      return StrokePoint(
        x: a.x + (b.x - a.x) * t,
        y: a.y + (b.y - a.y) * t,
        pressure: 0.6,
        tilt: 0.0,
        timestamp: a.timestamp,
      );
    });
  }

  static List<StrokePoint> _generateEllipsePoints(
    Offset center,
    double rx,
    double ry, {
    int segments = 64,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return List.generate(segments + 1, (i) {
      final theta = (i / segments) * 2 * math.pi;
      return StrokePoint(
        x: center.dx + rx * math.cos(theta),
        y: center.dy + ry * math.sin(theta),
        pressure: 0.6,
        tilt: 0.0,
        timestamp: now,
      );
    });
  }

  static List<StrokePoint> _generatePolygonPoints(List<StrokePoint> vertices) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <StrokePoint>[];
    for (int i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      const sub = 6;
      for (int s = 0; s < sub; s++) {
        final t = s / sub;
        out.add(StrokePoint(
          x: a.x + (b.x - a.x) * t,
          y: a.y + (b.y - a.y) * t,
          pressure: 0.6,
          tilt: 0.0,
          timestamp: now,
        ));
      }
    }
    out.add(StrokePoint(
      x: vertices.first.x,
      y: vertices.first.y,
      pressure: 0.6,
      tilt: 0.0,
      timestamp: now,
    ));
    return out;
  }

  static List<StrokePoint>? _trySnapRectangle(
    List<StrokePoint> vertices,
    Rect bounds,
  ) {
    if (vertices.length != 4) return null;
    int rightAngles = 0;
    for (int i = 0; i < 4; i++) {
      final prev = vertices[(i + 3) % 4];
      final curr = vertices[i];
      final next = vertices[(i + 1) % 4];
      final v1 = Offset(prev.x - curr.x, prev.y - curr.y);
      final v2 = Offset(next.x - curr.x, next.y - curr.y);
      if (v1.distance < 1 || v2.distance < 1) return null;
      final cosA = ((v1.dx * v2.dx + v1.dy * v2.dy) / (v1.distance * v2.distance))
          .clamp(-1.0, 1.0);
      final deg = math.acos(cosA) * 180 / math.pi;
      if ((deg - 90.0).abs() < 28.0) rightAngles++;
    }
    if (rightAngles < 3) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final rectVerts = [
      StrokePoint(x: bounds.left, y: bounds.top, pressure: 0.6, tilt: 0, timestamp: now),
      StrokePoint(x: bounds.right, y: bounds.top, pressure: 0.6, tilt: 0, timestamp: now),
      StrokePoint(x: bounds.right, y: bounds.bottom, pressure: 0.6, tilt: 0, timestamp: now),
      StrokePoint(x: bounds.left, y: bounds.bottom, pressure: 0.6, tilt: 0, timestamp: now),
    ];
    return _generateCleanPolygon(rectVerts);
  }

  static double _regularHexagonError(
    List<StrokePoint> points,
    Offset center,
    double radius,
  ) {
    if (radius < 1.0) return 1.0;
    double bestError = double.infinity;

    for (final baseAngle in [-math.pi / 6, 0.0]) {
      final hexVerts = List.generate(6, (i) {
        final a = baseAngle + i * math.pi / 3;
        return Offset(
          center.dx + radius * math.cos(a),
          center.dy + radius * math.sin(a),
        );
      });

      double sumErr = 0.0;
      for (final p in points) {
        final pt = Offset(p.x, p.y);
        double minEdgeDist = double.infinity;
        for (int i = 0; i < 6; i++) {
          final d = _pointToSegmentDistance(pt, hexVerts[i], hexVerts[(i + 1) % 6]);
          if (d < minEdgeDist) minEdgeDist = d;
        }
        sumErr += minEdgeDist / radius;
      }
      final avgErr = sumErr / points.length;
      if (avgErr < bestError) bestError = avgErr;
    }

    return bestError;
  }

  static List<StrokePoint> _generateRegularHexagon(
    List<StrokePoint> rawPoints,
    Offset center,
    double radius,
  ) {
    double bestBaseAngle = -math.pi / 6;
    double bestError = double.infinity;

    for (final baseAngle in [-math.pi / 6, 0.0]) {
      final hexVerts = List.generate(6, (i) {
        final a = baseAngle + i * math.pi / 3;
        return Offset(
          center.dx + radius * math.cos(a),
          center.dy + radius * math.sin(a),
        );
      });
      double err = 0.0;
      for (final p in rawPoints) {
        final pt = Offset(p.x, p.y);
        double minD = double.infinity;
        for (int i = 0; i < 6; i++) {
          final d = _pointToSegmentDistance(pt, hexVerts[i], hexVerts[(i + 1) % 6]);
          if (d < minD) minD = d;
        }
        err += minD;
      }
      if (err < bestError) {
        bestError = err;
        bestBaseAngle = baseAngle;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final vertices = List.generate(6, (i) {
      final a = bestBaseAngle + i * math.pi / 3;
      return StrokePoint(
        x: center.dx + radius * math.cos(a),
        y: center.dy + radius * math.sin(a),
        pressure: 0.6,
        tilt: 0.0,
        timestamp: now,
      );
    });
    return _generateCleanPolygon(vertices);
  }

  static double _circleEllipseError(List<StrokePoint> points, Rect bounds) {
    final rx = math.max(1.0, bounds.width * 0.5);
    final ry = math.max(1.0, bounds.height * 0.5);
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;

    double sumErr = 0.0;
    for (final p in points) {
      final nx = (p.x - cx) / rx;
      final ny = (p.y - cy) / ry;
      final r = math.sqrt(nx * nx + ny * ny);
      sumErr += (r - 1.0).abs();
    }
    return sumErr / points.length;
  }

  // ===========================================================================
  // GEOMETRY UTILITIES
  // ===========================================================================

  static double _dist(StrokePoint a, StrokePoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _polylineLength(List<StrokePoint> pts) {
    double total = 0.0;
    for (int i = 1; i < pts.length; i++) {
      total += _dist(pts[i - 1], pts[i]);
    }
    return total;
  }

  static Rect _boundingBox(List<StrokePoint> pts) {
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;
    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static double _pointToLineDistance(
    StrokePoint p,
    StrokePoint a,
    StrokePoint b,
  ) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 0.0001) return _dist(p, a);
    return ((dy * p.x - dx * p.y + b.x * a.y - b.y * a.x).abs()) /
        math.sqrt(lenSq);
  }

  static double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 0.0001) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq)
        .clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - proj).distance;
  }

  static List<StrokePoint> _douglasPeucker(
    List<StrokePoint> pts, {
    required double epsilon,
  }) {
    if (pts.length <= 2) return pts;

    double maxDist = 0.0;
    int index = 0;
    final first = pts.first;
    final last = pts.last;

    for (int i = 1; i < pts.length - 1; i++) {
      final d = _pointToLineDistance(pts[i], first, last);
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _douglasPeucker(pts.sublist(0, index + 1), epsilon: epsilon);
      final right = _douglasPeucker(pts.sublist(index), epsilon: epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [first, last];
    }
  }

  /// Hit-test whether [point] is within [tolerance] pixels of [stroke].
  static bool hitTestStroke(
    Stroke stroke,
    Offset point, {
    double tolerance = 12.0,
  }) {
    final pts = stroke.points;
    if (pts.isEmpty) return false;
    final effectiveTol = tolerance + stroke.width * 0.5;
    if (pts.length == 1) {
      return (Offset(pts.first.x, pts.first.y) - point).distance <= effectiveTol;
    }
    for (int i = 0; i < pts.length - 1; i++) {
      final a = Offset(pts[i].x, pts[i].y);
      final b = Offset(pts[i + 1].x, pts[i + 1].y);
      if (_pointToSegmentDistance(point, a, b) <= effectiveTol) {
        return true;
      }
    }
    return false;
  }

  /// Precision eraser: splits a stroke by removing points within [eraserRadius]
  /// of [eraserCenter], returning 0, 1, or multiple remaining sub-strokes.
  static List<Stroke> precisionEraseStroke(
    Stroke stroke,
    Offset eraserCenter,
    double eraserRadius, {
    required String Function() idGenerator,
  }) {
    final pts = stroke.points;
    if (pts.isEmpty) return const [];

    final segments = <List<StrokePoint>>[];
    var current = <StrokePoint>[];
    final rSq = eraserRadius * eraserRadius;

    for (final p in pts) {
      final dx = p.x - eraserCenter.dx;
      final dy = p.y - eraserCenter.dy;
      if (dx * dx + dy * dy > rSq) {
        current.add(p);
      } else {
        if (current.length >= 2) {
          segments.add(current);
        }
        current = <StrokePoint>[];
      }
    }
    if (current.length >= 2) {
      segments.add(current);
    }

    if (segments.length == 1 && segments.first.length == pts.length) {
      return [stroke];
    }

    return segments
        .map((seg) => stroke.copyWith(
              id: idGenerator(),
              points: seg,
              shapeType: ShapeType.none,
            ))
        .toList();
  }
}
