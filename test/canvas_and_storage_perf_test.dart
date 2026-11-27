import 'dart:io';
import 'dart:ui' as ui;

import 'package:chemnote/core/models/drawing_elements.dart';
import 'package:chemnote/core/models/folder.dart';
import 'package:chemnote/core/models/note_page.dart';
import 'package:chemnote/core/models/notebook.dart';
import 'package:chemnote/core/providers/app_state.dart';
import 'package:chemnote/core/storage/local_storage_service.dart';
import 'package:chemnote/features/canvas/canvas_painter.dart';
import 'package:chemnote/features/canvas/lasso_controller.dart';
import 'package:chemnote/features/canvas/paper_templates.dart';
import 'package:chemnote/features/canvas/stroke_engine.dart';
import 'package:chemnote/features/pdf/page_image_export_service.dart';
import 'package:chemnote/features/pdf/pdf_export_service.dart';
import 'package:chemnote/features/sync/google_auth_service.dart';
import 'package:chemnote/features/sync/google_drive_service.dart';
import 'package:chemnote/features/sync/sync_manager.dart';
import 'package:flutter/gestures.dart';
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

    test('default notebook/page uses sageRibbon white, persists import dir, and cleans pdf_pages/docx_media orphans', () async {
      final storage = LocalStorageService(baseDirectory: tempDir);
      final appState = AppState(storage: storage);
      addTearDown(appState.dispose);
      final defaultNb = await appState.createNotebook(title: 'Default Sage');
      expect(defaultNb.defaultTemplate, PaperTemplateType.sageRibbon);
      expect(defaultNb.defaultPaperColor, PaperColorType.white);
      expect(defaultNb.pages.first.templateType, PaperTemplateType.sageRibbon);
      expect(defaultNb.pages.first.paperColor, PaperColorType.white);

      appState.setDefaultImportDirectory('/storage/emulated/0/Download/ChemPDF');
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final reloaded = AppState(storage: storage);
      addTearDown(reloaded.dispose);
      await reloaded.loadAll();
      expect(reloaded.defaultImportDirectory, '/storage/emulated/0/Download/ChemPDF');

      // Prepare referenced & orphan files under pdf_pages and docx_media
      final rootDir = await storage.getRootDirectory();
      final pdfDir = Directory('${rootDir.path}/pdf_pages/b1')..createSync(recursive: true);
      final docxDir = Directory('${rootDir.path}/docx_media/d1')..createSync(recursive: true);
      final keptPdf = File('${pdfDir.path}/p1.png')..writeAsBytesSync([1, 2, 3]);
      final orphanPdf = File('${pdfDir.path}/orphan.png')..writeAsBytesSync([4, 5, 6]);
      final keptDocx = File('${docxDir.path}/img1.png')..writeAsBytesSync([7, 8, 9]);
      final orphanDocx = File('${docxDir.path}/orphan.png')..writeAsBytesSync([10, 11]);

      final withAssets = defaultNb.copyWith(
        pages: [
          defaultNb.pages.first.copyWith(
            pdfBackgroundPath: keptPdf.path,
            imageElements: [
              ImageElement(
                id: 'img-keep',
                x: 10,
                y: 10,
                width: 100,
                height: 80,
                filePath: keptDocx.path,
              ),
            ],
          ),
        ],
      );
      await appState.updateNotebook(withAssets);
      await storage.cleanupOrphanAssets(appState.notebooks);

      expect(await keptPdf.exists(), isTrue);
      expect(await keptDocx.exists(), isTrue);
      expect(await orphanPdf.exists(), isFalse);
      expect(await orphanDocx.exists(), isFalse);
    });

    test('hierarchical folders support nesting, cycle guard, total counts, and parent promotion', () async {
      final storage = LocalStorageService(baseDirectory: tempDir);
      final appState = AppState(storage: storage);
      addTearDown(appState.dispose);
      final root = await appState.createFolder(name: 'Học kỳ 1', colorValue: 0xFF3B82F6);
      final child = await appState.createFolder(
        name: 'Hóa Vô Cơ',
        parentId: root.id,
        colorValue: 0xFF14B8A6,
      );
      final grandChild = await appState.createFolder(
        name: 'Phức chất',
        parentId: child.id,
        colorValue: 0xFFF59E0B,
      );

      await appState.createNotebook(title: 'Bài 1', folderId: child.id);
      await appState.createNotebook(title: 'Bài 2', folderId: grandChild.id);

      expect(
        appState.getFolderPath(grandChild.id).map((f) => f.id).toList(),
        [root.id, child.id, grandChild.id],
      );
      expect(
        appState.getDescendantFolderIds(root.id),
        containsAll(<String>[child.id, grandChild.id]),
      );
      expect(appState.getTotalNotebookCountInFolder(root.id), 2);
      expect(appState.getTotalNotebookCountInFolder(child.id), 2);

      // Cycle guard prevents moving root inside its own descendant
      await appState.moveFolder(root.id, grandChild.id);
      expect(appState.getFolderById(root.id)!.parentId, isNull);

      // Valid move of grandChild directly under root
      await appState.moveFolder(grandChild.id, root.id);
      expect(appState.getFolderById(grandChild.id)!.parentId, root.id);

      // Deleting child promotes Bài 1 up to root instead of dropping hierarchy
      await appState.deleteFolder(child.id);
      expect(appState.getFolderById(child.id), isNull);
      expect(appState.getNotebooksInFolder(root.id).length, 1);
      expect(appState.getTotalNotebookCountInFolder(root.id), 2);
    });

    test('batch notebook actions support duplicate, move, cover update, trash/restore, and permanent delete', () async {
      final storage = LocalStorageService(baseDirectory: tempDir);
      final appState = AppState(storage: storage);
      addTearDown(appState.dispose);
      final folder = await appState.createFolder(name: 'Ôn thi');
      final n1 = await appState.createNotebook(title: 'Sổ A');
      final n2 = await appState.createNotebook(title: 'Sổ B');

      final dupes = await appState.duplicateNotebooks([n1.id, n2.id]);
      expect(dupes.length, 2);
      expect(dupes.first.title, endsWith('(Bản sao)'));
      expect(dupes.first.id, isNot(equals(n1.id)));
      expect(dupes.first.pages.first.id, isNot(equals(n1.pages.first.id)));

      await appState.moveNotebooks([n1.id, n2.id], folder.id);
      expect(appState.getNotebooksInFolder(folder.id).length, 2);

      await appState.updateNotebooksCover(
        [n1.id, n2.id],
        coverStyle: 'lab',
        coverColorValue: 0xFF0F766E,
      );
      expect(appState.getNotebookById(n1.id)!.coverStyle, 'lab');
      expect(appState.getNotebookById(n2.id)!.coverColorValue, 0xFF0F766E);

      await appState.moveNotebooksToTrash([n1.id, n2.id]);
      expect(appState.trashedNotebooks.map((n) => n.id), containsAll([n1.id, n2.id]));

      await appState.restoreNotebooksFromTrash([n1.id]);
      expect(appState.getNotebookById(n1.id)!.isTrashed, isFalse);

      await appState.deleteNotebooks([n1.id, n2.id]);
      expect(appState.getNotebookById(n1.id), isNull);
      expect(appState.getNotebookById(n2.id), isNull);
    });

    test('PaperTemplatePainter renders full A4 and thumbnail sizes cleanly for sageRibbon & label templates', () async {
      for (final tpl in [
        PaperTemplateType.sageRibbon,
        PaperTemplateType.pastelGrid,
        PaperTemplateType.cornell,
        PaperTemplateType.twoColumnStudy,
      ]) {
        for (final size in [const Size(794, 1123), const Size(88, 124)]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          PaperTemplatePainter(
            templateType: tpl,
            paperColor: PaperColorType.white,
          ).paint(canvas, size);
          final picture = recorder.endRecording();
          final img = await picture.toImage(size.width.toInt(), size.height.toInt());
          expect(img.width, size.width.toInt());
          img.dispose();
          picture.dispose();
        }
      }
    });

    test('Notebook lastOpenedAt roundtrips and AppState.markNotebookOpened sorts recently opened notebooks first', () async {
      final tOld = DateTime.utc(2026, 11, 10, 8, 0);
      final tNew = DateTime.utc(2026, 11, 26, 9, 0);
      final legacy = Notebook(
        id: 'nb-legacy',
        title: 'Legacy',
        createdAt: tOld,
        updatedAt: tOld,
      );
      expect(legacy.lastOpenedAt, isNull);
      expect(legacy.effectiveOpenedAt, tOld);

      final withOpened = Notebook.fromJson({
        ...legacy.toJson(),
        'lastOpenedAt': tNew.toIso8601String(),
      });
      expect(withOpened.lastOpenedAt, tNew);
      expect(withOpened.effectiveOpenedAt, tNew);

      final storage = LocalStorageService(baseDirectory: tempDir);
      final folder = Folder(
        id: 'f-open-sort',
        name: 'Sắp xếp',
        createdAt: tOld,
        updatedAt: tOld,
      );
      final olderNb = Notebook(
        id: 'nb-older',
        title: 'Sổ Mở Lại',
        folderId: folder.id,
        createdAt: tOld,
        updatedAt: tOld,
        lastOpenedAt: tOld,
      );
      final newerNb = Notebook(
        id: 'nb-newer',
        title: 'Sổ Mới Hơn',
        folderId: folder.id,
        createdAt: tNew,
        updatedAt: tNew,
        lastOpenedAt: tNew,
      );
      await storage.saveFolders([folder]);
      await storage.saveNotebooks([olderNb, newerNb]);

      final appState = AppState(storage: storage);
      addTearDown(appState.dispose);
      int syncHookCalls = 0;
      appState.onNotebookChangedForSync = (_) async {
        syncHookCalls++;
      };
      await appState.loadAll();

      expect(appState.activeNotebooks.map((n) => n.id).toList(), ['nb-newer', 'nb-older']);
      expect(appState.getNotebooksInFolder(folder.id).map((n) => n.id).toList(), ['nb-newer', 'nb-older']);

      // Opening olderNb puts it first without changing updatedAt or triggering Drive upload
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await appState.markNotebookOpened('nb-older');
      expect(syncHookCalls, 0);
      expect(appState.activeNotebooks.first.id, 'nb-older');
      expect(appState.getNotebooksInFolder(folder.id).first.id, 'nb-older');
      expect(appState.getNotebookById('nb-older')!.updatedAt, tOld);

      // Persists across reload
      final reloaded = AppState(storage: storage);
      addTearDown(reloaded.dispose);
      await reloaded.loadAll();
      expect(reloaded.activeNotebooks.first.id, 'nb-older');
    });
  });

  group('PalmRejectionFilter triple-layer unit guards', () {
    test('isLikelyPalmTouch allows MatePad fingertip with size=1.0 and rejects massive palm only', () {
      const matePadNormalFinger = PointerDownEvent(
        pointer: 101,
        kind: PointerDeviceKind.touch,
        position: Offset(200, 300),
        radiusMajor: 28.0,
        size: 1.0,
      );
      const massivePalm = PointerDownEvent(
        pointer: 102,
        kind: PointerDeviceKind.touch,
        position: Offset(220, 320),
        radiusMajor: 55.0,
        size: 1.0,
      );
      const normalFinger = PointerDownEvent(
        pointer: 103,
        kind: PointerDeviceKind.touch,
        position: Offset(240, 340),
        radiusMajor: 8.0,
        size: 0.08,
      );
      const largeStylus = PointerDownEvent(
        pointer: 104,
        kind: PointerDeviceKind.stylus,
        position: Offset(260, 360),
        radiusMajor: 60.0,
        size: 1.0,
      );

      expect(PalmRejectionFilter.isLikelyPalmTouch(matePadNormalFinger), isFalse);
      expect(PalmRejectionFilter.isLikelyPalmTouch(massivePalm), isTrue);
      expect(PalmRejectionFilter.isLikelyPalmTouch(normalFinger), isFalse);
      expect(PalmRejectionFilter.isLikelyPalmTouch(largeStylus), isFalse);

      final filter = PalmRejectionFilter(stylusOnlyMode: false);
      expect(filter.shouldAccept(matePadNormalFinger), isTrue);
      expect(filter.shouldAccept(massivePalm), isFalse);
    });

    test('notifyStylusActivity enables 300ms cooldown blocking touch while accepting stylus', () {
      expect(PalmRejectionFilter.stylusCooldownMs, 300);
      final filter = PalmRejectionFilter(stylusOnlyMode: false);

      const touch = PointerDownEvent(
        pointer: 201,
        kind: PointerDeviceKind.touch,
        position: Offset(180, 220),
        radiusMajor: 28.0,
        size: 1.0,
      );
      const stylus = PointerDownEvent(
        pointer: 202,
        kind: PointerDeviceKind.stylus,
        position: Offset(180, 220),
      );

      expect(filter.isStylusRecentlyActive, isFalse);
      expect(filter.shouldAccept(touch), isTrue);

      filter.notifyStylusActivity();
      expect(filter.isStylusRecentlyActive, isTrue);
      expect(filter.shouldAccept(touch), isFalse);
      expect(filter.shouldAccept(stylus), isTrue);
    });
  });

  group('LassoController long-press helpers (paste center, selectAll, cancelDrawing, stroke width)', () {
    test('selectAll, cancelDrawing, pasteClipboard(targetCenter), and setSelectionStrokeWidth work accurately', () {
      const sSelected = Stroke(
        id: 's1',
        toolType: ToolType.fountainPen,
        colorValue: 0xFF111827,
        width: 2.5,
        points: [
          StrokePoint(x: 20.0, y: 20.0, pressure: 0.5, timestamp: 1),
          StrokePoint(x: 60.0, y: 60.0, pressure: 0.6, timestamp: 2),
        ],
      );
      const sOther = Stroke(
        id: 's2',
        toolType: ToolType.ballpointPen,
        colorValue: 0xFFDC2626,
        width: 3.0,
        points: [
          StrokePoint(x: 400.0, y: 400.0, pressure: 0.5, timestamp: 3),
          StrokePoint(x: 430.0, y: 420.0, pressure: 0.5, timestamp: 4),
        ],
      );
      final page = NotePage(
        id: 'p-lasso',
        index: 0,
        strokes: const [sSelected, sOther],
        updatedAt: DateTime.utc(2026, 11, 26),
      );

      final lasso = LassoController();
      addTearDown(lasso.dispose);

      // Select only s1 by circling around (0..100, 0..100)
      lasso.startLasso(const Offset(0, 0), pageId: page.id);
      lasso.updateLasso(const Offset(100, 0));
      lasso.updateLasso(const Offset(100, 100));
      lasso.updateLasso(const Offset(0, 100));
      final sel = lasso.finishLasso(page);
      expect(sel.strokeIds, {'s1'});

      // Copy s1 to clipboard and adjust selected stroke width
      lasso.copySelection(page);
      expect(lasso.hasClipboard, isTrue);

      final resizedPage = lasso.setSelectionStrokeWidth(page, 5.0);
      expect(resizedPage.strokes.firstWhere((s) => s.id == 's1').width, 5.0);
      expect(resizedPage.strokes.firstWhere((s) => s.id == 's2').width, 3.0);

      // cancelDrawing clears active freehand path without wiping clipboard
      lasso.startLasso(const Offset(290, 390), pageId: page.id);
      expect(lasso.isDrawingLasso, isTrue);
      lasso.cancelDrawing();
      expect(lasso.isDrawingLasso, isFalse);
      expect(lasso.lassoPath, isEmpty);
      expect(lasso.hasClipboard, isTrue);

      // pasteClipboard with targetCenter centers the pasted stroke near (300, 400)
      int nextId = 10;
      final pastedPage = lasso.pasteClipboard(
        resizedPage,
        idGenerator: () => 'pasted-${nextId++}',
        targetCenter: const Offset(300, 400),
      );
      expect(pastedPage.strokes.length, 3);
      final pasted = pastedPage.strokes.last;
      final bounds = CanvasPainter.strokeBounds(pasted);
      expect(bounds.center.dx, closeTo(300.0, 2.0));
      expect(bounds.center.dy, closeTo(400.0, 2.0));

      // selectAll selects all strokes on the updated page
      final allSel = lasso.selectAll(pastedPage);
      expect(allSel.strokeIds.length, 3);
      expect(lasso.selectionBounds, isNotNull);
    });
  });

  group('Watermark PDF/PNG export & page-level Undo/Redo storage (v3.8.3)', () {
    test('PdfExportService embeds Cormorant watermark on sageRibbon pages only', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final now = DateTime.utc(2026, 11, 26);
      final sageNb = Notebook(
        id: 'nb-sage',
        title: 'Sage Watermark Test',
        coverColorValue: 0xFFB4C3AC,
        defaultTemplate: PaperTemplateType.sageRibbon,
        pages: [
          NotePage(
            id: 'p-sage',
            index: 0,
            templateType: PaperTemplateType.sageRibbon,
            paperColor: PaperColorType.white,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final blankNb = Notebook(
        id: 'nb-blank',
        title: 'Blank Test',
        coverColorValue: 0xFF3B82F6,
        defaultTemplate: PaperTemplateType.blank,
        pages: [
          NotePage(
            id: 'p-blank',
            index: 0,
            templateType: PaperTemplateType.blank,
            paperColor: PaperColorType.white,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final pdfService = PdfExportService();
      final sageBytes = await pdfService.buildNotebookPdfBytes(sageNb);
      final blankBytes = await pdfService.buildNotebookPdfBytes(blankNb);

      expect(String.fromCharCodes(sageBytes.take(5)), '%PDF-');
      expect(String.fromCharCodes(blankBytes.take(5)), '%PDF-');
      expect(sageBytes.length, greaterThan(blankBytes.length));

      // A sageRibbon page backed by an imported PDF should still export safely.
      final withPdfBg = sageNb.copyWith(
        pages: [
          sageNb.pages.first.copyWith(pdfBackgroundPath: '/tmp/nonexistent_slide.jpg'),
        ],
      );
      final bgBytes = await pdfService.buildNotebookPdfBytes(withPdfBg);
      expect(String.fromCharCodes(bgBytes.take(5)), '%PDF-');
    });

    test('PageImageExportService renders PNG bytes for sageRibbon page with content', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final tempDir = Directory.systemTemp.createTempSync('chemnote_img_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final now = DateTime.utc(2026, 11, 26);
      final page = NotePage(
        id: 'img-page-1',
        index: 0,
        templateType: PaperTemplateType.sageRibbon,
        paperColor: PaperColorType.white,
        strokes: const [
          Stroke(
            id: 'st-1',
            toolType: ToolType.fountainPen,
            colorValue: 0xFF1E3A8A,
            width: 3.0,
            points: [
              StrokePoint(x: 120, y: 180, pressure: 0.6),
              StrokePoint(x: 340, y: 260, pressure: 0.7),
            ],
          ),
        ],
        textElements: const [
          TextElement(
            id: 'txt-1',
            x: 100,
            y: 300,
            width: 240,
            text: 'H2SO4 + BaCl2 -> BaSO4 + 2HCl',
            fontSize: 16,
            colorValue: 0xFF141815,
          ),
        ],
        updatedAt: now,
      );

      final imageService = PageImageExportService(overrideExportDir: tempDir);
      final pngBytes = await imageService.renderPageToPngBytes(page, scale: 1.0);
      expect(pngBytes.length, greaterThan(1000));
      // PNG signature: 0x89 P N G
      expect(pngBytes.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('AppState.replaceNotebookPages restores deleted and reordered pages cleanly', () async {
      final tempDir = Directory.systemTemp.createTempSync('chemnote_page_undo_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final storage = LocalStorageService(baseDirectory: tempDir);
      final appState = AppState(storage: storage);
      addTearDown(appState.dispose);

      final nb = await appState.createNotebook(title: 'Undo MultiPage');
      await appState.addPage(nb.id);
      await appState.addPage(nb.id);

      final nbWithThree = appState.getNotebookById(nb.id)!;
      expect(nbWithThree.pages.length, 3);
      final snapshotBeforeDelete = List<NotePage>.of(nbWithThree.pages);
      final deletedPageId = nbWithThree.pages[1].id;

      await appState.deletePage(nb.id, deletedPageId);
      final nbAfterDelete = appState.getNotebookById(nb.id)!;
      expect(nbAfterDelete.pages.length, 2);
      expect(nbAfterDelete.pages.any((p) => p.id == deletedPageId), isFalse);

      // Simulate Undo restoring exact 3 pages with 0..2 indices
      await appState.replaceNotebookPages(nb.id, snapshotBeforeDelete);
      final nbRestored = appState.getNotebookById(nb.id)!;
      expect(nbRestored.pages.length, 3);
      expect(
        nbRestored.pages.map((p) => p.id).toList(),
        snapshotBeforeDelete.map((p) => p.id).toList(),
      );
      expect(nbRestored.pages.map((p) => p.index).toList(), [0, 1, 2]);

      await appState.flushPendingSaves();
      final reloaded = AppState(storage: storage);
      addTearDown(reloaded.dispose);
      await reloaded.loadAll();
      final persisted = reloaded.getNotebookById(nb.id)!;
      expect(persisted.pages.length, 3);
      expect(persisted.pages[1].id, deletedPageId);
    });
  });

  group('Smoothness, atomic storage & sync safety (v3.8.4)', () {
    test('LocalStorageService coalesces concurrent writes atomically with zero tmp leftovers', () async {
      final tempDir = Directory.systemTemp.createTempSync('chemnote_atomic_io_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final storage = LocalStorageService(baseDirectory: tempDir);
      final now = DateTime.utc(2026, 11, 27);
      Notebook makeNb(String title) => Notebook(
            id: 'nb-race',
            title: title,
            createdAt: now,
            updatedAt: now,
          );

      // Enqueue multiple out-of-order concurrent writes for the same notebook
      await Future.wait([
        storage.saveNotebook(makeNb('Title v1')),
        storage.saveNotebook(makeNb('Title v2')),
        storage.saveNotebook(makeNb('Title v3 Final')),
      ]);

      final loaded = await storage.loadNotebooks();
      expect(loaded.length, 1);
      expect(loaded.first.title, 'Title v3 Final');

      final root = await storage.getRootDirectory();
      final nbDir = Directory('${root.path}${Platform.pathSeparator}notebooks');
      final tmpLeftovers = nbDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.tmp.'))
          .toList();
      expect(tmpLeftovers, isEmpty);

      // Deleting during an in-flight save never leaves a resurrected file behind
      final inflight = storage.saveNotebook(makeNb('Should Not Ghost'));
      await storage.deleteNotebookFile('nb-race');
      await inflight;
      expect(await storage.loadNotebooks(), isEmpty);
    });

    test('AppState.libraryUiRevision ignores same-day stroke edits but bumps on structural changes', () async {
      final tempDir = Directory.systemTemp.createTempSync('chemnote_lib_rev_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final storage = LocalStorageService(baseDirectory: tempDir);
      final appState = AppState(storage: storage);
      addTearDown(appState.dispose);

      final revBeforeCreate = appState.libraryUiRevision;
      final nb = await appState.createNotebook(title: 'Revision Test');
      expect(appState.libraryUiRevision, greaterThan(revBeforeCreate));

      final revBeforeStrokes = appState.libraryUiRevision;
      final page0 = nb.pages.first;
      await appState.updatePage(
        nb.id,
        page0.copyWith(
          strokes: const [
            Stroke(
              id: 'stroke-rev-1',
              toolType: ToolType.fountainPen,
              colorValue: 0xFF1D4ED8,
              width: 2.0,
              points: [
                StrokePoint(x: 10, y: 10, pressure: 0.5),
                StrokePoint(x: 40, y: 40, pressure: 0.6),
              ],
            ),
          ],
        ),
      );
      expect(appState.libraryUiRevision, revBeforeStrokes);

      await appState.addPage(nb.id);
      expect(appState.libraryUiRevision, greaterThan(revBeforeStrokes));

      final revBeforeToggle = appState.libraryUiRevision;
      await appState.toggleFavorite(nb.id);
      expect(appState.libraryUiRevision, greaterThan(revBeforeToggle));

      final revBeforeFolder = appState.libraryUiRevision;
      await appState.createFolder(name: 'Vô Cơ');
      expect(appState.libraryUiRevision, greaterThan(revBeforeFolder));

      final revBeforeDeletePage = appState.libraryUiRevision;
      await appState.deletePage(nb.id, nb.pages.first.id);
      expect(appState.libraryUiRevision, greaterThan(revBeforeDeletePage));
    });

    test('AppState.upsertNotebookFromSync preserves newer unsaved local debounced edit', () async {
      final tempDir = Directory.systemTemp.createTempSync('chemnote_sync_clobber_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final storage = LocalStorageService(baseDirectory: tempDir);
      final appState = AppState(storage: storage);
      addTearDown(appState.dispose);

      final nb = await appState.createNotebook(title: 'Sync Clobber Guard');
      await Future<void>.delayed(const Duration(milliseconds: 25));

      final editedPage = nb.pages.first.copyWith(
        strokes: const [
          Stroke(
            id: 'local-new-stroke',
            toolType: ToolType.fountainPen,
            colorValue: 0xFF000000,
            width: 2.0,
            points: [StrokePoint(x: 5, y: 5, pressure: 0.5)],
          ),
        ],
      );
      // Schedules debounced local save in _pendingSaveNotebooks with newer updatedAt
      await appState.updatePage(nb.id, editedPage);
      final localAfterEdit = appState.getNotebookById(nb.id)!;

      // Older remote snapshot arrives -> must NOT clobber newer pending local edit
      final olderRemote = nb.copyWith(
        updatedAt: localAfterEdit.updatedAt.subtract(const Duration(seconds: 5)),
        pages: [nb.pages.first.copyWith(strokes: const [])],
      );
      await appState.upsertNotebookFromSync(olderRemote);

      final preserved = appState.getNotebookById(nb.id)!;
      expect(preserved.pages.first.strokes.length, 1);
      expect(preserved.pages.first.strokes.first.id, 'local-new-stroke');
    });

    test('SyncManager keeps pendingUpload status when notebook is edited during upload', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final tempDir = Directory.systemTemp.createTempSync('chemnote_mid_upload_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final storage = LocalStorageService(baseDirectory: tempDir);
      final appState = AppState(storage: storage);
      addTearDown(appState.dispose);

      final auth = GoogleAuthService();
      await auth.signInDemo();

      bool triggerEditOnce = true;
      final drive = _MidUploadEditDriveService(
        authService: auth,
        onBeforeUpload: (uploadingNb) async {
          if (!triggerEditOnce) return;
          triggerEditOnce = false;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await appState.updatePage(
            uploadingNb.id,
            uploadingNb.pages.first.copyWith(
              strokes: const [
                Stroke(
                  id: 'edited-mid-upload',
                  toolType: ToolType.fountainPen,
                  colorValue: 0xFFDC2626,
                  width: 3.0,
                  points: [StrokePoint(x: 12, y: 12, pressure: 0.6)],
                ),
              ],
            ),
          );
        },
      );

      final manager = SyncManager(
        appState: appState,
        authService: auth,
        driveService: drive,
        attachConnectivityListener: false,
        debounceDuration: const Duration(milliseconds: 20),
      );
      addTearDown(manager.dispose);

      final nb = await appState.createNotebook(title: 'Mid Upload Edit');
      await manager.syncNow(isManualSync: true);

      final current = appState.getNotebookById(nb.id)!;
      expect(current.syncStatus, SyncStatus.pendingUpload);
      expect(manager.pendingUploadIds, contains(nb.id));
    });
  });
}

class _MidUploadEditDriveService extends GoogleDriveService {
  _MidUploadEditDriveService({
    required super.authService,
    this.onBeforeUpload,
  });

  final Future<void> Function(Notebook notebook)? onBeforeUpload;

  @override
  Future<String> uploadNotebook(Notebook notebook) async {
    await onBeforeUpload?.call(notebook);
    return super.uploadNotebook(notebook);
  }
}
