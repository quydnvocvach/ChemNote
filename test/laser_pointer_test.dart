import 'package:chemnote/features/canvas/pro_tools_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LaserPointerController Huawei Notes behavior', () {
    test('holds multi-stroke line formula active until pause expires after release', () async {
      final ctrl = LaserPointerController();
      addTearDown(ctrl.dispose);

      expect(ctrl.mode, LaserPointerMode.line);
      expect(ctrl.color, LaserPointerController.presetColors.first);

      // Stroke 1 ("H")
      ctrl.beginStroke(const Offset(10, 10), pageId: 'p1');
      ctrl.addPoint(const Offset(10, 40), pageId: 'p1');
      ctrl.endStroke();

      // Stroke 2 immediately after ("2") keeps stroke 1 visible
      ctrl.beginStroke(const Offset(30, 20), pageId: 'p1');
      ctrl.addPoint(const Offset(45, 40), pageId: 'p1');
      expect(ctrl.strokes.length, 2);
      expect(ctrl.lastGroupReleaseMs, isNull);

      ctrl.endStroke();
      expect(ctrl.lastGroupReleaseMs, isNotNull);
      expect(ctrl.strokes.length, 2);

      // Still held solid well inside holdBeforeFadeMs
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(ctrl.strokes.length, 2);
      expect(ctrl.hasPoints, isTrue);

      ctrl.clear();
      expect(ctrl.strokes, isEmpty);
      expect(ctrl.hasPoints, isFalse);
    });

    test('dot spotlight mode tracks cursor and switches modes & colors cleanly', () async {
      final ctrl = LaserPointerController();
      addTearDown(ctrl.dispose);

      ctrl.setMode(LaserPointerMode.dot);
      expect(ctrl.mode, LaserPointerMode.dot);

      final green = LaserPointerController.presetColors[1];
      ctrl.setColor(green);
      expect(ctrl.color, green);

      ctrl.beginStroke(const Offset(120, 80), pageId: 'p1');
      ctrl.addPoint(const Offset(160, 100), pageId: 'p1');
      expect(ctrl.spotPosition, const Offset(160, 100));
      expect(ctrl.isSpotActive, isTrue);
      expect(ctrl.strokes, isEmpty);

      ctrl.endStroke();
      expect(ctrl.isSpotActive, isFalse);
      expect(ctrl.spotReleasedAtMs, isNotNull);

      await Future<void>.delayed(
        const Duration(milliseconds: LaserPointerController.dotFadeOutMs + 80),
      );
      expect(ctrl.spotPosition, isNull);
    });
  });
}
