import 'dart:convert';

import 'package:chemnote/core/models/drawing_elements.dart';
import 'package:chemnote/core/models/folder.dart';
import 'package:chemnote/core/models/note_page.dart';
import 'package:chemnote/core/models/notebook.dart';
import 'package:chemnote/core/providers/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Core Models JSON Serialization', () {
    test('Folder JSON round-trip and copyWith', () {
      final created = DateTime.utc(2026, 1, 15, 8, 30);
      final updated = DateTime.utc(2026, 1, 16, 14, 45);
      final folder = Folder(
        id: 'folder-1',
        name: 'Hóa Hữu Cơ',
        parentId: 'root-chem',
        colorValue: 0xFF2B6CB0,
        iconName: 'science',
        createdAt: created,
        updatedAt: updated,
      );

      final encoded = jsonEncode(folder.toJson());
      final decoded = Folder.fromJson(jsonDecode(encoded) as Map<String, dynamic>);

      expect(decoded.id, folder.id);
      expect(decoded.name, folder.name);
      expect(decoded.parentId, folder.parentId);
      expect(decoded.colorValue, folder.colorValue);
      expect(decoded.iconName, folder.iconName);
      expect(decoded.createdAt, created);
      expect(decoded.updatedAt, updated);

      final cleared = decoded.copyWith(clearParentId: true, name: 'Hóa Đại Cương');
      expect(cleared.parentId, isNull);
      expect(cleared.name, 'Hóa Đại Cương');
    });

    test('Stroke and StrokePoint JSON round-trip', () {
      const stroke = Stroke(
        id: 'stroke-1',
        toolType: ToolType.fountainPen,
        colorValue: 0xFF1A365D,
        width: 3.25,
        isSmoothed: true,
        shapeType: ShapeType.hexagon,
        points: [
          StrokePoint(x: 10.5, y: 20.25, pressure: 0.75, tilt: 0.15, timestamp: 1000),
          StrokePoint(x: 40.0, y: 55.5, pressure: 0.9, tilt: 0.2, timestamp: 1016),
        ],
      );

      final encoded = jsonEncode(stroke.toJson());
      final decoded = Stroke.fromJson(jsonDecode(encoded) as Map<String, dynamic>);

      expect(decoded.id, stroke.id);
      expect(decoded.toolType, ToolType.fountainPen);
      expect(decoded.colorValue, 0xFF1A365D);
      expect(decoded.width, 3.25);
      expect(decoded.isSmoothed, isTrue);
      expect(decoded.shapeType, ShapeType.hexagon);
      expect(decoded.points.length, 2);
      expect(decoded.points[0].x, 10.5);
      expect(decoded.points[0].y, 20.25);
      expect(decoded.points[0].pressure, 0.75);
      expect(decoded.points[0].tilt, 0.15);
      expect(decoded.points[0].timestamp, 1000);
      expect(decoded.points[1].pressure, 0.9);
    });

    test('NotePage JSON round-trip with all element types', () {
      final updatedAt = DateTime.utc(2026, 2, 10, 9, 0);
      final page = NotePage(
        id: 'page-1',
        index: 2,
        templateType: PaperTemplateType.hexagonal,
        paperColor: PaperColorType.cream,
        isLandscape: true,
        strokes: const [
          Stroke(
            id: 's1',
            toolType: ToolType.highlighter,
            colorValue: 0x80FFEE58,
            width: 14.0,
            points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 100)],
          ),
        ],
        textElements: const [
          TextElement(
            id: 't1',
            x: 50,
            y: 60,
            width: 300,
            height: 80,
            text: 'C6H6 + Br2 -> C6H5Br + HBr',
            fontSize: 20,
            colorValue: 0xFF000000,
            isBold: true,
            isItalic: false,
          ),
        ],
        imageElements: const [
          ImageElement(
            id: 'i1',
            x: 120,
            y: 140,
            width: 200,
            height: 150,
            rotation: 0.25,
            filePath: '/data/user/0/com.chemnote.app/files/img1.png',
          ),
        ],
        stencilElements: const [
          StencilElement(
            id: 'st1',
            stencilId: 'benzene_ring',
            x: 200,
            y: 220,
            width: 110,
            height: 110,
            rotation: 0.5,
            colorValue: 0xFF1F2937,
            strokeWidth: 2.2,
          ),
        ],
        pdfBackgroundPath: '/data/user/0/com.chemnote.app/files/slide_1.png',
        pdfPageNumber: 1,
        isBookmarked: true,
        title: 'Phản ứng thế thơm',
        updatedAt: updatedAt,
      );

      final encoded = jsonEncode(page.toJson());
      final decoded = NotePage.fromJson(jsonDecode(encoded) as Map<String, dynamic>);

      expect(decoded.id, page.id);
      expect(decoded.index, 2);
      expect(decoded.templateType, PaperTemplateType.hexagonal);
      expect(decoded.paperColor, PaperColorType.cream);
      expect(decoded.isLandscape, isTrue);
      expect(decoded.strokes.length, 1);
      expect(decoded.strokes.first.toolType, ToolType.highlighter);
      expect(decoded.textElements.length, 1);
      expect(decoded.textElements.first.text, 'C6H6 + Br2 -> C6H5Br + HBr');
      expect(decoded.textElements.first.isBold, isTrue);
      expect(decoded.imageElements.length, 1);
      expect(decoded.imageElements.first.rotation, 0.25);
      expect(decoded.stencilElements.length, 1);
      expect(decoded.stencilElements.first.stencilId, 'benzene_ring');
      expect(decoded.pdfBackgroundPath, '/data/user/0/com.chemnote.app/files/slide_1.png');
      expect(decoded.pdfPageNumber, 1);
      expect(decoded.isBookmarked, isTrue);
      expect(decoded.title, 'Phản ứng thế thơm');
      expect(decoded.updatedAt, updatedAt);
    });

    test('Notebook JSON round-trip preserves sync metadata and pages', () {
      final created = DateTime.utc(2026, 3, 1, 10, 0);
      final updated = DateTime.utc(2026, 3, 5, 16, 30);
      final notebook = Notebook(
        id: 'nb-chem-101',
        title: 'Hóa Phân Tích - Chuẩn Độ',
        folderId: 'folder-1',
        coverStyle: 'laboratory',
        coverColorValue: 0xFF1E5128,
        defaultTemplate: PaperTemplateType.sageRibbon,
        defaultPaperColor: PaperColorType.white,
        defaultOrientationLandscape: false,
        pages: [
          NotePage(
            id: 'p1',
            index: 0,
            templateType: PaperTemplateType.twoColumnStudy,
            paperColor: PaperColorType.dark,
            updatedAt: updated,
          ),
        ],
        createdAt: created,
        updatedAt: updated,
        syncStatus: SyncStatus.pendingUpload,
        driveFileId: 'drive-file-xyz',
      );

      final encoded = jsonEncode(notebook.toJson());
      final decoded = Notebook.fromJson(jsonDecode(encoded) as Map<String, dynamic>);

      expect(decoded.id, notebook.id);
      expect(decoded.title, notebook.title);
      expect(decoded.folderId, 'folder-1');
      expect(decoded.coverStyle, 'laboratory');
      expect(decoded.coverColorValue, 0xFF1E5128);
      expect(decoded.defaultTemplate, PaperTemplateType.sageRibbon);
      expect(decoded.defaultPaperColor, PaperColorType.white);
      expect(decoded.defaultOrientationLandscape, isFalse);
      expect(decoded.pages.length, 1);
      expect(decoded.pages.first.templateType, PaperTemplateType.twoColumnStudy);
      expect(decoded.pages.first.paperColor, PaperColorType.dark);
      expect(decoded.createdAt, created);
      expect(decoded.updatedAt, updated);
      expect(decoded.syncStatus, SyncStatus.pendingUpload);
      expect(decoded.driveFileId, 'drive-file-xyz');
    });

    test('Enum fallback safety on legacy and unknown JSON values', () {
      expect(paperTemplateFromJson('titrationGraph'), PaperTemplateType.grid);
      expect(paperTemplateFromJson('labReport'), PaperTemplateType.sageRibbon);
      expect(paperTemplateFromJson('pastelGrid'), PaperTemplateType.pastelGrid);
      expect(paperTemplateFromJson('vintageCream'), PaperTemplateType.vintageCream);
      expect(PaperTemplateType.values.length, 10);

      final decoded = Notebook.fromJson({
        'id': 'nb-fallback',
        'title': 'Fallback Test',
        'defaultTemplate': 'nonExistentTemplate',
        'defaultPaperColor': 'nonExistentColor',
        'syncStatus': 'unknownStatus',
      });

      expect(decoded.defaultTemplate, PaperTemplateType.sageRibbon);
      expect(decoded.defaultPaperColor, PaperColorType.cream);
      expect(decoded.syncStatus, SyncStatus.localOnly);
    });

    test('v3 ImageElement non-destructive crop, AttachmentElement, PenPreset, and empty favoritePens', () {
      final now = DateTime.utc(2026, 5, 1, 12, 0);
      const croppedImage = ImageElement(
        id: 'img-crop-1',
        x: 30,
        y: 50,
        width: 180,
        height: 40,
        filePath: '/data/chem/formula_hd.png',
        cropLeft: 0.12,
        cropTop: 0.45,
        cropRight: 0.68,
        cropBottom: 0.51,
        freehandClipPath: [
          StrokePoint(x: 0.1, y: 0.1),
          StrokePoint(x: 0.9, y: 0.2),
          StrokePoint(x: 0.5, y: 0.9),
        ],
      );
      const attachment = AttachmentElement(
        id: 'att-1',
        x: 80,
        y: 120,
        width: 240,
        height: 68,
        fileName: 'De_cuong_Hoa_Ly_2.docx',
        filePath: '/data/chem/De_cuong_Hoa_Ly_2.docx',
        fileExtension: 'docx',
        fileSizeBytes: 245760,
      );
      const preset = PenPreset(
        id: 'preset-v3',
        toolType: ToolType.fountainPen,
        colorValue: 0xFF3B5BDB,
        width: 2.0,
        opacity: 0.85,
        pressureSensitivity: 0.75,
        label: 'Bút máy xanh',
      );

      final page = NotePage(
        id: 'p-v3',
        index: 0,
        templateType: PaperTemplateType.sageRibbon,
        imageElements: const [croppedImage],
        attachmentElements: const [attachment],
        updatedAt: now,
      );

      final decodedPage = NotePage.fromJson(
        jsonDecode(jsonEncode(page.toJson())) as Map<String, dynamic>,
      );
      expect(decodedPage.imageElements.first.cropLeft, closeTo(0.12, 1e-6));
      expect(decodedPage.imageElements.first.cropTop, closeTo(0.45, 1e-6));
      expect(decodedPage.imageElements.first.cropRight, closeTo(0.68, 1e-6));
      expect(decodedPage.imageElements.first.cropBottom, closeTo(0.51, 1e-6));
      expect(decodedPage.imageElements.first.freehandClipPath.length, 3);
      expect(decodedPage.attachmentElements.length, 1);
      expect(decodedPage.attachmentElements.first.fileName, 'De_cuong_Hoa_Ly_2.docx');
      expect(decodedPage.attachmentElements.first.fileExtension, 'docx');
      expect(decodedPage.attachmentElements.first.fileSizeBytes, 245760);

      final decodedPreset = PenPreset.fromJson(
        jsonDecode(jsonEncode(preset.toJson())) as Map<String, dynamic>,
      );
      expect(decodedPreset.opacity, closeTo(0.85, 1e-6));
      expect(decodedPreset.pressureSensitivity, closeTo(0.75, 1e-6));

      // Verify AppState.favoritePens starts EMPTY until user stars a pen
      final appState = AppState();
      expect(appState.favoritePens, isEmpty);
      expect(appState.showFavoritesBar, isTrue);
      expect(
        appState.isPenStarred(
          preset.toolType,
          preset.colorValue,
          preset.width,
          opacity: preset.opacity,
        ),
        isFalse,
      );
    });

    test('v2 TapeElement, ToolType.pencil, PenPreset, and Notebook lock/favorite/trash round-trip', () {
      final trashedAt = DateTime.utc(2026, 4, 1, 12, 0);
      const pencilStroke = Stroke(
        id: 'stroke-pencil',
        toolType: ToolType.pencil,
        colorValue: 0xFF475569,
        width: 2.0,
        points: [StrokePoint(x: 1, y: 2, pressure: 0.4, tilt: 0.6)],
      );
      const tape = TapeElement(
        id: 'tape-1',
        x: 40,
        y: 80,
        width: 200,
        height: 48,
        colorValue: 0xFF3B82F6,
        isRevealed: true,
      );
      const preset = PenPreset(
        id: 'preset-1',
        toolType: ToolType.pencil,
        colorValue: 0xFF1E293B,
        width: 1.8,
        label: 'Bút chì phác thảo',
      );

      final page = NotePage(
        id: 'p-v2',
        index: 0,
        strokes: const [pencilStroke],
        tapeElements: const [tape],
        updatedAt: trashedAt,
      );
      final notebook = Notebook(
        id: 'nb-v2',
        title: 'Sổ khóa bảo mật',
        pages: [page],
        createdAt: trashedAt,
        updatedAt: trashedAt,
        isFavorite: true,
        isLocked: true,
        pinCode: '1234',
        isTrashed: true,
        trashedAt: trashedAt,
      );

      final decodedNb = Notebook.fromJson(
        jsonDecode(jsonEncode(notebook.toJson())) as Map<String, dynamic>,
      );
      expect(decodedNb.isFavorite, isTrue);
      expect(decodedNb.isLocked, isTrue);
      expect(decodedNb.pinCode, '1234');
      expect(decodedNb.isTrashed, isTrue);
      expect(decodedNb.trashedAt, trashedAt);
      expect(decodedNb.pages.first.strokes.first.toolType, ToolType.pencil);
      expect(decodedNb.pages.first.tapeElements.length, 1);
      expect(decodedNb.pages.first.tapeElements.first.isRevealed, isTrue);
      expect(decodedNb.pages.first.tapeElements.first.width, 200);

      final decodedPreset = PenPreset.fromJson(
        jsonDecode(jsonEncode(preset.toJson())) as Map<String, dynamic>,
      );
      expect(decodedPreset.id, 'preset-1');
      expect(decodedPreset.toolType, ToolType.pencil);
      expect(decodedPreset.label, 'Bút chì phác thảo');
    });

    test('v3.0.0 AudioRecording, Stroke audioId/audioTimeMs, and AppState SHA-256 PIN', () {
      final recordedAt = DateTime.utc(2026, 6, 1, 9, 30);
      const audioStroke = Stroke(
        id: 'stroke-audio-1',
        toolType: ToolType.fountainPen,
        colorValue: 0xFF1E3A5F,
        width: 2.5,
        points: [StrokePoint(x: 10, y: 20), StrokePoint(x: 50, y: 60)],
        audioId: 'rec-1',
        audioTimeMs: 4250,
      );
      final recording = AudioRecording(
        id: 'rec-1',
        filePath: '/data/user/0/com.chemnote.app/files/audio/rec_1.m4a',
        durationMs: 185000,
        createdAt: recordedAt,
      );
      final page = NotePage(
        id: 'page-audio',
        index: 0,
        strokes: const [audioStroke],
        audioRecordings: [recording],
        updatedAt: recordedAt,
      );

      final decodedPage = NotePage.fromJson(
        jsonDecode(jsonEncode(page.toJson())) as Map<String, dynamic>,
      );
      expect(decodedPage.strokes.first.audioId, 'rec-1');
      expect(decodedPage.strokes.first.audioTimeMs, 4250);
      expect(decodedPage.audioRecordings.length, 1);
      expect(decodedPage.audioRecordings.first.id, 'rec-1');
      expect(decodedPage.audioRecordings.first.durationMs, 185000);
      expect(decodedPage.audioRecordings.first.createdAt, recordedAt);

      final hashed = AppState.hashPin('2026');
      expect(hashed, startsWith('sha256_'));
      expect(AppState.verifyPin('2026', hashed), isTrue);
      expect(AppState.verifyPin('0000', hashed), isFalse);
      // Backwards-compatible plaintext PIN check
      expect(AppState.verifyPin('1234', '1234'), isTrue);
    });

    test('v3.1.0 StickyNoteElement, isInfiniteWhiteboard, and Notebook.isWhiteboard round-trip', () {
      final now = DateTime.utc(2026, 7, 1, 15, 0);
      final sticky = StickyNoteElement(
        id: 'sticky-1',
        x: 2950.0,
        y: 3020.0,
        width: 230.0,
        height: 200.0,
        text: 'Nhớ hệ số cân bằng: 2MnO4- + 5C2O4^2- + 16H+',
        colorValue: 0xFFBBF7D0,
        isCollapsed: true,
        updatedAt: now,
      );
      final whiteboardPage = NotePage(
        id: 'wb-page-1',
        index: 0,
        templateType: PaperTemplateType.dotted,
        isInfiniteWhiteboard: true,
        stickyNotes: [sticky],
        updatedAt: now,
      );
      final whiteboardNotebook = Notebook(
        id: 'wb-nb-1',
        title: 'Sơ đồ cơ chế Hữu cơ',
        defaultTemplate: PaperTemplateType.hexagonal,
        isWhiteboard: true,
        customCoverImagePath: '/data/user/0/com.chemnote.app/files/covers/my_cover.jpg',
        useFirstPageAsCover: true,
        pages: [whiteboardPage],
        createdAt: now,
        updatedAt: now,
      );

      final decoded = Notebook.fromJson(
        jsonDecode(jsonEncode(whiteboardNotebook.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.isWhiteboard, isTrue);
      expect(decoded.customCoverImagePath, '/data/user/0/com.chemnote.app/files/covers/my_cover.jpg');
      expect(decoded.useFirstPageAsCover, isTrue);
      expect(decoded.pages.first.isInfiniteWhiteboard, isTrue);
      expect(decoded.pages.first.stickyNotes.length, 1);
      final decodedSticky = decoded.pages.first.stickyNotes.first;
      expect(decodedSticky.id, 'sticky-1');
      expect(decodedSticky.x, 2950.0);
      expect(decodedSticky.y, 3020.0);
      expect(decodedSticky.width, 230.0);
      expect(decodedSticky.height, 200.0);
      expect(decodedSticky.text, contains('2MnO4-'));
      expect(decodedSticky.colorValue, 0xFFBBF7D0);
      expect(decodedSticky.isCollapsed, isTrue);
      expect(decodedSticky.updatedAt, now);

      // Safe defaults when legacy JSON omits v3.1.0 fields
      final legacy = Notebook.fromJson({'id': 'legacy-1', 'title': 'Legacy'});
      expect(legacy.isWhiteboard, isFalse);
      expect(legacy.customCoverImagePath, isNull);
      expect(legacy.useFirstPageAsCover, isFalse);
      final legacyPage = NotePage.fromJson({'id': 'legacy-p1'});
      expect(legacyPage.isInfiniteWhiteboard, isFalse);
      expect(legacyPage.stickyNotes, isEmpty);
    });

    test('v3.3.0 chronological zIndex round-trip across Stroke, Image, StickyNote, Text, and Stencil', () {
      const stroke = Stroke(
        id: 's-z',
        toolType: ToolType.fountainPen,
        colorValue: 0xFF111827,
        width: 2.0,
        points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 10)],
        zIndex: 1001,
      );
      const img = ImageElement(
        id: 'img-z',
        x: 20,
        y: 20,
        filePath: '/tmp/a.png',
        zIndex: 2002,
      );
      final sticky = StickyNoteElement(
        id: 'st-z',
        x: 30,
        y: 30,
        text: 'Z-order test',
        zIndex: 3003,
      );
      const txt = TextElement(
        id: 'txt-z',
        x: 40,
        y: 40,
        text: 'H2SO4',
        zIndex: 4004,
      );
      const stencil = StencilElement(
        id: 'stn-z',
        stencilId: 'benzene_ring',
        x: 50,
        y: 50,
        zIndex: 5005,
      );

      expect(Stroke.fromJson(jsonDecode(jsonEncode(stroke.toJson())) as Map<String, dynamic>).zIndex, 1001);
      expect(ImageElement.fromJson(jsonDecode(jsonEncode(img.toJson())) as Map<String, dynamic>).zIndex, 2002);
      expect(StickyNoteElement.fromJson(jsonDecode(jsonEncode(sticky.toJson())) as Map<String, dynamic>).zIndex, 3003);
      expect(TextElement.fromJson(jsonDecode(jsonEncode(txt.toJson())) as Map<String, dynamic>).zIndex, 4004);
      expect(StencilElement.fromJson(jsonDecode(jsonEncode(stencil.toJson())) as Map<String, dynamic>).zIndex, 5005);

      // Safe default 0 when legacy JSON omits zIndex
      expect(Stroke.fromJson({'id': 'legacy-s'}).zIndex, 0);
      expect(ImageElement.fromJson({'id': 'legacy-i', 'x': 0, 'y': 0}).zIndex, 0);
    });

    test('v3.5.0 StickyNoteElement.isTransparent and Notebook.drivePdfFileId round-trip', () {
      final now = DateTime.utc(2026, 8, 1, 10, 0);
      final sticky = StickyNoteElement(
        id: 'st-trans',
        x: 50,
        y: 60,
        text: 'Transparent sticky note',
        isTransparent: true,
        updatedAt: now,
      );
      final decodedSticky = StickyNoteElement.fromJson(
        jsonDecode(jsonEncode(sticky.toJson())) as Map<String, dynamic>,
      );
      expect(decodedSticky.isTransparent, isTrue);
      expect(StickyNoteElement.fromJson({'id': 'st-def', 'x': 0, 'y': 0}).isTransparent, isFalse);

      final nb = Notebook(
        id: 'nb-pdf-sync',
        title: 'Hóa Hữu Cơ Drive PDF',
        createdAt: now,
        updatedAt: now,
        driveFileId: 'drive-json-123',
        drivePdfFileId: 'drive-pdf-456',
      );
      final decodedNb = Notebook.fromJson(
        jsonDecode(jsonEncode(nb.toJson())) as Map<String, dynamic>,
      );
      expect(decodedNb.driveFileId, 'drive-json-123');
      expect(decodedNb.drivePdfFileId, 'drive-pdf-456');
      expect(decodedNb.copyWith(clearDrivePdfFileId: true).drivePdfFileId, isNull);
      expect(Notebook.fromJson({'id': 'nb-leg', 'title': 'Legacy'}).drivePdfFileId, isNull);
    });
  });
}
