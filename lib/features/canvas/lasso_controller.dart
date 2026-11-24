import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/drawing_elements.dart';
import '../../core/models/note_page.dart';

/// Holds IDs of elements currently captured by the freeform lasso tool.
class LassoSelection {
  final Set<String> strokeIds;
  final Set<String> stencilIds;
  final Set<String> textIds;
  final Set<String> imageIds;
  final Set<String> tapeIds;
  final Set<String> stickyNoteIds;
  final Set<String> attachmentIds;

  const LassoSelection({
    this.strokeIds = const {},
    this.stencilIds = const {},
    this.textIds = const {},
    this.imageIds = const {},
    this.tapeIds = const {},
    this.stickyNoteIds = const {},
    this.attachmentIds = const {},
  });

  bool get isEmpty =>
      strokeIds.isEmpty &&
      stencilIds.isEmpty &&
      textIds.isEmpty &&
      imageIds.isEmpty &&
      tapeIds.isEmpty &&
      stickyNoteIds.isEmpty &&
      attachmentIds.isEmpty;

  bool get isNotEmpty => !isEmpty;

  int get totalCount =>
      strokeIds.length +
      stencilIds.length +
      textIds.length +
      imageIds.length +
      tapeIds.length +
      stickyNoteIds.length +
      attachmentIds.length;

  LassoSelection copyWith({
    Set<String>? strokeIds,
    Set<String>? stencilIds,
    Set<String>? textIds,
    Set<String>? imageIds,
    Set<String>? tapeIds,
    Set<String>? stickyNoteIds,
    Set<String>? attachmentIds,
  }) {
    return LassoSelection(
      strokeIds: strokeIds ?? this.strokeIds,
      stencilIds: stencilIds ?? this.stencilIds,
      textIds: textIds ?? this.textIds,
      imageIds: imageIds ?? this.imageIds,
      tapeIds: tapeIds ?? this.tapeIds,
      stickyNoteIds: stickyNoteIds ?? this.stickyNoteIds,
      attachmentIds: attachmentIds ?? this.attachmentIds,
    );
  }
}

/// Snapshot stored in memory for Cut / Copy / Paste across pages.
class LassoClipboard {
  final List<Stroke> strokes;
  final List<StencilElement> stencils;
  final List<TextElement> texts;
  final List<ImageElement> images;
  final List<TapeElement> tapes;
  final List<StickyNoteElement> stickyNotes;
  final List<AttachmentElement> attachments;

  const LassoClipboard({
    this.strokes = const [],
    this.stencils = const [],
    this.texts = const [],
    this.images = const [],
    this.tapes = const [],
    this.stickyNotes = const [],
    this.attachments = const [],
  });

  bool get isEmpty =>
      strokes.isEmpty &&
      stencils.isEmpty &&
      texts.isEmpty &&
      images.isEmpty &&
      tapes.isEmpty &&
      stickyNotes.isEmpty &&
      attachments.isEmpty;

  bool get isNotEmpty => !isEmpty;
}

/// Manages freeform lasso polygon drawing, point-in-polygon hit detection,
/// bounding box computation, clipboard (cut/copy/paste), and batch transforms
/// (move, uniform scale, rotate, recolor, duplicate, delete).
class LassoController extends ChangeNotifier {
  final List<Offset> _lassoPath = [];
  LassoSelection _selection = const LassoSelection();
  LassoClipboard _clipboard = const LassoClipboard();
  Rect? _selectionBounds;
  String? _activePageId;
  bool _isDrawingLasso = false;

  List<Offset> get lassoPath => List.unmodifiable(_lassoPath);
  LassoSelection get selection => _selection;
  LassoClipboard get clipboard => _clipboard;
  Rect? get selectionBounds => _selectionBounds;
  String? get activePageId => _activePageId;
  bool get isDrawingLasso => _isDrawingLasso;
  bool get hasSelection => _selection.isNotEmpty;
  bool get hasClipboard => _clipboard.isNotEmpty;

  void startLasso(Offset startPoint, {String? pageId}) {
    _lassoPath
      ..clear()
      ..add(startPoint);
    _selection = const LassoSelection();
    _selectionBounds = null;
    _activePageId = pageId;
    _isDrawingLasso = true;
    notifyListeners();
  }

  void updateLasso(Offset point) {
    if (!_isDrawingLasso) return;
    if (_lassoPath.isEmpty || (_lassoPath.last - point).distance >= 4.0) {
      _lassoPath.add(point);
      notifyListeners();
    }
  }

