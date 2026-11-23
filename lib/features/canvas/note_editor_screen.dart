import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/drawing_elements.dart';
import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../core/providers/app_state.dart';
import '../../core/services/app_updater_service.dart';
import '../../core/services/hardware_service.dart';
import '../chemistry/chemistry_hub_sheet.dart';
import '../chemistry/widgets/stencil_picker_sheet.dart';
import '../library/search_screen.dart';
import '../pdf/pdf_export_service.dart';
import '../pdf/pdf_import_service.dart';
import 'canvas_painter.dart';
import 'editor_toolbar.dart';
import 'image_crop_dialog.dart';
import 'lasso_controller.dart';
import 'paper_templates.dart';
import 'pro_tools_overlay.dart';
import 'stroke_engine.dart';

/// Huawei Notes × GoodNotes 6 Pro Note Editor optimized for
/// Huawei MatePad 11.5"S (144Hz PaperMatte) + M-Pencil 3 (NearLink).
class NoteEditorScreen extends StatefulWidget {
  final String notebookId;
  final int initialPageIndex;

  const NoteEditorScreen({
    super.key,
    required this.notebookId,
    this.initialPageIndex = 0,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Uuid _uuid = const Uuid();
  final TransformationController _transformController = TransformationController();
  final ScrollController _verticalScrollController = ScrollController();
  late PageController _horizontalPageController;
  final LassoController _lassoController = LassoController();
  final PalmRejectionFilter _palmFilter = PalmRejectionFilter(stylusOnlyMode: false);
  final LaserPointerController _laserController = LaserPointerController();
  final ImagePicker _imagePicker = ImagePicker();
  final PdfImportService _pdfImportService = PdfImportService();
  final PdfExportService _pdfExportService = PdfExportService();

  // 144Hz zero-rebuild ValueNotifiers for ActiveStrokePainter
  final ValueNotifier<Stroke?> _activeStrokeNotifier = ValueNotifier(null);
  final ValueNotifier<Offset?> _hoverPosNotifier = ValueNotifier(null);
  final ValueNotifier<Offset?> _eraserCursorNotifier = ValueNotifier(null);
  final ValueNotifier<List<Offset>> _lassoPathNotifier = ValueNotifier(const []);
  final ValueNotifier<Rect?> _tapeDraftNotifier = ValueNotifier(null);

  // Active notebook & page state
  late String _activeNotebookId;
  int _currentPageIndex = 0;
  String? _activeDrawingPageId;
  int _repaintVersion = 0;
  double _refreshRateHz = 60.0;
  StreamSubscription<void>? _stylusDoubleTapSub;

  // Pull-to-add-page state
  double _pullOverscroll = 0.0;
  bool _isAddingPullPage = false;

  // Tool & ink configuration
  EditorTool _activeTool = EditorTool.fountainPen;
  EditorTool _lastPenTool = EditorTool.fountainPen;
  EditorTool _toolBeforeEraserToggle = EditorTool.fountainPen;
  EraserMode _eraserMode = EraserMode.stroke;
  Color _penColor = EditorColors.penSwatches[2];
  Color _highlighterColor = EditorColors.highlighterSwatches.first;
  double _penWidth = 2.6;
  double _highlighterWidth = 18.0;
  double _penOpacity = 1.0;
  double _highlighterOpacity = 0.45;
  double _pressureSensitivity = 0.75;
  bool _eyedropperActive = false;
  bool _isDrawingPointerDown = false;

  // Smoothing & M-Pencil 3 curve
  bool _autoNeatenEnabled = true;
  double _smoothingStrength = 0.55;
  double get _pressureGamma => (1.5 - _pressureSensitivity * 0.9).clamp(0.5, 1.5);
  Timer? _shapeHoldTimer;
  Offset? _lastHoldCheckPos;

  // Pro tools state
  bool _zoomWindowEnabled = false;
  Rect _zoomFocusRect = const Rect.fromLTWH(80, 140, 260, 110);
  bool _rulerVisible = false;
  final RulerState _rulerState = RulerState();

  // Gesture tracking (including 2-finger Undo / 3-finger Redo)
  final Map<int, Offset> _pointerDownPositions = {};
  DateTime? _multiFingerDownTime;
  int _maxSimultaneousPointers = 0;
  bool _multiFingerMovedTooMuch = false;
  bool _isDraggingLassoSelection = false;
  Offset? _lastLassoDragPos;
  Offset? _tapeDragStart;
  bool _eraserChangedPage = false;
  NotePage? _pageBeforeGesture;

  // Undo / Redo per page
  final Map<String, List<NotePage>> _undoStacks = {};
  final Map<String, List<NotePage>> _redoStacks = {};
  static const int _maxHistory = 40;

  // Interactive overlay selection (Text, Image, Stencil)
  String? _selectedTextId;
  String? _editingTextId;
  String? _selectedImageId;
  String? _selectedStencilId;
  TextEditingController? _activeTextController;
  FocusNode? _activeTextFocusNode;

  // Cached decoded PDF background & full-res ImageElement images
  final Map<String, ui.Image> _pdfImageCache = {};
  final Set<String> _loadingPdfPaths = {};
  final Map<String, ui.Image> _elementImageCache = {};
  final Set<String> _loadingElementImagePaths = {};
  bool _isBusyPdf = false;

  // Audio Note Recording & Synced Stroke Replay state
  bool _isRecordingAudio = false;
  String? _activeRecordingId;
  String? _activeRecordingPath;
  int _recordingStartMs = 0;
  String? _playingAudioId;
  bool _isAudioPlaying = false;
  int _audioPositionMs = 0;
  double _audioSpeed = 1.0;
  Timer? _audioPollTimer;

  Color get _effectiveColor =>
      _activeTool == EditorTool.highlighter ? _highlighterColor : _penColor;

  double get _effectiveWidth =>
      _activeTool == EditorTool.highlighter ? _highlighterWidth : _penWidth;

  double get _effectiveOpacity =>
      _activeTool == EditorTool.highlighter ? _highlighterOpacity : _penOpacity;

  @override
  void initState() {
    super.initState();
    _activeNotebookId = widget.notebookId;
    _currentPageIndex = widget.initialPageIndex;
    _horizontalPageController = PageController(initialPage: _currentPageIndex);
    _lassoController.addListener(_onLassoChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().openTab(_activeNotebookId);
    });

    _initHardwareBridge();
  }

  Future<void> _initHardwareBridge() async {
    final hz = await HardwareService.instance.getRefreshRate();
    if (mounted) {
      setState(() => _refreshRateHz = hz);
    }
    _stylusDoubleTapSub =
        HardwareService.instance.onStylusDoubleTap.listen((_) {
      if (!mounted) return;
      final appState = context.read<AppState>();
      if (!appState.mPencilDoubleTapEraser) return;
      setState(() {
        if (_activeTool == EditorTool.eraser) {
          _activeTool = _toolBeforeEraserToggle;
        } else {
          _toolBeforeEraserToggle = _activeTool;
          _activeTool = EditorTool.eraser;
        }
      });
    });
  }

  @override
  void dispose() {
    _shapeHoldTimer?.cancel();
    _audioPollTimer?.cancel();
    HardwareService.instance.stopAudio();
    _stylusDoubleTapSub?.cancel();
    _lassoController.removeListener(_onLassoChanged);
    _lassoController.dispose();
    _laserController.dispose();
    _transformController.dispose();
    _verticalScrollController.dispose();
    _horizontalPageController.dispose();
    _activeStrokeNotifier.dispose();
    _hoverPosNotifier.dispose();
    _eraserCursorNotifier.dispose();
    _lassoPathNotifier.dispose();
    _tapeDraftNotifier.dispose();
    _activeTextController?.dispose();
    _activeTextFocusNode?.dispose();
    for (final img in _pdfImageCache.values) {
      img.dispose();
    }
    for (final img in _elementImageCache.values) {
      img.dispose();
    }
    super.dispose();
  }

  void _onLassoChanged() {
    _lassoPathNotifier.value = List<Offset>.from(_lassoController.lassoPath);
    if (mounted) setState(() => _repaintVersion++);
  }

  // ===========================================================================
  // PAGE ACCESS, MULTI-TAB & UNDO/REDO HELPERS
  // ===========================================================================

  Notebook? _getNotebook(BuildContext context, {bool listen = true}) {
    final appState =
        listen ? context.watch<AppState>() : context.read<AppState>();
    return appState.getNotebookById(_activeNotebookId);
  }

  NotePage? _getCurrentPage(Notebook? notebook) {
    if (notebook == null || notebook.pages.isEmpty) return null;
    final idx = _currentPageIndex.clamp(0, notebook.pages.length - 1);
    return notebook.pages[idx];
  }

  List<NotePage> _undoFor(String pageId) =>
      _undoStacks.putIfAbsent(pageId, () => <NotePage>[]);
  List<NotePage> _redoFor(String pageId) =>
      _redoStacks.putIfAbsent(pageId, () => <NotePage>[]);

  void _pushUndo(NotePage snapshot) {
    final stack = _undoFor(snapshot.id);
    stack.add(snapshot);
    if (stack.length > _maxHistory) stack.removeAt(0);
    _redoFor(snapshot.id).clear();
  }

  Future<void> _commitPage(
    NotePage updatedPage, {
    NotePage? undoSnapshot,
  }) async {
    if (undoSnapshot != null) _pushUndo(undoSnapshot);
    await context.read<AppState>().updatePage(_activeNotebookId, updatedPage);
    if (mounted) setState(() => _repaintVersion++);
  }

  Future<void> _undo(NotePage currentPage) async {
    final stack = _undoFor(currentPage.id);
    if (stack.isEmpty) return;
    final previous = stack.removeLast();
    _redoFor(currentPage.id).add(currentPage);
    _lassoController.clear();
    await context.read<AppState>().updatePage(_activeNotebookId, previous);
    if (mounted) setState(() => _repaintVersion++);
  }

  Future<void> _redo(NotePage currentPage) async {
    final stack = _redoFor(currentPage.id);
    if (stack.isEmpty) return;
    final next = stack.removeLast();
    _undoFor(currentPage.id).add(currentPage);
    _lassoController.clear();
    await context.read<AppState>().updatePage(_activeNotebookId, next);
    if (mounted) setState(() => _repaintVersion++);
  }

  void _switchNotebookTab(String notebookId) {
    if (notebookId == _activeNotebookId) return;
    _commitActiveTextEdit();
    setState(() {
      _activeNotebookId = notebookId;
      _currentPageIndex = 0;
      _lassoController.clear();
      _selectedTextId = null;
      _selectedImageId = null;
      _selectedStencilId = null;
      _activeStrokeNotifier.value = null;
      _repaintVersion++;
    });
    if (_horizontalPageController.hasClients) {
      _horizontalPageController.jumpToPage(0);
    }
    if (_verticalScrollController.hasClients) {
      _verticalScrollController.jumpTo(0);
    }
  }

  void _closeNotebookTab(String notebookId) {
    final appState = context.read<AppState>();
    final open = appState.openNotebooks;
    if (open.length <= 1) return;
    appState.closeTab(notebookId);
    if (notebookId == _activeNotebookId) {
      final remaining = appState.openNotebooks;
      if (remaining.isNotEmpty) {
        _switchNotebookTab(remaining.first.id);
      }
    }
  }

  void _jumpToPage(int index) {
    final appState = context.read<AppState>();
    setState(() => _currentPageIndex = index);
    if (!appState.verticalContinuousScroll &&
        _horizontalPageController.hasClients) {
      _horizontalPageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } else if (appState.verticalContinuousScroll &&
        _verticalScrollController.hasClients) {
      final targetOffset = index * (PaperMetrics.portraitHeight + 14.0);
      _verticalScrollController.animateTo(
        targetOffset.clamp(
          0.0,
          _verticalScrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ===========================================================================
  // PDF BACKGROUND IMAGE DECODING
  // ===========================================================================

  void _ensurePdfImageLoaded(String? path) {
    if (path == null || path.isEmpty) return;
    if (_pdfImageCache.containsKey(path) || _loadingPdfPaths.contains(path)) {
      return;
    }
    _loadingPdfPaths.add(path);
    _loadPdfImage(path);
  }

  Future<void> _loadPdfImage(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _pdfImageCache[path] = frame.image;
        _repaintVersion++;
      });
    } catch (_) {
      // Ignore missing/corrupt PDF page image
    } finally {
      _loadingPdfPaths.remove(path);
    }
  }

  void _ensureElementImageLoaded(String path) {
    if (path.isEmpty) return;
    if (_elementImageCache.containsKey(path) ||
        _loadingElementImagePaths.contains(path)) {
      return;
    }
    _loadingElementImagePaths.add(path);
    _loadElementImage(path);
  }

  Future<void> _loadElementImage(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _elementImageCache[path] = frame.image;
        _repaintVersion++;
      });
    } catch (_) {
      // Ignore missing/corrupt image file
    } finally {
      _loadingElementImagePaths.remove(path);
    }
  }

  // ===========================================================================
  // 144Hz POINTER, M-PENCIL 3 HOVER, 2/3-FINGER TAP & TOOL HANDLERS
  // ===========================================================================

  void _handlePointerHover(PointerHoverEvent event, NotePage page) {
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      _palmFilter.notifyStylusHover();
      _activeDrawingPageId = page.id;
      _hoverPosNotifier.value = event.localPosition;
    }
  }

  void _handlePointerDown(
    PointerDownEvent event,
    NotePage page,
    int pageIndex,
  ) {
    if (_currentPageIndex != pageIndex) {
      setState(() => _currentPageIndex = pageIndex);
    }
    _activeDrawingPageId = page.id;

    // Track multi-finger gestures (2-finger Undo / 3-finger Redo)
    _pointerDownPositions[event.pointer] = event.position;
    if (_pointerDownPositions.length == 1) {
      _multiFingerDownTime = DateTime.now();
      _maxSimultaneousPointers = 1;
      _multiFingerMovedTooMuch = false;
    } else {
      if (_pointerDownPositions.length > _maxSimultaneousPointers) {
        _maxSimultaneousPointers = _pointerDownPositions.length;
      }
      _cancelActiveGesture();
      return;
    }

    final appState = context.read<AppState>();
    _palmFilter.stylusOnlyMode = appState.palmRejectionEnabled;

    if (appState.readOnlyMode || _activeTool == EditorTool.panZoom) return;

    final rawPos = event.localPosition;

    // Hit-test images ONLY when EditorTool.image is active!
    // When Pen / Highlighter / Eraser / Shape / Tape is active, let the user write directly ON TOP of images!
    if (_activeTool == EditorTool.image) {
      final hitImage = _findImageAt(page, rawPos);
      setState(() {
        _selectedImageId = hitImage?.id;
        _selectedTextId = null;
        _selectedStencilId = null;
      });
      return;
    }

    // Eyedropper sampling: pick color from tapped stroke, stencil, or paper
    if (_eyedropperActive) {
      Color sampled = PaperPalette.of(page.paperColor).background;
      for (int i = page.strokes.length - 1; i >= 0; i--) {
        if (StrokeEngine.hitTestStroke(page.strokes[i], rawPos, tolerance: 14)) {
          sampled = Color(page.strokes[i].colorValue).withAlpha(255);
          break;
        }
      }
      for (int i = page.stencilElements.length - 1; i >= 0; i--) {
        final st = page.stencilElements[i];
        if (Rect.fromLTWH(st.x, st.y, st.width, st.height).contains(rawPos)) {
          sampled = Color(st.colorValue).withAlpha(255);
          break;
        }
      }
      setState(() {
        _eyedropperActive = false;
        if (_activeTool == EditorTool.highlighter) {
          _highlighterColor = sampled;
        } else {
          _penColor = sampled;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 1100),
          content: Text('Đã hút màu từ trang ghi chú'),
        ),
      );
      return;
    }

    final pos = (_rulerVisible && _activeTool.isDrawingTool)
        ? _rulerState.snapPointIfNearEdge(rawPos)
        : rawPos;

    // Study Tape: tap existing tape to toggle reveal/hide, or drag to create new tape
    if (_activeTool == EditorTool.studyTape) {
      if (!_palmFilter.shouldAccept(event)) return;
      final hitTape = _findTapeAt(page, rawPos);
      if (hitTape != null) {
        final updatedTapes = page.tapeElements
            .map((t) =>
                t.id == hitTape.id ? t.copyWith(isRevealed: !t.isRevealed) : t)
            .toList();
        _commitPage(page.copyWith(tapeElements: updatedTapes));
        return;
      }
      _tapeDragStart = rawPos;
      _tapeDraftNotifier.value = Rect.fromPoints(rawPos, rawPos);
      return;
    }

    // Even in non-tape tools, tapping a Study Tape in read-only/pan mode reveals it
    if (_activeTool == EditorTool.laserPointer) {
      if (!_palmFilter.shouldAccept(event)) return;
      _laserController.addPoint(rawPos);
      return;
    }

    if (_activeTool == EditorTool.textBox) {
      if (!_palmFilter.shouldAccept(event)) return;
      _createTextElementAt(page, rawPos);
      return;
    }

    if (!_palmFilter.shouldAccept(event)) return;

    if (!_isDrawingPointerDown) {
      setState(() => _isDrawingPointerDown = true);
    }

    // Clear overlay selections when starting a stroke on empty paper
    if (_selectedTextId != null ||
        _selectedImageId != null ||
        _selectedStencilId != null ||
        _editingTextId != null) {
      _commitActiveTextEdit();
      setState(() {
        _selectedTextId = null;
        _selectedImageId = null;
        _selectedStencilId = null;
      });
    }

    if (_activeTool == EditorTool.lasso) {
      if (_lassoController.hasSelection &&
          _lassoController.activePageId == page.id &&
          _lassoController.hitTestSelectionBounds(rawPos)) {
        _isDraggingLassoSelection = true;
        _lastLassoDragPos = rawPos;
        _pageBeforeGesture = page;
      } else {
        _isDraggingLassoSelection = false;
        _lassoController.startLasso(rawPos, pageId: page.id);
      }
      return;
    }

    if (_activeTool == EditorTool.eraser) {
      _pageBeforeGesture = page;
      _eraserChangedPage = false;
      _eraserCursorNotifier.value = rawPos;
      _applyEraserAt(page, rawPos);
      return;
    }

    if (_activeTool.isDrawingTool) {
      final zoomScale = appState.zoomAdaptiveStroke
          ? _transformController.value.getMaxScaleOnAxis().clamp(0.5, 4.0)
          : 1.0;
      final firstPoint = StrokeEngine.pointFromEvent(
        event,
        pos,
        pressureGamma: _pressureGamma,
      );
      final effectiveInkColor = _effectiveColor.withAlpha(
        (_effectiveOpacity.clamp(0.1, 1.0) * 255).round(),
      );
      _activeStrokeNotifier.value = Stroke(
        id: _uuid.v4(),
        toolType: _activeTool.toStrokeToolType(),
        // ignore: deprecated_member_use
        colorValue: effectiveInkColor.value,
        width: _effectiveWidth / zoomScale,
        points: [firstPoint],
        isSmoothed: false,
        shapeType: ShapeType.none,
        audioId: _isRecordingAudio ? _activeRecordingId : null,
        audioTimeMs: _isRecordingAudio
            ? (DateTime.now().millisecondsSinceEpoch - _recordingStartMs)
            : null,
      );
      _lastHoldCheckPos = pos;
      _scheduleShapeHoldTimer();
    }
  }

  void _handlePointerMove(PointerMoveEvent event, NotePage page) {
    final startPos = _pointerDownPositions[event.pointer];
    if (startPos != null && (event.position - startPos).distance > 16.0) {
      _multiFingerMovedTooMuch = true;
    }

    if (_pointerDownPositions.length >= 2 ||
        context.read<AppState>().readOnlyMode ||
        _activeTool == EditorTool.panZoom) {
      return;
    }
    if (!_palmFilter.shouldAccept(event)) return;

    final rawPos = event.localPosition;
    final pos = (_rulerVisible && _activeTool.isDrawingTool)
        ? _rulerState.snapPointIfNearEdge(rawPos)
        : rawPos;

    if (_activeTool == EditorTool.studyTape && _tapeDragStart != null) {
      _tapeDraftNotifier.value = Rect.fromPoints(_tapeDragStart!, rawPos);
      return;
    }

    if (_activeTool == EditorTool.laserPointer) {
      _laserController.addPoint(rawPos);
      return;
    }

    if (_activeTool == EditorTool.lasso) {
      if (_isDraggingLassoSelection && _lastLassoDragPos != null) {
        final delta = rawPos - _lastLassoDragPos!;
        _lastLassoDragPos = rawPos;
        final movedPage = _lassoController.moveSelection(page, delta);
        context.read<AppState>().updatePage(_activeNotebookId, movedPage);
      } else if (_lassoController.isDrawingLasso) {
        _lassoController.updateLasso(rawPos);
      }
      return;
    }

    if (_activeTool == EditorTool.eraser) {
      _eraserCursorNotifier.value = rawPos;
      _applyEraserAt(page, rawPos);
      return;
    }

    final current = _activeStrokeNotifier.value;
    if (current != null && _activeTool.isDrawingTool) {
      final prev = current.points.isNotEmpty ? current.points.last : null;
      final incoming = StrokeEngine.pointFromEvent(
        event,
        pos,
        previousPoint: prev,
        pressureGamma: _pressureGamma,
      );
      final filtered = StrokeEngine.filterLivePoint(
        incoming,
        current.points,
        stabilization: _autoNeatenEnabled ? _smoothingStrength : 0.0,
      );
      if (filtered == null) return;

      _activeStrokeNotifier.value = current.copyWith(
        points: [...current.points, filtered],
        shapeType: ShapeType.none,
      );

      if (_lastHoldCheckPos == null ||
          (pos - _lastHoldCheckPos!).distance > 6.0) {
        _lastHoldCheckPos = pos;
        _scheduleShapeHoldTimer();
      }
    }
  }

  void _handlePointerUp(PointerEvent event, NotePage page) {
    _pointerDownPositions.remove(event.pointer);
    _shapeHoldTimer?.cancel();
    if (_pointerDownPositions.isEmpty && _isDrawingPointerDown) {
      setState(() => _isDrawingPointerDown = false);
    }

    // Check 2-finger tap Undo / 3-finger tap Redo when all fingers lift
    if (_pointerDownPositions.isEmpty &&
        _maxSimultaneousPointers >= 2 &&
        !_multiFingerMovedTooMuch &&
        _multiFingerDownTime != null) {
      final elapsed =
          DateTime.now().difference(_multiFingerDownTime!).inMilliseconds;
      final appState = context.read<AppState>();
      if (appState.quickGesturesEnabled && elapsed < 300) {
        if (_maxSimultaneousPointers == 2) {
          _undo(page);
        } else if (_maxSimultaneousPointers >= 3) {
          _redo(page);
        }
      }
      _maxSimultaneousPointers = 0;
      return;
    }

    if (_activeTool == EditorTool.studyTape && _tapeDragStart != null) {
      final rect = _tapeDraftNotifier.value;
      _tapeDragStart = null;
      _tapeDraftNotifier.value = null;
      if (rect != null && rect.width > 16 && rect.height > 12) {
        final newTape = TapeElement(
          id: _uuid.v4(),
          x: rect.left,
          y: rect.top,
          width: rect.width,
          height: math.max(24.0, rect.height),
          colorValue: 0xFF6366F1,
          isRevealed: false,
        );
        _commitPage(
          page.copyWith(tapeElements: [...page.tapeElements, newTape]),
          undoSnapshot: page,
        );
      }
      return;
    }

    if (_activeTool == EditorTool.laserPointer) {
      _laserController.endStroke();
      return;
    }

    if (_activeTool == EditorTool.lasso) {
      if (_isDraggingLassoSelection) {
        _isDraggingLassoSelection = false;
        _lastLassoDragPos = null;
        if (_pageBeforeGesture != null) {
          _pushUndo(_pageBeforeGesture!);
          _pageBeforeGesture = null;
        }
      } else if (_lassoController.isDrawingLasso) {
        _lassoController.finishLasso(page);
      }
      return;
    }

    if (_activeTool == EditorTool.eraser) {
      _eraserCursorNotifier.value = null;
      if (_eraserChangedPage && _pageBeforeGesture != null) {
        _pushUndo(_pageBeforeGesture!);
      }
      _pageBeforeGesture = null;
      _eraserChangedPage = false;
      return;
    }

    final live = _activeStrokeNotifier.value;
    if (live != null) {
      _activeStrokeNotifier.value = null;
      final appState = context.read<AppState>();

      // Check Scribble-to-Erase (rapid zig-zag over existing strokes)
      if (appState.scribbleToErase &&
          _activeTool.isPenFamily &&
          live.shapeType == ShapeType.none &&
          StrokeEngine.isScribbleGesture(live.points)) {
        final hitIds = StrokeEngine.findStrokesIntersectedByScribble(
          page.strokes,
          live.points,
        );
        if (hitIds.isNotEmpty) {
          final remaining =
              page.strokes.where((s) => !hitIds.contains(s.id)).toList();
          _commitPage(page.copyWith(strokes: remaining), undoSnapshot: page);
          return;
        }
      }

      Stroke finalized = live;
      if (_activeTool == EditorTool.shape &&
          finalized.shapeType == ShapeType.none) {
        final recognized = StrokeEngine.recognizeShape(finalized.points);
        if (recognized.recognized) {
          finalized = finalized.copyWith(
            points: recognized.snappedPoints,
            shapeType: recognized.shapeType,
            isSmoothed: true,
          );
        }
      } else if (finalized.shapeType == ShapeType.none && _autoNeatenEnabled) {
        final smoothed = StrokeEngine.smoothAndNeatenStroke(
          finalized.points,
          stabilization: _smoothingStrength,
          autoNeaten: _autoNeatenEnabled,
          toolType: finalized.toolType,
        );
        finalized = finalized.copyWith(points: smoothed, isSmoothed: true);
      }

      _commitPage(
        page.copyWith(strokes: [...page.strokes, finalized]),
        undoSnapshot: page,
      );
    }
  }

  void _cancelActiveGesture() {
    _shapeHoldTimer?.cancel();
    _activeStrokeNotifier.value = null;
    _eraserCursorNotifier.value = null;
    _tapeDraftNotifier.value = null;
    _tapeDragStart = null;
    if (_isDrawingPointerDown) {
      setState(() => _isDrawingPointerDown = false);
    }
  }

  void _scheduleShapeHoldTimer() {
    _shapeHoldTimer?.cancel();
    final appState = context.read<AppState>();
    if (!appState.holdToSnapShape && _activeTool != EditorTool.shape) return;
    if (_activeTool == EditorTool.highlighter) return;

    _shapeHoldTimer = Timer(const Duration(milliseconds: 460), () {
      final live = _activeStrokeNotifier.value;
      if (!mounted || live == null || live.points.length < 6) return;
      final res = StrokeEngine.recognizeShape(live.points);
      if (res.recognized) {
        _activeStrokeNotifier.value = live.copyWith(
          points: res.snappedPoints,
          shapeType: res.shapeType,
          isSmoothed: true,
        );
      }
    });
  }

  TapeElement? _findTapeAt(NotePage page, Offset pos) {
    for (int i = page.tapeElements.length - 1; i >= 0; i--) {
      final t = page.tapeElements[i];
      if (Rect.fromLTWH(t.x, t.y, t.width, t.height).contains(pos)) {
        return t;
      }
    }
    return null;
  }

  ImageElement? _findImageAt(NotePage page, Offset pos) {
    for (int i = page.imageElements.length - 1; i >= 0; i--) {
      final img = page.imageElements[i];
      if (Rect.fromLTWH(img.x, img.y, img.width, img.height)
          .inflate(8.0)
          .contains(pos)) {
        return img;
      }
    }
    return null;
  }

  void _applyEraserAt(NotePage page, Offset pos) {
    const double eraserRadius = 18.0;
    if (_eraserMode == EraserMode.stroke) {
      final remaining = page.strokes
          .where((s) => !StrokeEngine.hitTestStroke(s, pos, tolerance: eraserRadius))
          .toList();
      if (remaining.length != page.strokes.length) {
        _eraserChangedPage = true;
        context.read<AppState>().updatePage(
              _activeNotebookId,
              page.copyWith(strokes: remaining, updatedAt: DateTime.now()),
            );
      }
    } else {
      final newStrokes = <Stroke>[];
      bool changed = false;
      for (final s in page.strokes) {
        if (!StrokeEngine.hitTestStroke(s, pos, tolerance: eraserRadius)) {
          newStrokes.add(s);
          continue;
        }
        final split = StrokeEngine.precisionEraseStroke(
          s,
          pos,
          eraserRadius,
          idGenerator: _uuid.v4,
        );
        if (split.length != 1 || split.first.id != s.id) changed = true;
        newStrokes.addAll(split);
      }
      if (changed) {
        _eraserChangedPage = true;
        context.read<AppState>().updatePage(
              _activeNotebookId,
              page.copyWith(strokes: newStrokes, updatedAt: DateTime.now()),
            );
      }
    }
  }

  // ===========================================================================
  // TEXT, IMAGE, STENCIL & CHEMISTRY HUB INTEGRATION
  // ===========================================================================

  Future<void> _createTextElementAt(
    NotePage page,
    Offset pos, {
    String initialText = '',
  }) async {
    final newText = TextElement(
      id: _uuid.v4(),
      x: (pos.dx - 110).clamp(16.0, 560.0),
      y: (pos.dy - 24).clamp(16.0, 1020.0),
      width: 240.0,
      height: 68.0,
      text: initialText,
      fontSize: 18.0,
      // ignore: deprecated_member_use
      colorValue: _penColor.value,
    );
    await _commitPage(
      page.copyWith(textElements: [...page.textElements, newText]),
      undoSnapshot: page,
    );
    _startEditingText(newText);
  }

  void _startEditingText(TextElement element) {
    _commitActiveTextEdit();
    _activeTextController?.dispose();
    _activeTextFocusNode?.dispose();
    _activeTextController = TextEditingController(text: element.text);
    _activeTextFocusNode = FocusNode();
    setState(() {
      _selectedTextId = element.id;
      _editingTextId = element.id;
      _selectedImageId = null;
      _selectedStencilId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeTextFocusNode?.requestFocus();
    });
  }

  void _commitActiveTextEdit() {
    if (_editingTextId == null || _activeTextController == null) return;
    final notebook = _getNotebook(context, listen: false);
    final page = _getCurrentPage(notebook);
    if (page == null) return;

    final id = _editingTextId!;
    final newTextVal = _activeTextController!.text;
    _editingTextId = null;

    final updatedTexts = page.textElements
        .map((t) => t.id == id ? t.copyWith(text: newTextVal) : t)
        .toList();

    context.read<AppState>().updatePage(
          _activeNotebookId,
          page.copyWith(textElements: updatedTexts, updatedAt: DateTime.now()),
        );
  }

  void _insertSymbolFromChemistryHub(NotePage page, String symbol) {
    final ctrl = _activeTextController;
    if (_editingTextId != null && ctrl != null) {
      final sel = ctrl.selection;
      final text = ctrl.text;
      final start = sel.isValid ? sel.start : text.length;
      final end = sel.isValid ? sel.end : text.length;
      final next = text.replaceRange(start, end, symbol);
      ctrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + symbol.length),
      );
      return;
    }
    _insertTextFromChemistryHub(page, symbol);
  }

  Future<void> _insertTextFromChemistryHub(NotePage page, String text) async {
    final pageSize = PaperMetrics.pageSize(isLandscape: page.isLandscape);
    final element = TextElement(
      id: _uuid.v4(),
      x: (pageSize.width - 280) * 0.5,
      y: (pageSize.height - 80) * 0.42,
      width: 280.0,
      height: 84.0,
      text: text,
      fontSize: 17.0,
      // ignore: deprecated_member_use
      colorValue: _penColor.value,
    );
    await _commitPage(
      page.copyWith(textElements: [...page.textElements, element]),
      undoSnapshot: page,
    );
    setState(() {
      _selectedTextId = element.id;
      _activeTool = EditorTool.panZoom;
    });
  }

  Future<void> _insertStencilElement(NotePage page, String stencilId) async {
    final pageSize = PaperMetrics.pageSize(isLandscape: page.isLandscape);
    final stencil = StencilElement(
      id: _uuid.v4(),
      stencilId: stencilId,
      x: (pageSize.width - 140) * 0.5,
      y: (pageSize.height - 140) * 0.4,
      width: 140.0,
      height: 140.0,
      rotation: 0.0,
      // ignore: deprecated_member_use
      colorValue: _penColor.value,
      strokeWidth: 2.2,
    );
    await _commitPage(
      page.copyWith(stencilElements: [...page.stencilElements, stencil]),
      undoSnapshot: page,
    );
    setState(() {
      _selectedStencilId = stencil.id;
      _selectedTextId = null;
      _selectedImageId = null;
      _activeTool = EditorTool.panZoom;
    });
  }

  Future<void> _insertSavedImagePath(NotePage page, String savedPath) async {
    _ensureElementImageLoaded(savedPath);
    context.read<AppState>().addRecentImagePath(savedPath);
    final pageSize = PaperMetrics.pageSize(isLandscape: page.isLandscape);
    final imgEl = ImageElement(
      id: _uuid.v4(),
      x: (pageSize.width - 280) * 0.5,
      y: (pageSize.height - 220) * 0.32,
      width: 280.0,
      height: 220.0,
      rotation: 0.0,
      filePath: savedPath,
    );
    await _commitPage(
      page.copyWith(imageElements: [...page.imageElements, imgEl]),
      undoSnapshot: page,
    );
    if (mounted) {
      setState(() {
        _activeTool = EditorTool.image;
        _selectedImageId = imgEl.id;
        _selectedTextId = null;
        _selectedStencilId = null;
      });
    }
  }

  void _handleImageToolButtonTap(NotePage page) {
    _commitActiveTextEdit();
    if (_activeTool != EditorTool.image) {
      setState(() {
        _activeTool = EditorTool.image;
        _lassoController.clear();
      });
      if (page.imageElements.isEmpty) {
        _showImageInsertOptions(page);
      }
    } else {
      _showImageInsertOptions(page);
    }
  }

  Future<void> _showImageInsertOptions(NotePage page) async {
    final appState = context.read<AppState>();
    final recentPaths = <String>[
      ...appState.recentImagePaths,
      ...appState.customStickers.where(
        (p) => !appState.recentImagePaths.contains(p),
      ),
    ];

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 4, 18, 8),
                child: Text(
                  'Ảnh gần đây',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (recentPaths.isNotEmpty)
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: recentPaths.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (c, i) {
                      final path = recentPaths[i];
                      final file = File(path);
                      return GestureDetector(
                        onTap: () => Navigator.pop(ctx, 'recent:$path'),
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                            color: Colors.black26,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: file.existsSync()
                                ? Image.file(file, fit: BoxFit.cover)
                                : const Icon(Icons.image_outlined),
                          ),
                        ),
                      );
                    },
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Text(
                    'Chưa có ảnh gần đây. Chọn ảnh bên dưới để chèn lên trang.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                ),
              const Divider(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Chụp ảnh'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Chọn từ Bộ sưu tập'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action.startsWith('recent:')) {
      final path = action.substring('recent:'.length);
      await _insertSavedImagePath(page, path);
      return;
    }

    final source =
        action == 'camera' ? ImageSource.camera : ImageSource.gallery;
    try {
      // Never downscale on import: keep full original resolution for crisp cropping!
      final picked = await _imagePicker.pickImage(source: source);
      if (picked == null || !mounted) return;

      final savedPath = await appState.storage.saveImportedFile(
        File(picked.path),
        subfolder: 'images',
      );
      await _insertSavedImagePath(page, savedPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể chèn ảnh: $e')),
        );
      }
    }
  }

  Future<void> _handleInsertAction(
    InsertMenuAction action,
    Notebook notebook,
    NotePage currentPage,
    int currentIdx,
  ) async {
    switch (action) {
      case InsertMenuAction.newPage:
        await context.read<AppState>().addPage(
              notebook.id,
              templateType: currentPage.templateType,
              paperColor: currentPage.paperColor,
              isLandscape: currentPage.isLandscape,
              insertAfterIndex: currentIdx,
            );
        if (mounted) {
          _jumpToPage(currentIdx + 1);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(milliseconds: 1100),
              content: Text('Đã thêm trang mới ngay sau trang hiện tại'),
            ),
          );
        }
        break;
      case InsertMenuAction.attachment:
        await _pickAndInsertAttachment(currentPage);
        break;
      case InsertMenuAction.image:
        await _showImageInsertOptions(currentPage);
        break;
      case InsertMenuAction.pdf:
        await _handleImportPdf(notebook);
        break;
      case InsertMenuAction.docPpt:
        await _pickAndInsertAttachment(
          currentPage,
          allowedExtensions: const ['doc', 'docx', 'ppt', 'pptx'],
          emptyLabel: 'DOC/PPT',
        );
        break;
    }
  }

  Future<void> _pickAndInsertAttachment(
    NotePage page, {
    List<String>? allowedExtensions,
    String emptyLabel = 'tệp đính kèm',
  }) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: allowedExtensions != null ? FileType.custom : FileType.any,
        allowedExtensions: allowedExtensions,
      );
      if (res == null || res.files.isEmpty || !mounted) return;
      final picked = res.files.first;
      String savedPath = picked.path ?? '';
      if (savedPath.isNotEmpty && File(savedPath).existsSync()) {
        savedPath = await context.read<AppState>().storage.saveImportedFile(
              File(savedPath),
              subfolder: 'attachments',
            );
      }
      final ext = (picked.extension ??
              (picked.name.contains('.') ? picked.name.split('.').last : 'FILE'))
          .toUpperCase();
      final pageSize = PaperMetrics.pageSize(isLandscape: page.isLandscape);
      final attachment = AttachmentElement(
        id: _uuid.v4(),
        x: (pageSize.width - 260) * 0.5,
        y: (pageSize.height - 64) * 0.35,
        width: 260.0,
        height: 64.0,
        fileName: picked.name,
        filePath: savedPath,
        fileExtension: ext,
        fileSizeBytes: picked.size,
      );
      await _commitPage(
        page.copyWith(
          attachmentElements: [...page.attachmentElements, attachment],
        ),
        undoSnapshot: page,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã đính kèm $emptyLabel: ${picked.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể đính kèm tệp: $e')),
        );
      }
    }
  }

  Future<void> _openImageCrop(
    NotePage page,
    ImageElement img,
    ImageCropMode mode,
  ) async {
    final uiImg = _elementImageCache[img.filePath];
    if (uiImg == null) {
      _ensureElementImageLoaded(img.filePath);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đang tải ảnh gốc độ phân giải cao...')),
      );
      return;
    }
    final result = await ImageCropDialog.show(
      context,
      image: uiImg,
      initialMode: mode,
      initialCropLeft: img.cropLeft,
      initialCropTop: img.cropTop,
      initialCropRight: img.cropRight,
      initialCropBottom: img.cropBottom,
      initialFreehandPath: img.freehandClipPath,
    );
    if (result == null || !mounted) return;

    // Preserve natural aspect ratio of the cropped region
    final croppedPixelW =
        math.max(1.0, (result.cropRight - result.cropLeft) * uiImg.width);
    final croppedPixelH =
        math.max(1.0, (result.cropBottom - result.cropTop) * uiImg.height);
    final newAspect = croppedPixelW / croppedPixelH;
    final newHeight = (img.width / newAspect).clamp(32.0, 520.0);

    final updated = page.imageElements.map((e) {
      if (e.id != img.id) return e;
      return e.copyWith(
        height: newHeight,
        cropLeft: result.cropLeft,
        cropTop: result.cropTop,
        cropRight: result.cropRight,
        cropBottom: result.cropBottom,
        freehandClipPath: result.freehandClipPath,
      );
    }).toList();
    await _commitPage(
      page.copyWith(imageElements: updated),
      undoSnapshot: page,
    );
  }

  void _openChemistryHub(NotePage page) {
    _commitActiveTextEdit();
    ChemistryHubSheet.show(
      context,
      onInsertStencil: (stencilId) => _insertStencilElement(page, stencilId),
      onInsertText: (text) => _insertTextFromChemistryHub(page, text),
      onInsertSymbol: (sym) => _insertSymbolFromChemistryHub(page, sym),
    );
  }

  void _openQuickStencilPicker(NotePage page) {
    _commitActiveTextEdit();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return FractionallySizedBox(
          heightFactor: 0.72,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.biotech_outlined),
                    SizedBox(width: 8),
                    Text(
                      'Khuôn Hóa học & Dụng cụ thí nghiệm',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StencilPickerSheet(
                  previewColor: _penColor,
                  onSelectStencil: (stencilId) {
                    Navigator.of(sheetCtx).pop();
                    _insertStencilElement(page, stencilId);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleImportPdf(Notebook notebook) async {
    setState(() => _isBusyPdf = true);
    try {
      final result = await _pdfImportService.pickAndImportPdf(
        startIndex: notebook.pages.length,
      );
      if (result == null || !mounted) return;

      final firstNewIndex = notebook.pages.length;
      await context.read<AppState>().updateNotebook(
            notebook.copyWith(
              pages: [...notebook.pages, ...result.pages],
              updatedAt: DateTime.now(),
            ),
          );
      if (mounted) {
        _jumpToPage(firstNewIndex);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã nhập ${result.pages.length} trang từ "${result.sourceFileName}"',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi nhập PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusyPdf = false);
    }
  }

  Future<void> _handleExportPdf(Notebook notebook) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Xuất sổ tay ra PDF',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Nền giấy, nét viết tay, công thức & khuôn Hóa'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Xuất & Chia sẻ tệp PDF'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Xem trước & In PDF'),
              onTap: () => Navigator.pop(ctx, 'print'),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: const Text('Lưu PDF vào bộ nhớ máy'),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    setState(() => _isBusyPdf = true);
    try {
      if (action == 'share') {
        await _pdfExportService.shareNotebookPdf(notebook);
      } else if (action == 'print') {
        await _pdfExportService.printNotebookPdf(notebook);
      } else if (action == 'save') {
        final file = await _pdfExportService.exportNotebookToFile(notebook);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã lưu PDF tại: ${file.path}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusyPdf = false);
    }
  }

  Future<void> _handlePullAddPage(Notebook notebook, NotePage lastPage) async {
    if (_isAddingPullPage) return;
    _isAddingPullPage = true;
    try {
      await context.read<AppState>().addPage(
            notebook.id,
            templateType: lastPage.templateType,
            paperColor: lastPage.paperColor,
            isLandscape: lastPage.isLandscape,
          );
      if (mounted) {
        setState(() {
          _pullOverscroll = 0.0;
          _currentPageIndex = notebook.pages.length;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(milliseconds: 1200),
            content: Text('Đã thêm trang mới'),
          ),
        );
      }
    } finally {
      _isAddingPullPage = false;
    }
  }

  // ===========================================================================
  // AUDIO NOTE RECORDING, SYNCED STROKE REPLAY & IN-APP APK UPDATER
  // ===========================================================================

  Future<void> _toggleAudioRecording(NotePage page) async {
    if (_isRecordingAudio) {
      final durationMs = await HardwareService.instance.stopAudioRecording();
      final recId = _activeRecordingId;
      final recPath = _activeRecordingPath;
      final fallbackDuration =
          DateTime.now().millisecondsSinceEpoch - _recordingStartMs;
      setState(() {
        _isRecordingAudio = false;
        _activeRecordingId = null;
        _activeRecordingPath = null;
      });
      if (recId != null && recPath != null) {
        final rec = AudioRecording(
          id: recId,
          filePath: recPath,
          durationMs: durationMs > 0 ? durationMs : math.max(1000, fallbackDuration),
          createdAt: DateTime.now(),
        );
        await _commitPage(
          page.copyWith(audioRecordings: [...page.audioRecordings, rec]),
          undoSnapshot: page,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(milliseconds: 1400),
              content: Text('Đã lưu bản ghi âm bài giảng đồng bộ nét viết'),
            ),
          );
        }
      }
      return;
    }

    // Start new recording
    final appState = context.read<AppState>();
    final rootDir = await appState.storage.getRootDirectory();
    final audioDir = Directory('${rootDir.path}${Platform.pathSeparator}audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    final recId = _uuid.v4();
    final path = '${audioDir.path}${Platform.pathSeparator}$recId.m4a';
    final started = await HardwareService.instance.startAudioRecording(path);
    if (!mounted) return;
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cần cấp quyền Micro để ghi âm bài giảng (hỗ trợ trên Android / MatePad).',
          ),
        ),
      );
      return;
    }
    setState(() {
      _isRecordingAudio = true;
      _activeRecordingId = recId;
      _activeRecordingPath = path;
      _recordingStartMs = DateTime.now().millisecondsSinceEpoch;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 1400),
        content: Text('Đang ghi âm... Mọi nét viết sẽ tự động đồng bộ mốc thời gian'),
      ),
    );
  }

  Future<void> _togglePlayAudio(AudioRecording rec) async {
    if (_isAudioPlaying && _playingAudioId == rec.id) {
      await HardwareService.instance.pauseAudio();
      _audioPollTimer?.cancel();
      if (mounted) {
        setState(() => _isAudioPlaying = false);
      }
      return;
    }

    final ok = await HardwareService.instance.playAudio(rec.filePath);
    if (!mounted) return;
    if (ok) {
      await HardwareService.instance.setAudioSpeed(_audioSpeed);
      if (_playingAudioId == rec.id && _audioPositionMs > 0) {
        await HardwareService.instance.seekAudio(_audioPositionMs);
      }
    }
    setState(() {
      _playingAudioId = rec.id;
      _isAudioPlaying = true;
    });
    _audioPollTimer?.cancel();
    _audioPollTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (!mounted || !_isAudioPlaying) return;
      final pos = await HardwareService.instance.getAudioPositionMs();
      if (!mounted) return;
      if (pos >= rec.durationMs && rec.durationMs > 0) {
        _audioPollTimer?.cancel();
        setState(() {
          _isAudioPlaying = false;
          _audioPositionMs = rec.durationMs;
          _repaintVersion++;
        });
      } else {
        setState(() {
          _audioPositionMs = pos;
          _repaintVersion++;
        });
      }
    });
  }

  Future<void> _seekAudio(AudioRecording rec, int ms) async {
    setState(() {
      _playingAudioId = rec.id;
      _audioPositionMs = ms;
      _repaintVersion++;
    });
    await HardwareService.instance.seekAudio(ms);
  }

  Future<void> _cycleAudioSpeed() async {
    final next = _audioSpeed == 1.0
        ? 1.5
        : (_audioSpeed == 1.5 ? 2.0 : 1.0);
    setState(() => _audioSpeed = next);
    await HardwareService.instance.setAudioSpeed(next);
  }

  Future<void> _deleteAudioRecording(NotePage page, AudioRecording rec) async {
    if (_playingAudioId == rec.id) {
      _audioPollTimer?.cancel();
      await HardwareService.instance.stopAudio();
      _playingAudioId = null;
      _isAudioPlaying = false;
      _audioPositionMs = 0;
    }
    final updated =
        page.audioRecordings.where((r) => r.id != rec.id).toList();
    await _commitPage(
      page.copyWith(audioRecordings: updated),
      undoSnapshot: page,
    );
  }

  Future<void> _handleCheckForUpdate() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 1200),
        content: Text('Đang kiểm tra bản cập nhật APK mới nhất...'),
      ),
    );
    final info = await AppUpdaterService.checkForUpdate();
    if (!mounted) return;

    if (info.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(info.errorMessage!)),
      );
      return;
    }

    if (!info.hasUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ChemNote v${info.currentVersion} là phiên bản mới nhất!',
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Có bản cập nhật ChemNote v${info.latestVersion}'),
        content: SingleChildScrollView(
          child: Text(
            info.releaseNotes.trim().isNotEmpty
                ? info.releaseNotes.trim()
                : 'Phiên bản mới đã sẵn sàng trên GitHub Releases. Nhấn tải để cài đặt APK mới nhất cho MatePad 11.5"S.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Để sau'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              AppUpdaterService.openDownloadUrl(info.downloadUrl);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Tải APK mới'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MODALS: TAB PICKER & PAGE GRID / OUTLINE
  // ===========================================================================

  void _openTabPickerModal(AppState appState) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const ListTile(
              title: Text(
                'Mở nhanh sổ tay trong tab mới',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final nb in appState.activeNotebooks)
              ListTile(
                leading: Container(
                  width: 24,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(nb.coverColorValue),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                title: Text(nb.title),
                subtitle: Text('${nb.pages.length} trang'),
                trailing: nb.id == _activeNotebookId
                    ? const Icon(Icons.check_rounded,
                        color: EditorColors.activeBlue)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  appState.openTab(nb.id);
                  _switchNotebookTab(nb.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openPageGridModal(Notebook notebook) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.grid_view_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Danh sách trang (${notebook.pages.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final last = notebook.pages.last;
                      await context.read<AppState>().addPage(
                            notebook.id,
                            templateType: last.templateType,
                            paperColor: last.paperColor,
                            isLandscape: last.isLandscape,
                          );
                      if (mounted) _jumpToPage(notebook.pages.length);
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Thêm trang'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 170,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.72,
                ),
                itemCount: notebook.pages.length,
                itemBuilder: (c, i) {
                  final p = notebook.pages[i];
                  final isCur = i == _currentPageIndex;
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _jumpToPage(i);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCur
                              ? EditorColors.activeBlue
                              : Colors.white24,
                          width: isCur ? 2.4 : 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8),
                                    ),
                                    child: CustomPaint(
                                      painter: PaperTemplatePainter(
                                        templateType: p.templateType,
                                        paperColor: p.paperColor,
                                        isLandscape: p.isLandscape,
                                      ),
                                    ),
                                  ),
                                ),
                                if (p.isBookmarked)
                                  const Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Icon(
                                      Icons.bookmark_rounded,
                                      size: 18,
                                      color: Color(0xFFD97706),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Trang ${i + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isCur
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                if (notebook.pages.length > 1)
                                  GestureDetector(
                                    onTap: () async {
                                      await context
                                          .read<AppState>()
                                          .deletePage(notebook.id, p.id);
                                      if (ctx.mounted) Navigator.pop(ctx);
                                    },
                                    child: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD UI
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final notebook = appState.getNotebookById(_activeNotebookId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backdrop = isDark ? EditorColors.obsidianBg : const Color(0xFFE5E7EB);

    if (notebook == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sổ tay')),
        body: const Center(child: Text('Không tìm thấy sổ tay này.')),
      );
    }

    final currentPage = _getCurrentPage(notebook);
    if (currentPage == null) {
      return Scaffold(
        appBar: AppBar(title: Text(notebook.title)),
        body: Center(
          child: FilledButton.icon(
            onPressed: () => appState.addPage(notebook.id),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Thêm trang đầu tiên'),
          ),
        ),
      );
    }

    final openTabs = appState.openNotebooks.isNotEmpty
        ? appState.openNotebooks
        : [notebook];
    final currentIdx = _currentPageIndex.clamp(0, notebook.pages.length - 1);
    final bool allowZoomPan = _pointerDownPositions.length >= 2 ||
        appState.readOnlyMode ||
        (!_isDrawingPointerDown && _activeTool == EditorTool.panZoom);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: backdrop,
      endDrawer: EditorSettingsDrawer(
        notebook: notebook,
        activePageIndex: currentIdx,
        isCurrentPageBookmarked: currentPage.isBookmarked,
        refreshRateHz: _refreshRateHz,
        appState: appState,
        onToggleBookmark: () =>
            appState.toggleBookmark(notebook.id, currentPage.id),
        onOpenTemplateSwitcher: () => showPageTemplateSheet(
          context: context,
          currentTemplate: currentPage.templateType,
          currentColor: currentPage.paperColor,
          onApply: (tpl, col) => _commitPage(
            currentPage.copyWith(templateType: tpl, paperColor: col),
            undoSnapshot: currentPage,
          ),
        ),
        onToggleOrientation: () => _commitPage(
          currentPage.copyWith(isLandscape: !currentPage.isLandscape),
          undoSnapshot: currentPage,
        ),
        onClearPage: () => _commitPage(
          currentPage.copyWith(
            strokes: const [],
            textElements: const [],
            stencilElements: const [],
            imageElements: const [],
            tapeElements: const [],
          ),
          undoSnapshot: currentPage,
        ),
        onDeletePage: () async {
          await appState.deletePage(notebook.id, currentPage.id);
          if (mounted) {
            setState(() => _currentPageIndex = math.max(0, currentIdx - 1));
          }
        },
        onImportPdf: () => _handleImportPdf(notebook),
        onExportPdf: () => _handleExportPdf(notebook),
        onToggleLockNotebook: () async {
          await appState.setNotebookLock(
            notebook.id,
            locked: !notebook.isLocked,
            pinCode: notebook.isLocked ? null : '1234',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  !notebook.isLocked
                      ? 'Đã khóa sổ tay (PIN mặc định: 1234)'
                      : 'Đã mở khóa sổ tay',
                ),
              ),
            );
          }
        },
        onCheckForUpdate: _handleCheckForUpdate,
      ),
      body: Column(
        children: [
          // Row 1: Multi-Notebook Tab Bar + Top-Right 5-Item Insert `+` Menu
          EditorTabBar(
            openNotebooks: openTabs,
            activeNotebookId: notebook.id,
            onBack: () {
              _commitActiveTextEdit();
              Navigator.of(context).maybePop();
            },
            onSelectTab: _switchNotebookTab,
            onCloseTab: _closeNotebookTab,
            onOpenTabPicker: () => _openTabPickerModal(appState),
            onInsertAction: (action) =>
                _handleInsertAction(action, notebook, currentPage, currentIdx),
            onOpenSearch: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              );
            },
            onOpenPageGrid: () => _openPageGridModal(notebook),
            onOpenChemistryHub: () => _openChemistryHub(currentPage),
            onOpenSettingsDrawer: () =>
                _scaffoldKey.currentState?.openEndDrawer(),
          ),

          // Row 2: Sleek Monochrome Vector Tool Bar (No 3 quick-width squiggles)
          EditorToolBar(
            activeTool: _activeTool,
            lastPenTool: _lastPenTool,
            activeColor: _effectiveColor,
            canUndo: _undoFor(currentPage.id).isNotEmpty,
            canRedo: _redoFor(currentPage.id).isNotEmpty,
            zoomWindowEnabled: _zoomWindowEnabled,
            rulerVisible: _rulerVisible,
            palmRejectionEnabled: appState.palmRejectionEnabled,
            isRecordingAudio: _isRecordingAudio,
            onUndo: () => _undo(currentPage),
            onRedo: () => _redo(currentPage),
            onSelectTool: (tool) {
              _commitActiveTextEdit();
              setState(() {
                _activeTool = tool;
                if (tool.isPenFamily) _lastPenTool = tool;
                if (tool != EditorTool.lasso) _lassoController.clear();
                if (tool != EditorTool.image) _selectedImageId = null;
              });
            },
            onOpenPenPopover: () => showPenSettingsSheet(
              context: context,
              appState: appState,
              currentTool: _activeTool == EditorTool.highlighter
                  ? EditorTool.highlighter
                  : _lastPenTool,
              currentColor: _effectiveColor,
              strokeWidth: _effectiveWidth,
              opacity: _effectiveOpacity,
              pressureSensitivity: _pressureSensitivity,
              autoNeaten: _autoNeatenEnabled,
              smoothingStrength: _smoothingStrength,
              onSelectPen: (p) => setState(() {
                _lastPenTool = p;
                _activeTool = p;
              }),
              onSelectColor: (c) => setState(() {
                if (_activeTool == EditorTool.highlighter) {
                  _highlighterColor = c;
                } else {
                  _penColor = c;
                }
              }),
              onPickEyedropper: () {
                setState(() => _eyedropperActive = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    duration: Duration(milliseconds: 1600),
                    content: Text('Chạm vào trang để hút màu'),
                  ),
                );
              },
              onOpenColorWheel: () => showColorPaletteSheet(
                context: context,
                isHighlighter: _activeTool == EditorTool.highlighter,
                currentColor: _effectiveColor,
                onSelectColor: (c) => setState(() {
                  if (_activeTool == EditorTool.highlighter) {
                    _highlighterColor = c;
                  } else {
                    _penColor = c;
                  }
                }),
              ),
              onUpdate: ({
                width,
                opacity,
                pressureSensitivity,
                autoNeaten,
                smoothingStrength,
                scribbleToErase,
                holdToSnapShape,
              }) {
                setState(() {
                  if (width != null) {
                    if (_activeTool == EditorTool.highlighter) {
                      _highlighterWidth = width;
                    } else {
                      _penWidth = width;
                    }
                  }
                  if (opacity != null) {
                    if (_activeTool == EditorTool.highlighter) {
                      _highlighterOpacity = opacity;
                    } else {
                      _penOpacity = opacity;
                    }
                  }
                  if (pressureSensitivity != null) {
                    _pressureSensitivity = pressureSensitivity;
                  }
                  if (autoNeaten != null) _autoNeatenEnabled = autoNeaten;
                  if (smoothingStrength != null) {
                    _smoothingStrength = smoothingStrength;
                  }
                });
                if (scribbleToErase != null) {
                  appState.setScribbleToErase(scribbleToErase);
                }
                if (holdToSnapShape != null) {
                  appState.setHoldToSnapShape(holdToSnapShape);
                }
              },
            ),
            onOpenEraserPopover: () => showEraserSettingsSheet(
              context: context,
              currentMode: _eraserMode,
              onSelectMode: (m) => setState(() => _eraserMode = m),
              onClearCurrentPage: () => _commitPage(
                currentPage.copyWith(strokes: const []),
                undoSnapshot: currentPage,
              ),
            ),
            onInsertImage: () => _handleImageToolButtonTap(currentPage),
            onOpenStickerPicker: () => _openQuickStencilPicker(currentPage),
            onToggleZoomWindow: () =>
                setState(() => _zoomWindowEnabled = !_zoomWindowEnabled),
            onToggleRuler: () =>
                setState(() => _rulerVisible = !_rulerVisible),
            onTogglePalmRejection: () {
              appState.togglePalmRejection();
              _palmFilter.stylusOnlyMode = appState.palmRejectionEnabled;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(milliseconds: 1400),
                  content: Text(
                    appState.palmRejectionEnabled
                        ? 'Khoá lòng bàn tay: BẬT (Bút M-Pencil 3 viết · 1 ngón tay cuộn trang)'
                        : 'Khoá lòng bàn tay: TẮT (Cả bút và ngón tay đều viết)',
                  ),
                ),
              );
            },
            onToggleAudioRecording: () => _toggleAudioRecording(currentPage),
            onSelectColor: (c) => setState(() {
              if (_activeTool == EditorTool.highlighter) {
                _highlighterColor = c;
              } else {
                _penColor = c;
              }
            }),
            onOpenColorPalette: () => showColorPaletteSheet(
              context: context,
              isHighlighter: _activeTool == EditorTool.highlighter,
              currentColor: _effectiveColor,
              onSelectColor: (c) => setState(() {
                if (_activeTool == EditorTool.highlighter) {
                  _highlighterColor = c;
                } else {
                  _penColor = c;
                }
              }),
            ),
          ),

          // Compact Audio Note Replay Bar (shown when current page has an AudioRecording)
          if (currentPage.audioRecordings.isNotEmpty)
            AudioReplayBar(
              recording: currentPage.audioRecordings.last,
              isPlaying: _isAudioPlaying &&
                  _playingAudioId == currentPage.audioRecordings.last.id,
              positionMs:
                  _playingAudioId == currentPage.audioRecordings.last.id
                      ? _audioPositionMs
                      : 0,
              speed: _audioSpeed,
              onTogglePlay: () =>
                  _togglePlayAudio(currentPage.audioRecordings.last),
              onSeek: (ms) =>
                  _seekAudio(currentPage.audioRecordings.last, ms),
              onCycleSpeed: _cycleAudioSpeed,
              onDelete: () => _deleteAudioRecording(
                currentPage,
                currentPage.audioRecordings.last,
              ),
            ),

          // Main Canvas Area (Continuous Vertical Scroll or Horizontal Flip)
          Expanded(
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 0.45,
                  maxScale: 4.5,
                  boundaryMargin: EdgeInsets.all(
                    appState.freePaperMovement ? 260 : 24,
                  ),
                  panEnabled: allowZoomPan,
                  scaleEnabled: allowZoomPan,
                  child: appState.verticalContinuousScroll
                      ? _buildVerticalContinuousPages(notebook)
                      : _buildHorizontalFlipPages(notebook),
                ),

                // Star-Only Floating Left Quick-Pen Favorites Dock
                if (appState.showFavoritesBar &&
                    appState.favoritePens.isNotEmpty)
                  Positioned(
                    left: 10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: QuickPenFavoritesDock(
                        favoritePens: appState.favoritePens,
                        activeTool: _activeTool,
                        activeColor: _effectiveColor,
                        activeWidth: _effectiveWidth,
                        onSelectPreset: (preset) {
                          setState(() {
                            final tool =
                                EditorToolX.fromStrokeToolType(preset.toolType);
                            _activeTool = tool;
                            if (tool.isPenFamily) _lastPenTool = tool;
                            if (tool == EditorTool.highlighter) {
                              _highlighterColor = Color(preset.colorValue);
                              _highlighterWidth = preset.width;
                              _highlighterOpacity = preset.opacity;
                            } else {
                              _penColor = Color(preset.colorValue);
                              _penWidth = preset.width;
                              _penOpacity = preset.opacity;
                              _pressureSensitivity = preset.pressureSensitivity;
                            }
                            _selectedImageId = null;
                          });
                        },
                        onRemovePreset: (preset) {
                          appState.toggleStarPen(preset);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              duration: Duration(milliseconds: 1000),
                              content: Text('Đã bỏ ghim bút khỏi thanh ưa thích'),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // Subtle Floating Page Counter Badge (top-right)
                Positioned(
                  top: 10,
                  right: 14,
                  child: GestureDetector(
                    onTap: () => _openPageGridModal(notebook),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: EditorColors.obsidianSurface.withAlpha(210),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        '${currentIdx + 1} / ${notebook.pages.length}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),

                // Pro Lasso Floating Context Menu
                if (_lassoController.hasSelection)
                  Positioned(
                    top: 12,
                    left: 58,
                    right: 58,
                    child: Center(
                      child: LassoFloatingMenu(
                        selectedCount: _lassoController.selection.totalCount,
                        hasClipboard: _lassoController.hasClipboard,
                        onCut: () {
                          final updated =
                              _lassoController.cutSelection(currentPage);
                          _commitPage(updated, undoSnapshot: currentPage);
                        },
                        onCopy: () {
                          _lassoController.copySelection(currentPage);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              duration: Duration(milliseconds: 900),
                              content: Text('Đã sao chép vùng chọn'),
                            ),
                          );
                        },
                        onPaste: () {
                          final updated = _lassoController.pasteClipboard(
                            currentPage,
                            idGenerator: _uuid.v4,
                          );
                          _commitPage(updated, undoSnapshot: currentPage);
                        },
                        onDuplicate: () {
                          final updated = _lassoController.duplicateSelection(
                            currentPage,
                            idGenerator: _uuid.v4,
                          );
                          _commitPage(updated, undoSnapshot: currentPage);
                        },
                        onRotate: () {
                          final updated = _lassoController.rotateSelection(
                            currentPage,
                            math.pi / 12,
                          );
                          _commitPage(updated, undoSnapshot: currentPage);
                        },
                        onScaleUp: () {
                          final updated =
                              _lassoController.scaleSelection(currentPage, 1.15);
                          _commitPage(updated, undoSnapshot: currentPage);
                        },
                        onScaleDown: () {
                          final updated =
                              _lassoController.scaleSelection(currentPage, 0.85);
                          _commitPage(updated, undoSnapshot: currentPage);
                        },
                        onRecolor: (color) {
                          final updated = _lassoController.recolorSelection(
                            currentPage,
                            // ignore: deprecated_member_use
                            color.value,
                          );
                          _commitPage(updated, undoSnapshot: currentPage);
                        },
                        onDelete: () {
                          final updated =
                              _lassoController.deleteSelection(currentPage);
                          _commitPage(updated, undoSnapshot: currentPage);
                        },
                        onClear: _lassoController.clear,
                      ),
                    ),
                  ),

                // Busy PDF overlay
                if (_isBusyPdf)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black45,
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                CircularProgressIndicator(),
                                SizedBox(width: 16),
                                Text('Đang xử lý tệp PDF...'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Docked Zoom Window Panel (when Zoom Window tool is toggled ON)
          if (_zoomWindowEnabled)
            ZoomWindowDock(
              focusRect: _zoomFocusRect,
              pageSize:
                  PaperMetrics.pageSize(isLandscape: currentPage.isLandscape),
              magnifiedPageBuilder: (focusRect) =>
                  _buildZoomedWritingStrip(currentPage, currentIdx, focusRect),
              onStepLeft: () => setState(() {
                _zoomFocusRect = _zoomFocusRect.shift(const Offset(-120, 0));
              }),
              onStepRight: () => setState(() {
                _zoomFocusRect = _zoomFocusRect.shift(const Offset(120, 0));
              }),
              onNewLine: () => setState(() {
                _zoomFocusRect = Rect.fromLTWH(
                  60,
                  _zoomFocusRect.top + 85,
                  _zoomFocusRect.width,
                  _zoomFocusRect.height,
                );
              }),
              onClose: () => setState(() => _zoomWindowEnabled = false),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CONTINUOUS VERTICAL PAGES + PULL-TO-ADD-PAGE & HORIZONTAL FLIP
  // ===========================================================================

  Widget _buildVerticalContinuousPages(Notebook notebook) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is OverscrollNotification &&
            notification.overscroll > 0) {
          setState(() {
            _pullOverscroll =
                (_pullOverscroll + notification.overscroll).clamp(0.0, 140.0);
          });
          if (_pullOverscroll >= 85.0 && !_isAddingPullPage) {
            _handlePullAddPage(notebook, notebook.pages.last);
          }
        } else if (notification is ScrollEndNotification &&
            _pullOverscroll > 0) {
          setState(() => _pullOverscroll = 0.0);
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _verticalScrollController,
        physics: !_isDrawingPointerDown &&
                (context.read<AppState>().palmRejectionEnabled ||
                    context.read<AppState>().readOnlyMode ||
                    _activeTool == EditorTool.panZoom)
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        child: Column(
          children: [
            for (int i = 0; i < notebook.pages.length; i++) ...[
              _buildSinglePageCanvas(notebook, notebook.pages[i], i),
              if (i < notebook.pages.length - 1) const SizedBox(height: 14),
            ],
            const SizedBox(height: 18),
            // Pull-to-add-page indicator / direct tap fallback
            GestureDetector(
              onTap: () => _handlePullAddPage(notebook, notebook.pages.last),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: _pullOverscroll > 30
                      ? EditorColors.activeBlue.withAlpha(48)
                      : EditorColors.obsidianSurface.withAlpha(180),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _pullOverscroll > 30
                        ? EditorColors.activeBlue
                        : Colors.white12,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _pullOverscroll > 60
                          ? Icons.add_circle_outline_rounded
                          : Icons.arrow_downward_rounded,
                      size: 16,
                      color: EditorColors.activeBlue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _pullOverscroll > 60
                          ? 'Thả để thêm trang mới'
                          : 'Kéo mạnh xuống (hoặc chạm) để thêm trang mới',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalFlipPages(Notebook notebook) {
    return PageView.builder(
      controller: _horizontalPageController,
      physics: !_isDrawingPointerDown &&
              (context.read<AppState>().palmRejectionEnabled ||
                  context.read<AppState>().readOnlyMode ||
                  _activeTool == EditorTool.panZoom)
          ? const PageScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: notebook.pages.length,
      onPageChanged: (i) => setState(() => _currentPageIndex = i),
      itemBuilder: (ctx, i) {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildSinglePageCanvas(notebook, notebook.pages[i], i),
          ),
        );
      },
    );
  }

  /// Builds a single A4 page with the Two-Layer 144Hz RepaintBoundary split,
  /// interactive overlays, Laser Pointer, Ruler, Bookmark ribbon, and Zoom Box.
  Widget _buildSinglePageCanvas(
    Notebook notebook,
    NotePage page,
    int pageIndex,
  ) {
    _ensurePdfImageLoaded(page.pdfBackgroundPath);
    for (final img in page.imageElements) {
      _ensureElementImageLoaded(img.filePath);
    }
    final pageSize = PaperMetrics.pageSize(isLandscape: page.isLandscape);
    final bool isActivePage = pageIndex == _currentPageIndex;
    final bool isLassoOwner = _lassoController.activePageId == page.id;

    return Container(
      width: pageSize.width,
      height: pageSize.height,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(65),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRect(
        child: Stack(
          children: [
            // Layer 1 (Cached RepaintBoundary): Paper + PDF + High-Res Images + Committed Ink + Stencils + Tapes
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: pageSize,
                  painter: CanvasPainter(
                    page: page,
                    pdfBackgroundImage: page.pdfBackgroundPath != null
                        ? _pdfImageCache[page.pdfBackgroundPath!]
                        : null,
                    elementImageCache: _elementImageCache,
                    lassoSelection: isLassoOwner
                        ? _lassoController.selection
                        : const LassoSelection(),
                    lassoSelectionBounds:
                        isLassoOwner ? _lassoController.selectionBounds : null,
                    playingAudioId: _playingAudioId,
                    playingAudioTimeMs:
                        _playingAudioId != null ? _audioPositionMs : null,
                    repaintVersion: _repaintVersion,
                  ),
                ),
              ),
            ),

            // Layer 2 (144Hz Live Ink & Hover Overlay — Zero Widget Rebuilds)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerHover: (e) => _handlePointerHover(e, page),
                onPointerDown: (e) => _handlePointerDown(e, page, pageIndex),
                onPointerMove: (e) => _handlePointerMove(e, page),
                onPointerUp: (e) => _handlePointerUp(e, page),
                onPointerCancel: (e) => _handlePointerUp(e, page),
                child: (_activeDrawingPageId == page.id || isActivePage)
                    ? CustomPaint(
                        size: pageSize,
                        painter: ActiveStrokePainter(
                          activeStroke: _activeStrokeNotifier,
                          hoverPosition: _hoverPosNotifier,
                          eraserCursor: _eraserCursorNotifier,
                          lassoPath: _lassoPathNotifier,
                          tapeDraftRect: _tapeDraftNotifier,
                          isDarkPaper: page.paperColor == PaperColorType.dark,
                          hoverRadius: _effectiveWidth * 0.65,
                          hoverColor: _effectiveColor,
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),

            // Laser Pointer Fading Trail Overlay
            if (isActivePage)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: LaserPointerPainter(controller: _laserController),
                  ),
                ),
              ),

            // Interactive Image Overlays (8 handles + 6-button Crop/Edit Pill)
            for (final img in page.imageElements) _buildImageOverlay(page, img),

            // Interactive Attachment Cards (DOC/PPT/PDF/Files)
            for (final att in page.attachmentElements)
              _buildAttachmentOverlay(page, att),

            // Interactive Stencil Overlays
            for (final st in page.stencilElements)
              _buildStencilOverlay(page, st),

            // Interactive Text Overlays
            for (final txt in page.textElements) _buildTextOverlay(page, txt),

            // Movable Zoom Window Focus Indicator on Active Page
            if (_zoomWindowEnabled && isActivePage)
              Positioned(
                left: _zoomFocusRect.left,
                top: _zoomFocusRect.top,
                child: GestureDetector(
                  onPanUpdate: (d) {
                    setState(() {
                      _zoomFocusRect = _zoomFocusRect.shift(d.delta);
                    });
                  },
                  child: Container(
                    width: _zoomFocusRect.width,
                    height: _zoomFocusRect.height,
                    decoration: BoxDecoration(
                      color: EditorColors.activeBlue.withAlpha(22),
                      border: Border.all(
                        color: EditorColors.activeBlue,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),

            // Interactive Translucent Ruler Overlay
            if (_rulerVisible && isActivePage)
              InteractiveRulerOverlay(
                ruler: _rulerState,
                onChanged: () => setState(() {}),
                onClose: () => setState(() => _rulerVisible = false),
              ),

            // Subtle Top-Left Bookmark Ribbon on Bookmarked Pages
            if (page.isBookmarked)
              const Positioned(
                top: 0,
                left: 18,
                child: Icon(
                  Icons.bookmark_rounded,
                  size: 26,
                  color: Color(0xFFD97706),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomedWritingStrip(
    NotePage page,
    int pageIndex,
    Rect focusRect,
  ) {
    final pageSize = PaperMetrics.pageSize(isLandscape: page.isLandscape);
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final scale = (constraints.maxWidth / focusRect.width).clamp(1.6, 3.2);
        return ClipRect(
          child: Transform(
            transform: Matrix4.identity()
              ..scale(scale, scale)
              ..translate(-focusRect.left, -focusRect.top),
            child: SizedBox(
              width: pageSize.width,
              height: pageSize.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      size: pageSize,
                      painter: CanvasPainter(
                        page: page,
                        pdfBackgroundImage: page.pdfBackgroundPath != null
                            ? _pdfImageCache[page.pdfBackgroundPath!]
                            : null,
                        repaintVersion: _repaintVersion,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) =>
                          _handlePointerDown(e, page, pageIndex),
                      onPointerMove: (e) => _handlePointerMove(e, page),
                      onPointerUp: (e) => _handlePointerUp(e, page),
                      onPointerCancel: (e) => _handlePointerUp(e, page),
                      child: CustomPaint(
                        size: pageSize,
                        painter: ActiveStrokePainter(
                          activeStroke: _activeStrokeNotifier,
                          hoverPosition: _hoverPosNotifier,
                          eraserCursor: _eraserCursorNotifier,
                          lassoPath: _lassoPathNotifier,
                          tapeDraftRect: _tapeDraftNotifier,
                          isDarkPaper: page.paperColor == PaperColorType.dark,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // INTERACTIVE ELEMENT OVERLAYS (TEXT, IMAGE, STENCIL)
  // ===========================================================================

  Widget _buildTextOverlay(NotePage page, TextElement element) {
    final bool isSelected = _selectedTextId == element.id;
    final bool isEditing = _editingTextId == element.id;
    final bool interactive = _activeTool == EditorTool.panZoom ||
        _activeTool == EditorTool.textBox ||
        isSelected ||
        isEditing;

    return Positioned(
      left: element.x,
      top: element.y,
      child: IgnorePointer(
        ignoring: !interactive,
        child: GestureDetector(
          onTap: () {
            if (!isSelected) {
              setState(() {
                _selectedTextId = element.id;
                _selectedImageId = null;
                _selectedStencilId = null;
              });
            } else if (!isEditing) {
              _startEditingText(element);
            }
          },
          onDoubleTap: () => _startEditingText(element),
          onPanUpdate: isEditing
              ? null
              : (details) {
                  final updatedList = page.textElements
                      .map((t) => t.id == element.id
                          ? t.copyWith(
                              x: t.x + details.delta.dx,
                              y: t.y + details.delta.dy,
                            )
                          : t)
                      .toList();
                  context.read<AppState>().updatePage(
                        _activeNotebookId,
                        page.copyWith(textElements: updatedList),
                      );
                },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: element.width,
                constraints: BoxConstraints(minHeight: element.height),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isEditing
                      ? Colors.white.withAlpha(225)
                      : Colors.transparent,
                  border: (isSelected || isEditing)
                      ? Border.all(color: EditorColors.activeBlue, width: 1.5)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: isEditing
                    ? TextField(
                        controller: _activeTextController,
                        focusNode: _activeTextFocusNode,
                        maxLines: null,
                        style: TextStyle(
                          fontSize: element.fontSize,
                          color: Color(element.colorValue),
                          fontWeight: element.isBold
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontStyle: element.isItalic
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Nhập văn bản / PTHH...',
                        ),
                      )
                    : Text(
                        element.text.isEmpty
                            ? 'Nhấn đúp để nhập'
                            : element.text,
                        style: TextStyle(
                          fontSize: element.fontSize,
                          color: element.text.isEmpty
                              ? Colors.grey
                              : Color(element.colorValue),
                          fontWeight: element.isBold
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontStyle: element.isItalic
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
              ),
              if (isSelected || isEditing)
                Positioned(
                  top: -32,
                  left: 0,
                  child: Material(
                    elevation: 4,
                    color: EditorColors.obsidianSurface,
                    borderRadius: BorderRadius.circular(16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.format_bold_rounded,
                            size: 16,
                            color: element.isBold
                                ? EditorColors.activeBlue
                                : Colors.white,
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            final updated = page.textElements
                                .map((t) => t.id == element.id
                                    ? t.copyWith(isBold: !t.isBold)
                                    : t)
                                .toList();
                            _commitPage(page.copyWith(textElements: updated));
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.format_italic_rounded,
                            size: 16,
                            color: element.isItalic
                                ? EditorColors.activeBlue
                                : Colors.white,
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            final updated = page.textElements
                                .map((t) => t.id == element.id
                                    ? t.copyWith(isItalic: !t.isItalic)
                                    : t)
                                .toList();
                            _commitPage(page.copyWith(textElements: updated));
                          },
                        ),
                        if (isEditing)
                          IconButton(
                            icon: const Icon(Icons.check_rounded,
                                size: 16, color: Color(0xFF34D399)),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            onPressed: () {
                              _commitActiveTextEdit();
                              setState(() {});
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 16, color: Color(0xFFEF4444)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            _editingTextId = null;
                            _selectedTextId = null;
                            final updated = page.textElements
                                .where((t) => t.id != element.id)
                                .toList();
                            _commitPage(
                              page.copyWith(textElements: updated),
                              undoSnapshot: page,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              if (isSelected)
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: GestureDetector(
                    onPanUpdate: (d) {
                      final updated = page.textElements
                          .map((t) => t.id == element.id
                              ? t.copyWith(
                                  width: math.max(80.0, t.width + d.delta.dx),
                                  height: math.max(36.0, t.height + d.delta.dy),
                                )
                              : t)
                          .toList();
                      context.read<AppState>().updatePage(
                            _activeNotebookId,
                            page.copyWith(textElements: updated),
                          );
                    },
                    child: _buildResizeHandle(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageOverlay(NotePage page, ImageElement img) {
    final bool interactive =
        _activeTool == EditorTool.image || _activeTool == EditorTool.lasso;
    final bool isSelected = interactive && _selectedImageId == img.id;
    final bool hasHighRes = _elementImageCache.containsKey(img.filePath);
    final file = File(img.filePath);

    void updateImg(ImageElement Function(ImageElement e) transform) {
      final updated = page.imageElements
          .map((e) => e.id == img.id ? transform(e) : e)
          .toList();
      context.read<AppState>().updatePage(
            _activeNotebookId,
            page.copyWith(imageElements: updated),
          );
    }

    return Positioned(
      left: img.x,
      top: img.y,
      child: IgnorePointer(
        ignoring: !interactive,
        child: Transform.rotate(
          angle: img.rotation,
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedImageId = img.id;
              _selectedTextId = null;
              _selectedStencilId = null;
            }),
            onPanUpdate: (d) =>
                updateImg((e) => e.copyWith(x: e.x + d.delta.dx, y: e.y + d.delta.dy)),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Transparent hit/border box (full-res cropped image is painted by CanvasPainter!)
                Container(
                  width: img.width,
                  height: img.height,
                  decoration: BoxDecoration(
                    border: isSelected
                        ? Border.all(color: EditorColors.activeBlue, width: 2)
                        : null,
                  ),
                  child: hasHighRes
                      ? const SizedBox.expand()
                      : (file.existsSync()
                          ? Image.file(
                              file,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            )
                          : Container(
                              color: Colors.grey.shade200,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                size: 32,
                              ),
                            )),
                ),
                if (isSelected) ...[
                  // 6-Button Floating Image Action Pill above image
                  Positioned(
                    top: -46,
                    left: -40,
                    child: ImageActionPill(
                      onCropRect: () =>
                          _openImageCrop(page, img, ImageCropMode.rectangle),
                      onCropFreehand: () =>
                          _openImageCrop(page, img, ImageCropMode.freehand),
                      onCopy: () {
                        final dup = img.copyWith(
                          id: _uuid.v4(),
                          x: img.x + 24,
                          y: img.y + 24,
                        );
                        _commitPage(
                          page.copyWith(
                            imageElements: [...page.imageElements, dup],
                          ),
                          undoSnapshot: page,
                        );
                        setState(() => _selectedImageId = dup.id);
                      },
                      onCut: () {
                        _lassoController.clear();
                        _selectedImageId = null;
                        final updated = page.imageElements
                            .where((e) => e.id != img.id)
                            .toList();
                        _commitPage(
                          page.copyWith(imageElements: updated),
                          undoSnapshot: page,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            duration: Duration(milliseconds: 1000),
                            content: Text('Đã cắt hình ảnh'),
                          ),
                        );
                      },
                      onAddToStickers: () async {
                        await context
                            .read<AppState>()
                            .addCustomSticker(img.filePath);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              duration: Duration(milliseconds: 1200),
                              content: Text('Đã lưu vào bộ Hình dán của bạn'),
                            ),
                          );
                        }
                      },
                      onDelete: () {
                        _selectedImageId = null;
                        final updated = page.imageElements
                            .where((e) => e.id != img.id)
                            .toList();
                        _commitPage(
                          page.copyWith(imageElements: updated),
                          undoSnapshot: page,
                        );
                      },
                    ),
                  ),
                  // Rotate handle (bottom-center stem)
                  Positioned(
                    left: img.width * 0.5 - 12,
                    bottom: -34,
                    child: _buildMiniCircleButton(
                      icon: Icons.rotate_right_rounded,
                      color: EditorColors.activeBlue,
                      onTap: () {
                        final updated = page.imageElements
                            .map((e) => e.id == img.id
                                ? e.copyWith(rotation: e.rotation + math.pi / 12)
                                : e)
                            .toList();
                        _commitPage(page.copyWith(imageElements: updated));
                      },
                    ),
                  ),
                  // 8 Resize Handles: 4 corners + 4 edge midpoints
                  // Top-Left
                  Positioned(
                    left: -8,
                    top: -8,
                    child: GestureDetector(
                      onPanUpdate: (d) => updateImg((e) {
                        final nw = math.max(32.0, e.width - d.delta.dx);
                        final nh = math.max(32.0, e.height - d.delta.dy);
                        return e.copyWith(
                          x: e.x + (e.width - nw),
                          y: e.y + (e.height - nh),
                          width: nw,
                          height: nh,
                        );
                      }),
                      child: _buildResizeHandle(),
                    ),
                  ),
                  // Top-Center
                  Positioned(
                    left: img.width * 0.5 - 8,
                    top: -8,
                    child: GestureDetector(
                      onPanUpdate: (d) => updateImg((e) {
                        final nh = math.max(32.0, e.height - d.delta.dy);
                        return e.copyWith(
                          y: e.y + (e.height - nh),
                          height: nh,
                        );
                      }),
                      child: _buildResizeHandle(),
                    ),
                  ),
                  // Top-Right
                  Positioned(
                    right: -8,
                    top: -8,
                    child: GestureDetector(
                      onPanUpdate: (d) => updateImg((e) {
                        final nh = math.max(32.0, e.height - d.delta.dy);
                        return e.copyWith(
                          y: e.y + (e.height - nh),
                          width: math.max(32.0, e.width + d.delta.dx),
                          height: nh,
                        );
                      }),
                      child: _buildResizeHandle(),
                    ),
                  ),
                  // Middle-Left
                  Positioned(
                    left: -8,
                    top: img.height * 0.5 - 8,
                    child: GestureDetector(
                      onPanUpdate: (d) => updateImg((e) {
                        final nw = math.max(32.0, e.width - d.delta.dx);
                        return e.copyWith(
                          x: e.x + (e.width - nw),
                          width: nw,
                        );
                      }),
                      child: _buildResizeHandle(),
                    ),
                  ),
                  // Middle-Right
                  Positioned(
                    right: -8,
                    top: img.height * 0.5 - 8,
                    child: GestureDetector(
                      onPanUpdate: (d) => updateImg(
                        (e) => e.copyWith(
                          width: math.max(32.0, e.width + d.delta.dx),
                        ),
                      ),
                      child: _buildResizeHandle(),
                    ),
                  ),
                  // Bottom-Left
                  Positioned(
                    left: -8,
                    bottom: -8,
                    child: GestureDetector(
                      onPanUpdate: (d) => updateImg((e) {
                        final nw = math.max(32.0, e.width - d.delta.dx);
                        return e.copyWith(
                          x: e.x + (e.width - nw),
                          width: nw,
                          height: math.max(32.0, e.height + d.delta.dy),
                        );
                      }),
                      child: _buildResizeHandle(),
                    ),
                  ),
                  // Bottom-Center
                  Positioned(
                    left: img.width * 0.5 - 8,
                    bottom: -8,
                    child: GestureDetector(
                      onPanUpdate: (d) => updateImg(
                        (e) => e.copyWith(
                          height: math.max(32.0, e.height + d.delta.dy),
                        ),
                      ),
                      child: _buildResizeHandle(),
                    ),
                  ),
                  // Bottom-Right
                  Positioned(
                    right: -8,
                    bottom: -8,
                    child: GestureDetector(
                      onPanUpdate: (d) => updateImg(
                        (e) => e.copyWith(
                          width: math.max(32.0, e.width + d.delta.dx),
                          height: math.max(32.0, e.height + d.delta.dy),
                        ),
                      ),
                      child: _buildResizeHandle(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentOverlay(NotePage page, AttachmentElement att) {
    final ext = att.fileExtension.toUpperCase();
    final Color badgeColor = (ext == 'PPT' || ext == 'PPTX')
        ? const Color(0xFFEA580C)
        : (ext == 'DOC' || ext == 'DOCX')
            ? const Color(0xFF2563EB)
            : (ext == 'PDF')
                ? const Color(0xFFDC2626)
                : const Color(0xFF0F766E);
    final sizeKb = (att.fileSizeBytes / 1024).toStringAsFixed(1);

    return Positioned(
      left: att.x,
      top: att.y,
      child: GestureDetector(
        onPanUpdate: (d) {
          final updated = page.attachmentElements
              .map((a) => a.id == att.id
                  ? a.copyWith(x: a.x + d.delta.dx, y: a.y + d.delta.dy)
                  : a)
              .toList();
          context.read<AppState>().updatePage(
                _activeNotebookId,
                page.copyWith(attachmentElements: updated),
              );
        },
        child: Container(
          width: att.width,
          height: att.height,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: EditorColors.obsidianSurface.withAlpha(240),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(45),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  ext.isEmpty ? 'FILE' : ext,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      att.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$sizeKb KB',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Xóa tệp đính kèm',
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.white70,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final updated = page.attachmentElements
                      .where((a) => a.id != att.id)
                      .toList();
                  _commitPage(
                    page.copyWith(attachmentElements: updated),
                    undoSnapshot: page,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStencilOverlay(NotePage page, StencilElement stencil) {
    final bool isSelected = _selectedStencilId == stencil.id;
    final bool interactive = _activeTool == EditorTool.panZoom || isSelected;

    return Positioned(
      left: stencil.x,
      top: stencil.y,
      child: IgnorePointer(
        ignoring: !interactive,
        child: GestureDetector(
          onTap: () => setState(() {
            _selectedStencilId = stencil.id;
            _selectedTextId = null;
            _selectedImageId = null;
          }),
          onPanUpdate: (d) {
            final updated = page.stencilElements
                .map((s) => s.id == stencil.id
                    ? s.copyWith(x: s.x + d.delta.dx, y: s.y + d.delta.dy)
                    : s)
                .toList();
            context.read<AppState>().updatePage(
                  _activeNotebookId,
                  page.copyWith(stencilElements: updated),
                );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: stencil.width,
                height: stencil.height,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: isSelected
                      ? Border.all(color: EditorColors.activeBlue, width: 1.5)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              if (isSelected) ...[
                Positioned(
                  top: -14,
                  right: -14,
                  child: _buildMiniCircleButton(
                    icon: Icons.close_rounded,
                    color: const Color(0xFFEF4444),
                    onTap: () {
                      _selectedStencilId = null;
                      final updated = page.stencilElements
                          .where((s) => s.id != stencil.id)
                          .toList();
                      _commitPage(
                        page.copyWith(stencilElements: updated),
                        undoSnapshot: page,
                      );
                    },
                  ),
                ),
                Positioned(
                  top: -14,
                  left: -14,
                  child: _buildMiniCircleButton(
                    icon: Icons.rotate_right_rounded,
                    color: EditorColors.activeBlue,
                    onTap: () {
                      final updated = page.stencilElements
                          .map((s) => s.id == stencil.id
                              ? s.copyWith(rotation: s.rotation + math.pi / 6)
                              : s)
                          .toList();
                      _commitPage(page.copyWith(stencilElements: updated));
                    },
                  ),
                ),
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: GestureDetector(
                    onPanUpdate: (d) {
                      final delta = (d.delta.dx + d.delta.dy) * 0.5;
                      final updated = page.stencilElements
                          .map((s) => s.id == stencil.id
                              ? s.copyWith(
                                  width: math.max(36.0, s.width + delta),
                                  height: math.max(36.0, s.height + delta),
                                )
                              : s)
                          .toList();
                      context.read<AppState>().updatePage(
                            _activeNotebookId,
                            page.copyWith(stencilElements: updated),
                          );
                    },
                    child: _buildResizeHandle(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResizeHandle() {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: EditorColors.activeBlue, width: 2),
      ),
      child: const Icon(
        Icons.open_in_full_rounded,
        size: 10,
        color: EditorColors.activeBlue,
      ),
    );
  }

  Widget _buildMiniCircleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }
}
