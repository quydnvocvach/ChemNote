import 'dart:math' as math;

import 'package:chemnote/core/models/drawing_elements.dart';
import 'package:chemnote/features/canvas/stroke_engine.dart';
import 'package:flutter_test/flutter_test.dart';

List<StrokePoint> _samplePolygon(List<(double, double)> vertices, {int stepsPerEdge = 6}) {
  final pts = <StrokePoint>[];
  int ts = 1000;
  for (int i = 0; i < vertices.length; i++) {
    final (x1, y1) = vertices[i];
    final (x2, y2) = vertices[(i + 1) % vertices.length];
    for (int s = 0; s < stepsPerEdge; s++) {
      final t = s / stepsPerEdge;
      pts.add(StrokePoint(
        x: x1 + (x2 - x1) * t,
        y: y1 + (y2 - y1) * t,
        pressure: 0.6,
        timestamp: ts,
      ));
      ts += 16;
    }
  }
  final (fx, fy) = vertices.first;
  pts.add(StrokePoint(x: fx, y: fy, pressure: 0.6, timestamp: ts));
  return pts;
}

void main() {
  group('StrokeEngine Handwriting Smoothing & Neatening', () {
    test('reduces high-frequency jitter while preserving endpoints', () {
      // Simulate a shaky horizontal stroke with alternating +/- 3px tremor
      final raw = List.generate(20, (i) {
        final jitter = (i % 2 == 0) ? 3.0 : -3.0;
        return StrokePoint(
          x: i * 10.0,
          y: 100.0 + (i == 0 || i == 19 ? 0.0 : jitter),
          pressure: 0.6,
          timestamp: 1000 + i * 16,
        );
      });

      final smoothed = StrokeEngine.smoothAndNeatenStroke(
        raw,
        stabilization: 0.7,
        autoNeaten: true,
        toolType: ToolType.fountainPen,
      );

      expect(smoothed.length, greaterThanOrEqualTo(raw.length));
      // Verify vertical deviation from y = 100 is substantially reduced
      final maxRawDev = raw.map((p) => (p.y - 100.0).abs()).reduce(math.max);
      final maxSmoothDev =
          smoothed.map((p) => (p.y - 100.0).abs()).reduce(math.max);
      expect(maxSmoothDev, lessThan(maxRawDev));
    });

    test('live jitter filter skips micro-movements and accepts real steps', () {
      final current = <StrokePoint>[
        const StrokePoint(x: 50, y: 50, pressure: 0.5, timestamp: 1000),
      ];

      final micro = const StrokePoint(x: 50.4, y: 50.3, pressure: 0.5, timestamp: 1005);
      expect(StrokeEngine.filterLivePoint(micro, current, stabilization: 0.55), isNull);

      final realMove = const StrokePoint(x: 65.0, y: 50.0, pressure: 0.7, timestamp: 1020);
      final accepted = StrokeEngine.filterLivePoint(realMove, current, stabilization: 0.55);
      expect(accepted, isNotNull);
      expect(accepted!.x, greaterThan(50.0));
      expect(accepted.x, lessThan(65.0));
    });
  });

  group('StrokeEngine Auto Shape Recognition', () {
    test('recognizes a straight line', () {
      final raw = List.generate(15, (i) {
        final wobble = math.sin(i * 0.7) * 1.5;
        return StrokePoint(
          x: 20.0 + i * 15.0,
          y: 100.0 + wobble,
          pressure: 0.6,
          timestamp: 1000 + i * 16,
        );
      });

      final result = StrokeEngine.recognizeShape(raw);
      expect(result.recognized, isTrue);
      expect(result.shapeType, ShapeType.line);
      expect(result.snappedPoints.length, greaterThanOrEqualTo(2));
    });

    test('recognizes a circle', () {
      const cx = 200.0;
      const cy = 200.0;
      const r = 80.0;
      final raw = List.generate(48, (i) {
        final theta = (i / 47) * 2 * math.pi;
        return StrokePoint(
          x: cx + r * math.cos(theta),
          y: cy + r * math.sin(theta),
          pressure: 0.6,
          timestamp: 1000 + i * 16,
        );
      });

      final result = StrokeEngine.recognizeShape(raw);
      expect(result.recognized, isTrue);
      expect(result.shapeType, ShapeType.circle);
    });

    test('recognizes a rectangle', () {
      final raw = _samplePolygon([
        (100.0, 100.0),
        (300.0, 100.0),
        (300.0, 220.0),
        (100.0, 220.0),
      ]);

      final result = StrokeEngine.recognizeShape(raw);
      expect(result.recognized, isTrue);
      expect(result.shapeType, ShapeType.rectangle);
    });

    test('recognizes a triangle', () {
      final raw = _samplePolygon([
        (200.0, 80.0),
        (300.0, 250.0),
        (100.0, 250.0),
      ]);

      final result = StrokeEngine.recognizeShape(raw);
      expect(result.recognized, isTrue);
      expect(result.shapeType, ShapeType.triangle);
    });

    test('recognizes a regular hexagon (benzene ring)', () {
      const cx = 250.0;
      const cy = 250.0;
      const r = 90.0;
      final hexVerts = List.generate(6, (i) {
        final a = -math.pi / 6 + i * math.pi / 3;
        return (cx + r * math.cos(a), cy + r * math.sin(a));
      });
      final raw = _samplePolygon(hexVerts, stepsPerEdge: 8);

      final result = StrokeEngine.recognizeShape(raw);
      expect(result.recognized, isTrue);
      expect(result.shapeType, ShapeType.hexagon);
    });

    test('returns ShapeType.none for too-short strokes', () {
      const shortStroke = [
        StrokePoint(x: 10, y: 10),
        StrokePoint(x: 12, y: 11),
      ];
      final result = StrokeEngine.recognizeShape(shortStroke);
      expect(result.recognized, isFalse);
      expect(result.shapeType, ShapeType.none);
    });
  });

  group('StrokeEngine v2: M-Pencil 3 Pressure, Pencil Tilt & Scribble-to-Erase', () {
    test('M-Pencil 3 pressure curve responds smoothly to gamma', () {
      final low = StrokeEngine.applyMPencilPressureCurve(0.0);
      final midDefault = StrokeEngine.applyMPencilPressureCurve(0.5, gamma: 0.85);
      final midLinear = StrokeEngine.applyMPencilPressureCurve(0.5, gamma: 1.0);
      final high = StrokeEngine.applyMPencilPressureCurve(1.0);

      expect(low, closeTo(0.08, 0.001));
      expect(high, closeTo(1.0, 0.001));
      // Lower gamma produces fuller mid-pressure output for PaperMatte feel
      expect(midDefault, greaterThan(midLinear));
    });

    test('ToolType.pencil widens stroke radius when tilted', () {
      const upright = StrokePoint(x: 0, y: 0, pressure: 0.6, tilt: 0.05);
      const tilted = StrokePoint(x: 0, y: 0, pressure: 0.6, tilt: 1.0);

      final rUpright = StrokeEngine.radiusForPoint(
        upright,
        baseWidth: 3.0,
        toolType: ToolType.pencil,
      );
      final rTilted = StrokeEngine.radiusForPoint(
        tilted,
        baseWidth: 3.0,
        toolType: ToolType.pencil,
      );
      expect(rTilted, greaterThan(rUpright));
    });

    test('detects strict scribble-to-erase zig-zag (>=7 reversals) and ignores fast handwriting', () {
      // Create a 10-pass back-and-forth scribble (9 sharp reversals ~175 deg, ~120px segments)
      final scribble = <StrokePoint>[];
      int ts = 1000;
      const passes = 10;
      for (int pass = 0; pass < passes; pass++) {
        final xStart = (pass % 2 == 0) ? 100.0 : 220.0;
        final xEnd = (pass % 2 == 0) ? 220.0 : 100.0;
        final yStart = 80.0 + pass * 5.0;
        final yEnd = 80.0 + (pass + 1) * 5.0;
        final firstStep = pass == 0 ? 0 : 1;
        for (int s = firstStep; s <= 2; s++) {
          final t = s / 2.0;
          scribble.add(StrokePoint(
            x: xStart + (xEnd - xStart) * t,
            y: yStart + (yEnd - yStart) * t,
            pressure: 0.6,
            timestamp: ts,
          ));
          ts += 10;
        }
      }

      expect(StrokeEngine.isScribbleGesture(scribble), isTrue);

      // Short 3-pass cursive handwriting wave (only 2 reversals) must NOT trigger scribble-to-erase
      final shortWave = scribble.sublist(0, 7);
      expect(StrokeEngine.isScribbleGesture(shortWave), isFalse);

      // Straight line should NOT trigger scribble-to-erase
      final line = List.generate(
        12,
        (i) => StrokePoint(x: 10.0 + i * 15.0, y: 50.0, pressure: 0.6, timestamp: i * 16),
      );
      expect(StrokeEngine.isScribbleGesture(line), isFalse);

      const hitStroke = Stroke(
        id: 'stroke-hit',
        toolType: ToolType.fountainPen,
        colorValue: 0xFF111827,
        width: 2.5,
        points: [
          StrokePoint(x: 110, y: 105),
          StrokePoint(x: 170, y: 105),
        ],
      );
      const missStroke = Stroke(
        id: 'stroke-miss',
        toolType: ToolType.fountainPen,
        colorValue: 0xFF111827,
        width: 2.5,
        points: [
          StrokePoint(x: 400, y: 400),
          StrokePoint(x: 460, y: 420),
        ],
      );

      final erased = StrokeEngine.detectScribbleToErase(
        const [hitStroke, missStroke],
        scribble,
      );
      expect(erased, contains('stroke-hit'));
      expect(erased, isNot(contains('stroke-miss')));
    });
  });
}