  /// Closes the lasso polygon and selects all elements on [page] inside it.
  LassoSelection finishLasso(NotePage page) {
    _isDrawingLasso = false;
    _activePageId = page.id;
    if (_lassoPath.length < 3) {
      _lassoPath.clear();
      _selection = const LassoSelection();
      _selectionBounds = null;
      notifyListeners();
      return _selection;
    }

    final selectedStrokes = <String>{};
    final selectedStencils = <String>{};
    final selectedTexts = <String>{};
    final selectedImages = <String>{};
    final selectedTapes = <String>{};
    final selectedStickyNotes = <String>{};
    final selectedAttachments = <String>{};

    for (final stroke in page.strokes) {
      if (stroke.points.isEmpty) continue;
      int insideCount = 0;
      for (final p in stroke.points) {
        if (isPointInPolygon(Offset(p.x, p.y), _lassoPath)) {
          insideCount++;
        }
      }
      if (insideCount > 0 &&
          (insideCount / stroke.points.length >= 0.35 || insideCount >= 3)) {
        selectedStrokes.add(stroke.id);
      }
    }

    for (final stencil in page.stencilElements) {
      final center = Offset(
        stencil.x + stencil.width * 0.5,
        stencil.y + stencil.height * 0.5,
      );
      if (isPointInPolygon(center, _lassoPath)) {
        selectedStencils.add(stencil.id);
      }
    }

    for (final text in page.textElements) {
      final center = Offset(
        text.x + text.width * 0.5,
        text.y + text.height * 0.5,
      );
      if (isPointInPolygon(center, _lassoPath)) {
        selectedTexts.add(text.id);
      }
    }

    for (final img in page.imageElements) {
      final center = Offset(
        img.x + img.width * 0.5,
        img.y + img.height * 0.5,
      );
      if (isPointInPolygon(center, _lassoPath)) {
        selectedImages.add(img.id);
      }
    }

    for (final tape in page.tapeElements) {
      final center = Offset(
        tape.x + tape.width * 0.5,
        tape.y + tape.height * 0.5,
      );
      if (isPointInPolygon(center, _lassoPath)) {
        selectedTapes.add(tape.id);
      }
    }

    for (final sticky in page.stickyNotes) {
      final double sw = sticky.isCollapsed ? math.min(sticky.width, 210.0) : sticky.width;
      final double sh = sticky.isCollapsed ? 40.0 : sticky.height;
      final center = Offset(sticky.x + sw * 0.5, sticky.y + sh * 0.5);
      if (isPointInPolygon(center, _lassoPath)) {
        selectedStickyNotes.add(sticky.id);
      }
    }

    for (final att in page.attachmentElements) {
      final center = Offset(att.x + att.width * 0.5, att.y + att.height * 0.5);
      if (isPointInPolygon(center, _lassoPath)) {
        selectedAttachments.add(att.id);
      }
    }

    _selection = LassoSelection(
      strokeIds: selectedStrokes,
      stencilIds: selectedStencils,
      textIds: selectedTexts,
      imageIds: selectedImages,
      tapeIds: selectedTapes,
      stickyNoteIds: selectedStickyNotes,
      attachmentIds: selectedAttachments,
    );

    _lassoPath.clear();
    _selectionBounds = computeBounds(page, _selection);
    notifyListeners();
    return _selection;
  }

  void clear() {
    _lassoPath.clear();
    _selection = const LassoSelection();
    _selectionBounds = null;
    _isDrawingLasso = false;
    notifyListeners();
  }

  bool hitTestSelectionBounds(Offset point, {double padding = 10.0}) {
    final bounds = _selectionBounds;
    if (bounds == null || _selection.isEmpty) return false;
    return bounds.inflate(padding).contains(point);
  }

  /// Standard ray-casting point-in-polygon test.
  static bool isPointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      final xi = polygon[i].dx;
      final yi = polygon[i].dy;
      final xj = polygon[j].dx;
      final yj = polygon[j].dy;

