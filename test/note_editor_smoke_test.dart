import 'dart:io';

import 'package:chemnote/core/models/drawing_elements.dart';
import 'package:chemnote/core/models/note_page.dart';
import 'package:chemnote/core/providers/app_state.dart';
import 'package:chemnote/core/storage/local_storage_service.dart';
import 'package:chemnote/features/canvas/note_editor_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('NoteEditorScreen smoke tests', () {
    late Directory tempDir;
    late AppState appState;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chemnote_editor_smoke_');
      appState = AppState(
        storage: LocalStorageService(baseDirectory: tempDir),
      );
    });

    tearDown(() {
      appState.dispose();
    });

    testWidgets(
      'renders multi-page vertical notebook cleanly and accepts stylus stroke',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime.now();
        late final String notebookId;
        await tester.runAsync(() async {
          final nb = await appState.createNotebook(
            title: 'Smoke Vertical Notebook',
            initialPages: [
              NotePage(
                id: 'page-1',
                index: 0,
                templateType: PaperTemplateType.ruled,
                paperColor: PaperColorType.cream,
                updatedAt: now,
              ),
              NotePage(
                id: 'page-2',
                index: 1,
                templateType: PaperTemplateType.ruled,
                paperColor: PaperColorType.cream,
                updatedAt: now,
              ),
            ],
          );
          notebookId = nb.id;
        });

        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: MaterialApp(
              home: NoteEditorScreen(notebookId: notebookId),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(find.byType(InteractiveViewer), findsOneWidget);

        // Simulate M-Pencil 3 stylus stroke near center of the visible first page
        final center = tester.getCenter(find.byType(InteractiveViewer));
        final stylus = TestPointer(1, PointerDeviceKind.stylus);
        await tester.sendEventToBinding(stylus.down(center));
        await tester.pump();
        await tester.sendEventToBinding(
          stylus.move(center + const Offset(45, 25)),
        );
        await tester.pump();
        await tester.sendEventToBinding(
          stylus.move(center + const Offset(95, 50)),
        );
        await tester.pump();
        await tester.sendEventToBinding(stylus.up());
        await tester.pump();

        expect(tester.takeException(), isNull);
        final updatedNb = appState.getNotebookById(notebookId)!;
        expect(updatedNb.pages.first.strokes.length, 1);

        // Unmount and drain any background save compute before finishing
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await appState.flushPendingSaves();
          await Future<void>.delayed(const Duration(milliseconds: 80));
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      },
    );

    testWidgets(
      'renders Infinite Whiteboard notebook cleanly inside InteractiveViewer',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        late final String whiteboardId;
        await tester.runAsync(() async {
          final nb = await appState.createNotebook(
            title: 'Smoke Whiteboard',
            isWhiteboard: true,
          );
          whiteboardId = nb.id;
        });

        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: MaterialApp(
              home: NoteEditorScreen(notebookId: whiteboardId),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(find.byType(InteractiveViewer), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await appState.flushPendingSaves();
          await Future<void>.delayed(const Duration(milliseconds: 80));
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      },
    );

    testWidgets(
      'palm touch + PointerCancel during stylus stroke never drops finished stroke, and reopening restores lastPageIndex',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime.now();
        late final String notebookId;
        await tester.runAsync(() async {
          final nb = await appState.createNotebook(
            title: 'Palm & Restore Notebook',
            initialPages: [
              for (int i = 0; i < 3; i++)
                NotePage(
                  id: 'p_restore_$i',
                  index: i,
                  templateType: PaperTemplateType.ruled,
                  paperColor: PaperColorType.cream,
                  updatedAt: now,
                ),
            ],
          );
          await appState.saveNotebookViewportState(
            nb.id,
            lastPageIndex: 2,
            lastScrollOffsetX: 24.0,
            lastScrollOffsetY: 2274.0,
            lastZoomScale: 1.0,
            flushImmediately: true,
          );
          notebookId = nb.id;
        });

        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: MaterialApp(
              home: NoteEditorScreen(notebookId: notebookId),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Restored onto last page index (Page 3 -> index 2, so badge reads 'Trang 3 / 3')
        expect(find.text('Trang 3 / 3'), findsOneWidget);

        final center = tester.getCenter(find.byType(InteractiveViewer));
        final stylus = TestPointer(10, PointerDeviceKind.stylus);
        final palm = TestPointer(11, PointerDeviceKind.touch);

        // Start stylus stroke, then simulate resting palm touch + OS palm cancel mid-stroke
        await tester.sendEventToBinding(stylus.down(center));
        await tester.pump();
        await tester.sendEventToBinding(
          stylus.move(center + const Offset(35, 10)),
        );
        await tester.pump();
        await tester.sendEventToBinding(palm.down(center + const Offset(120, 120)));
        await tester.pump();
        await tester.sendEventToBinding(palm.cancel());
        await tester.pump();
        await tester.sendEventToBinding(
          stylus.move(center + const Offset(80, 30)),
        );
        await tester.pump();
        await tester.sendEventToBinding(stylus.up());
        await tester.pump();

        expect(tester.takeException(), isNull);
        final updatedNb = appState.getNotebookById(notebookId)!;
        expect(updatedNb.pages[2].strokes.length, 1);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await appState.flushPendingSaves();
          await Future<void>.delayed(const Duration(milliseconds: 80));
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      },
    );
  });
}
