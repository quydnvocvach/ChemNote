import 'dart:io';
import 'dart:ui' as ui;

import 'package:chemnote/core/models/drawing_elements.dart';
import 'package:chemnote/core/models/note_page.dart';
import 'package:chemnote/core/models/notebook.dart';
import 'package:chemnote/core/providers/app_state.dart';
import 'package:chemnote/core/storage/local_storage_service.dart';
import 'package:chemnote/features/canvas/canvas_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CanvasPainter stroke bounds & width-batched geometry cache', () {
    test('strokeBounds computes exact padded AABB and caches per Stroke', () {
      const emptyStroke = Stroke(
        id: 'empty',
        toolType: ToolType.fountainPen,
        colorValue: 0xFF000000,
        width: 4.0,
        points: [],
      );
      expect(CanvasPainter.strokeBounds(emptyStroke), Rect.zero);

      const stroke = Stroke(
        id: 's1',
        toolType: ToolType.fountainPen,
        colorValue: 0xFF1E3A8A,
        width: 4.0,
        points: [
          StrokePoint(x: 10.0, y: 20.0, pressure: 0.4, timestamp: 100),
          StrokePoint(x: 30.0, y: 50.0, pressure: 0.7, timestamp: 116),
          StrokePoint(x: 50.0, y: 80.0, pressure: 0.9, timestamp: 132),
        ],
      );

      final first = CanvasPainter.strokeBounds(stroke);
      final second = CanvasPainter.strokeBounds(stroke);
      expect(first, const Rect.fromLTRB(8.0, 18.0, 52.0, 82.0));
      expect(identical(first, second), isTrue);
    });

    test('renders width-batched fountain, ballpoint, highlighter, and pencil strokes cleanly', () {
      final fountainPoints = List<StrokePoint>.generate(
        24,
        (i) => StrokePoint(
          x: 20.0 + i * 8.0,
          y: 40.0 + (i % 5) * 6.0,
          pressure: 0.25 + (i / 24.0) * 0.7,
          timestamp: 1000 + i * 8,
        ),
      );
      final page = NotePage(
        id: 'p1',
        index: 0,
        strokes: [
          Stroke(
            id: 'f1',
            toolType: ToolType.fountainPen,
            colorValue: 0xFF111827,
            width: 3.5,
            points: fountainPoints,
          ),
          Stroke(
            id: 'b1',
            toolType: ToolType.ballpointPen,
            colorValue: 0xFF1D4ED8,
            width: 2.2,
            points: fountainPoints,
          ),
          Stroke(
            id: 'h1',
            toolType: ToolType.highlighter,
            colorValue: 0xFFFDE047,
            width: 18.0,
            points: fountainPoints,
          ),
          Stroke(
            id: 'p1',
            toolType: ToolType.pencil,
            colorValue: 0xFF4B5563,
            width: 2.5,
            points: fountainPoints,
          ),
        ],
        updatedAt: DateTime.utc(2026, 11, 25),
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final notifier = ValueNotifier<int>(1050);
      final painter = CanvasPainter(
        page: page,
        playingAudioTimeMsNotifier: notifier,
      );
      // Paint twice to exercise both uncached build and Expando cached replay
      painter.paint(canvas, const Size(794, 1123));
      painter.paint(canvas, const Size(794, 1123));
      final picture = recorder.endRecording();
      picture.dispose();
      notifier.dispose();
    });
  });

  group('LocalStorageService Isolate serialization roundtrip', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('chemnote_perf_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveNotebook and loadNotebooks preserve small & large notebooks via Isolate compute', () async {
      final storage = LocalStorageService(baseDirectory: tempDir);
      final heavyPoints = List<StrokePoint>.generate(
        900,
        (i) => StrokePoint(
          x: (i % 500).toDouble(),
          y: (i * 1.5),
          pressure: 0.6,
          tilt: 0.1,
          timestamp: 5000 + i * 7,
        ),
      );

      final smallNb = Notebook(
        id: 'nb-small',
        title: 'Sổ nhỏ',
        createdAt: DateTime.utc(2026, 11, 20),
        updatedAt: DateTime.utc(2026, 11, 24),
        pages: [
          NotePage(
            id: 'p-s1',
            index: 0,
            updatedAt: DateTime.utc(2026, 11, 24),
          ),
        ],
      );

      final largeNb = Notebook(
        id: 'nb-large',
        title: 'Sổ Hóa lớn',
        createdAt: DateTime.utc(2026, 11, 21),
        updatedAt: DateTime.utc(2026, 11, 25),
        pages: [
          NotePage(
            id: 'p-l1',
            index: 0,
            strokes: [
              Stroke(
                id: 'st-heavy',
                toolType: ToolType.fountainPen,
                colorValue: 0xFF0F172A,
                width: 3.0,
                points: heavyPoints,
              ),
            ],
            updatedAt: DateTime.utc(2026, 11, 25),
          ),
        ],
      );

      await storage.saveNotebook(smallNb);
      await storage.saveNotebook(largeNb);

      final loaded = await storage.loadNotebooks();
      expect(loaded.length, 2);
      expect(loaded.first.id, 'nb-large');
      expect(loaded.first.pages.first.strokes.first.points.length, 900);
      expect(loaded.last.id, 'nb-small');
    });

    test('AppState supports insertPagesAt, reorderPages, toggleBookmark & deletePages', () async {
      final storage = LocalStorageService(baseDirectory: tempDir);
      final appState = AppState(storage: storage);
      final now = DateTime.utc(2026, 11, 25);
      final nb = await appState.createNotebook(
        title: 'Sổ thử trang',
        initialPages: [
          NotePage(id: 'p1', index: 0, title: 'T1', updatedAt: now),
          NotePage(id: 'p2', index: 1, title: 'T2', updatedAt: now),
          NotePage(id: 'p3', index: 2, title: 'T3', updatedAt: now),
        ],
      );

      // Insert duplicated page after p1 (index 1)
      await appState.insertPagesAt(
        nb.id,
        [NotePage(id: 'p1_copy', index: 0, title: 'T1 Copy', updatedAt: now)],
        insertIndex: 1,
      );
      var updated = appState.getNotebookById(nb.id)!;
      expect(updated.pages.map((p) => p.id).toList(), ['p1', 'p1_copy', 'p2', 'p3']);
      expect(updated.pages.map((p) => p.index).toList(), [0, 1, 2, 3]);

      // Reorder p3 (index 3) -> index 0
      await appState.reorderPages(nb.id, 3, 0);
      updated = appState.getNotebookById(nb.id)!;
      expect(updated.pages.map((p) => p.id).toList(), ['p3', 'p1', 'p1_copy', 'p2']);

      // Toggle bookmark on p1
      await appState.toggleBookmark(nb.id, 'p1');
      updated = appState.getNotebookById(nb.id)!;
      expect(updated.pages[1].isBookmarked, isTrue);

      // Batch delete p1_copy & p2
      await appState.deletePages(nb.id, {'p1_copy', 'p2'});
      updated = appState.getNotebookById(nb.id)!;
      expect(updated.pages.map((p) => p.id).toList(), ['p3', 'p1']);
      expect(updated.pages.map((p) => p.index).toList(), [0, 1]);

      // Deleting all pages preserves at least 1 page safely
      await appState.deletePages(nb.id, {'p3', 'p1'});
      updated = appState.getNotebookById(nb.id)!;
      expect(updated.pages.length, 1);
    });
  });
}