      final intersect = ((yi > point.dy) != (yj > point.dy)) &&
          (point.dx <
              (xj - xi) * (point.dy - yi) / ((yj - yi) == 0 ? 1e-9 : (yj - yi)) +
                  xi);
      if (intersect) inside = !inside;
      j = i;
    }
    return inside;
  }

  /// Computes combined bounding box of all currently selected elements.
  static Rect? computeBounds(NotePage page, LassoSelection sel) {
    if (sel.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;

    void includePoint(double x, double y) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    void includeRect(double x, double y, double w, double h) {
      includePoint(x, y);
      includePoint(x + w, y + h);
    }

    for (final s in page.strokes) {
      if (!sel.strokeIds.contains(s.id)) continue;
      final halfW = s.width * 0.5;
      for (final p in s.points) {
        includePoint(p.x - halfW, p.y - halfW);
        includePoint(p.x + halfW, p.y + halfW);
      }
    }

    for (final st in page.stencilElements) {
      if (!sel.stencilIds.contains(st.id)) continue;
      includeRect(st.x, st.y, st.width, st.height);
    }

    for (final t in page.textElements) {
      if (!sel.textIds.contains(t.id)) continue;
      includeRect(t.x, t.y, t.width, t.height);
    }

    for (final img in page.imageElements) {
      if (!sel.imageIds.contains(img.id)) continue;
      includeRect(img.x, img.y, img.width, img.height);
    }

    for (final tape in page.tapeElements) {
      if (!sel.tapeIds.contains(tape.id)) continue;
      includeRect(tape.x, tape.y, tape.width, tape.height);
    }

    for (final sticky in page.stickyNotes) {
      if (!sel.stickyNoteIds.contains(sticky.id)) continue;
      final double sw = sticky.isCollapsed ? math.min(sticky.width, 210.0) : sticky.width;
      final double sh = sticky.isCollapsed ? 40.0 : sticky.height;
      includeRect(sticky.x, sticky.y, sw, sh);
    }

    for (final att in page.attachmentElements) {
      if (!sel.attachmentIds.contains(att.id)) continue;
      includeRect(att.x, att.y, att.width, att.height);
    }

    if (!minX.isFinite || !minY.isFinite) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(8.0);
  }

  /// Copies currently selected elements to the internal clipboard.
  void copySelection(NotePage page) {
    if (_selection.isEmpty) return;
    _clipboard = LassoClipboard(
      strokes: page.strokes
          .where((s) => _selection.strokeIds.contains(s.id))
          .toList(),
      stencils: page.stencilElements
          .where((st) => _selection.stencilIds.contains(st.id))
          .toList(),
      texts: page.textElements
          .where((t) => _selection.textIds.contains(t.id))
          .toList(),
      images: page.imageElements
          .where((img) => _selection.imageIds.contains(img.id))
          .toList(),
      tapes: page.tapeElements
          .where((tp) => _selection.tapeIds.contains(tp.id))
          .toList(),
      stickyNotes: page.stickyNotes
          .where((sn) => _selection.stickyNoteIds.contains(sn.id))
          .toList(),
      attachments: page.attachmentElements
          .where((att) => _selection.attachmentIds.contains(att.id))
          .toList(),
    );
    notifyListeners();
  }

  /// Cuts currently selected elements (copies to clipboard and removes from [page]).
  NotePage cutSelection(NotePage page) {
    copySelection(page);
    return deleteSelection(page);
  }

  /// Pastes clipboard contents onto [page] with a slight offset and selects them.
  NotePage pasteClipboard(
    NotePage page, {
    required String Function() idGenerator,
    Offset offset = const Offset(28.0, 28.0),
  }) {
    if (_clipboard.isEmpty) return page;

    final newStrokeIds = <String>{};
    final newStencilIds = <String>{};
    final newTextIds = <String>{};
    final newImageIds = <String>{};
    final newTapeIds = <String>{};
    final newStickyNoteIds = <String>{};
    final newAttachmentIds = <String>{};

    final addedStrokes = _clipboard.strokes.map((s) {
      final id = idGenerator();
      newStrokeIds.add(id);
      return s.copyWith(
        id: id,
        points: s.points
            .map((p) => p.copyWith(x: p.x + offset.dx, y: p.y + offset.dy))
            .toList(),
      );
    }).toList();

    final addedStencils = _clipboard.stencils.map((st) {
      final id = idGenerator();
      newStencilIds.add(id);
      return st.copyWith(id: id, x: st.x + offset.dx, y: st.y + offset.dy);
    }).toList();

    final addedTexts = _clipboard.texts.map((t) {
      final id = idGenerator();
      newTextIds.add(id);
      return t.copyWith(id: id, x: t.x + offset.dx, y: t.y + offset.dy);
    }).toList();

    final addedImages = _clipboard.images.map((img) {
      final id = idGenerator();
      newImageIds.add(id);
      return img.copyWith(id: id, x: img.x + offset.dx, y: img.y + offset.dy);
    }).toList();

    final addedTapes = _clipboard.tapes.map((tp) {
      final id = idGenerator();
      newTapeIds.add(id);
      return tp.copyWith(id: id, x: tp.x + offset.dx, y: tp.y + offset.dy);
    }).toList();

    final addedStickyNotes = _clipboard.stickyNotes.map((sn) {
      final id = idGenerator();
      newStickyNoteIds.add(id);
      return sn.copyWith(
        id: id,
        x: sn.x + offset.dx,
        y: sn.y + offset.dy,
        updatedAt: DateTime.now(),
      );
    }).toList();

    final addedAttachments = _clipboard.attachments.map((att) {
      final id = idGenerator();
      newAttachmentIds.add(id);
      return att.copyWith(id: id, x: att.x + offset.dx, y: att.y + offset.dy);
    }).toList();

    final updatedPage = page.copyWith(
      strokes: [...page.strokes, ...addedStrokes],
      stencilElements: [...page.stencilElements, ...addedStencils],
      textElements: [...page.textElements, ...addedTexts],
      imageElements: [...page.imageElements, ...addedImages],
      tapeElements: [...page.tapeElements, ...addedTapes],
      stickyNotes: [...page.stickyNotes, ...addedStickyNotes],
      attachmentElements: [...page.attachmentElements, ...addedAttachments],
      updatedAt: DateTime.now(),
    );

    _activePageId = page.id;
    _selection = LassoSelection(
      strokeIds: newStrokeIds,
      stencilIds: newStencilIds,
      textIds: newTextIds,
      imageIds: newImageIds,
      tapeIds: newTapeIds,
      stickyNoteIds: newStickyNoteIds,
      attachmentIds: newAttachmentIds,
    );
    _selectionBounds = computeBounds(updatedPage, _selection);
    notifyListeners();
    return updatedPage;
  }

  /// Translates all selected elements by [delta].
  NotePage moveSelection(NotePage page, Offset delta) {
    if (_selection.isEmpty || delta == Offset.zero) return page;

    final updatedStrokes = page.strokes.map((s) {
      if (!_selection.strokeIds.contains(s.id)) return s;
      return s.copyWith(
        points: s.points
            .map((p) => p.copyWith(x: p.x + delta.dx, y: p.y + delta.dy))
            .toList(),
      );
    }).toList();

    final updatedStencils = page.stencilElements.map((st) {
      if (!_selection.stencilIds.contains(st.id)) return st;
      return st.copyWith(x: st.x + delta.dx, y: st.y + delta.dy);
    }).toList();

    final updatedTexts = page.textElements.map((t) {
      if (!_selection.textIds.contains(t.id)) return t;
      return t.copyWith(x: t.x + delta.dx, y: t.y + delta.dy);
    }).toList();

    final updatedImages = page.imageElements.map((img) {
      if (!_selection.imageIds.contains(img.id)) return img;
      return img.copyWith(x: img.x + delta.dx, y: img.y + delta.dy);
    }).toList();

    final updatedTapes = page.tapeElements.map((tp) {
      if (!_selection.tapeIds.contains(tp.id)) return tp;
      return tp.copyWith(x: tp.x + delta.dx, y: tp.y + delta.dy);
    }).toList();

    final updatedStickyNotes = page.stickyNotes.map((sn) {
      if (!_selection.stickyNoteIds.contains(sn.id)) return sn;
      return sn.copyWith(x: sn.x + delta.dx, y: sn.y + delta.dy);
    }).toList();

    final updatedAttachments = page.attachmentElements.map((att) {
      if (!_selection.attachmentIds.contains(att.id)) return att;
      return att.copyWith(x: att.x + delta.dx, y: att.y + delta.dy);
    }).toList();

    final updatedPage = page.copyWith(
      strokes: updatedStrokes,
      stencilElements: updatedStencils,
      textElements: updatedTexts,
      imageElements: updatedImages,
      tapeElements: updatedTapes,
      stickyNotes: updatedStickyNotes,
      attachmentElements: updatedAttachments,
      updatedAt: DateTime.now(),
    );

    _selectionBounds = computeBounds(updatedPage, _selection);
    notifyListeners();
    return updatedPage;
  }

  /// Uniformly scales all selected elements around [pivot].
  NotePage scaleSelection(
    NotePage page,
    double scaleFactor, {
    Offset? pivot,
  }) {
    if (_selection.isEmpty) return page;
    final clampedScale = scaleFactor.clamp(0.25, 4.0);
    final origin = pivot ?? _selectionBounds?.center ?? Offset.zero;

    final updatedStrokes = page.strokes.map((s) {
      if (!_selection.strokeIds.contains(s.id)) return s;
      return s.copyWith(
        width: (s.width * clampedScale).clamp(0.8, 60.0),
        points: s.points
            .map((p) => p.copyWith(
                  x: origin.dx + (p.x - origin.dx) * clampedScale,
                  y: origin.dy + (p.y - origin.dy) * clampedScale,
                ))
            .toList(),
      );
    }).toList();

    final updatedStencils = page.stencilElements.map((st) {
      if (!_selection.stencilIds.contains(st.id)) return st;
      return st.copyWith(
        x: origin.dx + (st.x - origin.dx) * clampedScale,
        y: origin.dy + (st.y - origin.dy) * clampedScale,
        width: math.max(24.0, st.width * clampedScale),
        height: math.max(24.0, st.height * clampedScale),
      );
    }).toList();

    final updatedTexts = page.textElements.map((t) {
      if (!_selection.textIds.contains(t.id)) return t;
      return t.copyWith(
        x: origin.dx + (t.x - origin.dx) * clampedScale,
        y: origin.dy + (t.y - origin.dy) * clampedScale,
        width: math.max(60.0, t.width * clampedScale),
        height: math.max(28.0, t.height * clampedScale),
        fontSize: (t.fontSize * clampedScale).clamp(10.0, 72.0),
      );
    }).toList();

    final updatedImages = page.imageElements.map((img) {
      if (!_selection.imageIds.contains(img.id)) return img;
      return img.copyWith(
        x: origin.dx + (img.x - origin.dx) * clampedScale,
        y: origin.dy + (img.y - origin.dy) * clampedScale,
        width: math.max(36.0, img.width * clampedScale),
        height: math.max(36.0, img.height * clampedScale),
      );
    }).toList();

    final updatedTapes = page.tapeElements.map((tp) {
      if (!_selection.tapeIds.contains(tp.id)) return tp;
      return tp.copyWith(
        x: origin.dx + (tp.x - origin.dx) * clampedScale,
        y: origin.dy + (tp.y - origin.dy) * clampedScale,
        width: math.max(24.0, tp.width * clampedScale),
        height: math.max(16.0, tp.height * clampedScale),
      );
    }).toList();

    final updatedStickyNotes = page.stickyNotes.map((sn) {
      if (!_selection.stickyNoteIds.contains(sn.id)) return sn;
      return sn.copyWith(
        x: origin.dx + (sn.x - origin.dx) * clampedScale,
        y: origin.dy + (sn.y - origin.dy) * clampedScale,
        width: math.max(140.0, sn.width * clampedScale),
        height: math.max(110.0, sn.height * clampedScale),
      );
    }).toList();

    final updatedAttachments = page.attachmentElements.map((att) {
      if (!_selection.attachmentIds.contains(att.id)) return att;
      return att.copyWith(
        x: origin.dx + (att.x - origin.dx) * clampedScale,
        y: origin.dy + (att.y - origin.dy) * clampedScale,
        width: math.max(140.0, att.width * clampedScale),
        height: math.max(48.0, att.height * clampedScale),
      );
    }).toList();

    final updatedPage = page.copyWith(
      strokes: updatedStrokes,
      stencilElements: updatedStencils,
      textElements: updatedTexts,
      imageElements: updatedImages,
      tapeElements: updatedTapes,
      stickyNotes: updatedStickyNotes,
      attachmentElements: updatedAttachments,
      updatedAt: DateTime.now(),
    );

    _selectionBounds = computeBounds(updatedPage, _selection);
    notifyListeners();
    return updatedPage;
  }

  /// Rotates all selected strokes and stencils around [pivot] by [deltaRad].
  NotePage rotateSelection(
    NotePage page,
    double deltaRad, {
    Offset? pivot,
  }) {
    if (_selection.isEmpty || deltaRad == 0.0) return page;
    final origin = pivot ?? _selectionBounds?.center ?? Offset.zero;
    final cosA = math.cos(deltaRad);
    final sinA = math.sin(deltaRad);

    Offset rotatePt(double x, double y) {
      final dx = x - origin.dx;
      final dy = y - origin.dy;
      return Offset(
        origin.dx + dx * cosA - dy * sinA,
        origin.dy + dx * sinA + dy * cosA,
      );
    }

    final updatedStrokes = page.strokes.map((s) {
      if (!_selection.strokeIds.contains(s.id)) return s;
      return s.copyWith(
        points: s.points.map((p) {
          final rp = rotatePt(p.x, p.y);
          return p.copyWith(x: rp.dx, y: rp.dy);
        }).toList(),
      );
    }).toList();

    final updatedStencils = page.stencilElements.map((st) {
      if (!_selection.stencilIds.contains(st.id)) return st;
      final c = rotatePt(st.x + st.width * 0.5, st.y + st.height * 0.5);
      return st.copyWith(
        x: c.dx - st.width * 0.5,
        y: c.dy - st.height * 0.5,
        rotation: st.rotation + deltaRad,
      );
    }).toList();

    final updatedImages = page.imageElements.map((img) {
      if (!_selection.imageIds.contains(img.id)) return img;
      final c = rotatePt(img.x + img.width * 0.5, img.y + img.height * 0.5);
      return img.copyWith(
        x: c.dx - img.width * 0.5,
        y: c.dy - img.height * 0.5,
        rotation: img.rotation + deltaRad,
      );
    }).toList();

    final updatedPage = page.copyWith(
      strokes: updatedStrokes,
      stencilElements: updatedStencils,
      imageElements: updatedImages,
      updatedAt: DateTime.now(),
    );

    _selectionBounds = computeBounds(updatedPage, _selection);
    notifyListeners();
    return updatedPage;
  }

  /// Recolors all selected strokes, text boxes, stencils, and study tapes.
  NotePage recolorSelection(NotePage page, int colorValue) {
    if (_selection.isEmpty) return page;

    final updatedStrokes = page.strokes.map((s) {
      if (!_selection.strokeIds.contains(s.id)) return s;
      return s.copyWith(colorValue: colorValue);
    }).toList();

    final updatedStencils = page.stencilElements.map((st) {
      if (!_selection.stencilIds.contains(st.id)) return st;
      return st.copyWith(colorValue: colorValue);
    }).toList();

    final updatedTexts = page.textElements.map((t) {
      if (!_selection.textIds.contains(t.id)) return t;
      return t.copyWith(colorValue: colorValue);
    }).toList();

    final updatedTapes = page.tapeElements.map((tp) {
      if (!_selection.tapeIds.contains(tp.id)) return tp;
      return tp.copyWith(colorValue: colorValue);
    }).toList();

    final updatedPage = page.copyWith(
      strokes: updatedStrokes,
      stencilElements: updatedStencils,
      textElements: updatedTexts,
      tapeElements: updatedTapes,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    return updatedPage;
  }

  /// Duplicates all selected elements offset by [offset] and switches selection
  /// to the newly created duplicates.
  NotePage duplicateSelection(
    NotePage page, {
    required String Function() idGenerator,
    Offset offset = const Offset(24.0, 24.0),
  }) {
    if (_selection.isEmpty) return page;
    copySelection(page);
    return pasteClipboard(page, idGenerator: idGenerator, offset: offset);
  }

  /// Removes all currently selected elements from [page] and clears selection.
  NotePage deleteSelection(NotePage page) {
    if (_selection.isEmpty) return page;

    final updatedPage = page.copyWith(
      strokes: page.strokes
          .where((s) => !_selection.strokeIds.contains(s.id))
          .toList(),
      stencilElements: page.stencilElements
          .where((st) => !_selection.stencilIds.contains(st.id))
          .toList(),
      textElements: page.textElements
          .where((t) => !_selection.textIds.contains(t.id))
          .toList(),
      imageElements: page.imageElements
          .where((img) => !_selection.imageIds.contains(img.id))
          .toList(),
      tapeElements: page.tapeElements
          .where((tp) => !_selection.tapeIds.contains(tp.id))
          .toList(),
      stickyNotes: page.stickyNotes
          .where((sn) => !_selection.stickyNoteIds.contains(sn.id))
          .toList(),
      attachmentElements: page.attachmentElements
          .where((att) => !_selection.attachmentIds.contains(att.id))
          .toList(),
      updatedAt: DateTime.now(),
    );

    clear();
    return updatedPage;
  }
}
