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
import '../pdf/pdf_import_progress_overlay.dart';
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
  final TransformationController _whiteboardTransformController =
      TransformationController();
  final ScrollController _verticalScrollController = ScrollController();
  bool _whiteboardCenteredOnce = false;
  final ValueNotifier<double> _whiteboardZoomNotifier = ValueNotifier(1.0);
  final ValueNotifier<({String id, double x, double y, double w, double h})?>
      _imageDragNotifier = ValueNotifier(null);
  ({
    Offset startGlobal,
    double startX,
    double startY,
    double startW,
    double startH,
    double canvasScale,
  })? _cornerResizeStart;
  final ValueNotifier<({String id, double x, double y, double w, double h})?>
      _stickyDragNotifier = ValueNotifier(null);
  final ValueNotifier<Stroke?> _activeStickyStrokeNotifier = ValueNotifier(null);
  String? _activeStickyStrokeNoteId;
  final ValueNotifier<Offset> _lassoDragOffsetNotifier = ValueNotifier(Offset.zero);
  final ValueNotifier<({String pageId, List<Stroke> strokes})?>
      _erasingStrokesNotifier = ValueNotifier(null);
  List<Stroke>? _workingEraseStrokes;
  Offset? _lastEraserPoint;
  final ValueNotifier<({String id, double left, double top, double right, double bottom})?>
      _cropDraftNotifier = ValueNotifier(null);
  String? _croppingImageId;
  bool _shapeSnappedLive = false;
  final ValueNotifier<double> _pullAddProgressNotifier = ValueNotifier(0.0);
  final GlobalKey _viewportStackKey = GlobalKey();
  final Map<String, TextEditingController> _stickyControllers = {};
  late PageController _horizontalPageController;
  final LassoController _lassoController = LassoController();
  final PalmRejectionFilter _palmFilter = PalmRejectionFilter(stylusOnlyMode: false);
  final LaserPointerController _laserController = LaserPointerController();
  final ImagePicker _imagePicker = ImagePicker();
  final PdfImportService _pdfImportService = PdfImportService();
  final PdfExportService _pdfExportService = PdfExportService();

  // 144Hz zero-rebuild ValueNotifiers for ActiveStrokePainter (hover ring removed)
  final ValueNotifier<Stroke?> _activeStrokeNotifier = ValueNotifier(null);
  final ValueNotifier<Offset?> _eraserCursorNotifier = ValueNotifier(null);
  final ValueNotifier<List<Offset>> _lassoPathNotifier = ValueNotifier(const []);
  final ValueNotifier<Rect?> _tapeDraftNotifier = ValueNotifier(null);
  Size _editorViewportSize = const Size(900, 650);
  bool _verticalCenteredOnce = false;

  // Active notebook & page state
  late final AppState _appStateRef;
  late String _activeNotebookId;
  int _currentPageIndex = 0;
  int _renderedWindowCenter = 0;
  bool _isScrubbingPages = false;
  Timer? _scrubPrefetchTimer;
  String? _activeDrawingPageId;
  final List<StrokePoint> _liveStrokePoints = <StrokePoint>[];
  String? _cachedLayoutNotebookId;
  List<NotePage>? _cachedLayoutPagesRef;
  int _cachedLayoutPageCount = -1;
  List<double> _cachedPageTops = const [];
  double _cachedTotalHeight = 0.0;
  double _cachedMaxPageWidth = 0.0;
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
  double _eraserRadius = 18.0;
  Color _penColor = EditorColors.penSwatches[2];
  Color _highlighterColor = EditorColors.highlighterSwatches.first;
  double _penWidth = 2.6;
  double _highlighterWidth = 18.0;
  double _penOpacity = 1.0;
  double _highlighterOpacity = 0.45;
  double _pressureSensitivity = 0.75;
  bool _eyedropperActive = false;
  bool _isDrawingPointerDown = false;
  bool _isStylusDown = false;
  bool _isStylusHovering = false;
  Timer? _stylusHoverTimer;
  Matrix4? _lockedMatrixDuringStylus;
  Matrix4? _lockedWhiteboardMatrixDuringStylus;
  bool _stylusPanMode = false;
  bool _isOverlayDragging = false;
  final Set<int> _activeTouchPointers = {};
  final Set<int> _overlayTouchPointers = {};

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

  // Gesture tracking (top-level 2-finger Undo / 3-finger Redo)
  final Map<int, Offset> _pointerDownPositions = {};
  DateTime? _multiFingerDownTime;
  int _maxSimultaneousPointers = 0;
  bool _multiFingerMovedTooMuch = false;
  final Map<int, Offset> _tapTouchStarts = {};
  DateTime? _tapTouchStartTime;
  int _tapMaxTouchCount = 0;
  bool _tapMovedTooFar = false;
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
  final ValueNotifier<int> _recordingElapsedMsNotifier = ValueNotifier<int>(0);
  Timer? _recordingElapsedTimer;
  String? _selectedAudioId;
  bool _isAudioBarVisible = false;
  String? _playingAudioId;
  bool _isAudioPlaying = false;
  final ValueNotifier<int> _audioPositionMsNotifier = ValueNotifier<int>(0);
  double _audioSpeed = 1.0;
  Timer? _audioPollTimer;

  void _syncStylusDrawingState() {
    _appStateRef.setStylusDrawingActive(_isStylusDown || _isDrawingPointerDown);
  }

  Color get _effectiveColor =>
      _activeTool == EditorTool.highlighter ? _highlighterColor : _penColor;

  double get _effectiveWidth =>
      _activeTool == EditorTool.highlighter ? _highlighterWidth : _penWidth;

  double get _effectiveOpacity =>
      _activeTool == EditorTool.highlighter ? _highlighterOpacity : _penOpacity;

  EditorTool _editorToolFromStrokeTool(ToolType t) {
    switch (t) {
      case ToolType.fountainPen:
        return EditorTool.fountainPen;
      case ToolType.ballpointPen:
        return EditorTool.ballpointPen;
      case ToolType.pencil:
        return EditorTool.pencil;
      case ToolType.brushPen:
        return EditorTool.brushPen;
      case ToolType.highlighter:
        return EditorTool.highlighter;
      default:
        return EditorTool.fountainPen;
    }
  }

  void _persistPenPrefs() {
    if (!mounted) return;
    context.read<AppState>().updatePenPrefs(
          lastPenTool: _lastPenTool.toStrokeToolType(),
          // ignore: deprecated_member_use
          lastPenColorValue: _penColor.value,
          lastPenWidth: _penWidth,
          lastPenOpacity: _penOpacity,
          lastPressureSensitivity: _pressureSensitivity,
          lastSmoothingEnabled: _autoNeatenEnabled,
          lastSmoothingStrength: _smoothingStrength,
          // ignore: deprecated_member_use
          lastHighlighterColorValue: _highlighterColor.value,
          lastHighlighterWidth: _highlighterWidth,
          lastEraserRadius: _eraserRadius,
        );
  }

  @override
  void initState() {
    super.initState();
    _activeNotebookId = widget.notebookId;
    _currentPageIndex = widget.initialPageIndex;
    _renderedWindowCenter = _currentPageIndex;
    _horizontalPageController = PageController(initialPage: _currentPageIndex);
    _lassoController.addListener(_onLassoChanged);

    // Restore user's last-used writing tool, color, size, opacity, smoothing & eraser size
    final appState = context.read<AppState>();
    _appStateRef = appState;
    _lastPenTool = _editorToolFromStrokeTool(appState.lastPenTool);
    _activeTool = _lastPenTool;
    _penColor = Color(appState.lastPenColorValue);
    _penWidth = appState.lastPenWidth;
    _penOpacity = appState.lastPenOpacity;
    _pressureSensitivity = appState.lastPressureSensitivity;
    _autoNeatenEnabled = appState.lastSmoothingEnabled;
    _smoothingStrength = appState.lastSmoothingStrength;
    _highlighterColor = Color(appState.lastHighlighterColorValue);
    _highlighterWidth = appState.lastHighlighterWidth;
    _eraserRadius = appState.lastEraserRadius.clamp(5.0, 35.0);
    _palmFilter.stylusOnlyMode = appState.palmRejectionEnabled;

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
    _appStateRef.setStylusDrawingActive(false);
    _appStateRef.flushPendingSaves();
    _stylusHoverTimer?.cancel();
    _shapeHoldTimer?.cancel();
    _scrubPrefetchTimer?.cancel();
    _recordingElapsedTimer?.cancel();
    _audioPollTimer?.cancel();
    HardwareService.instance.stopAudio();
    _stylusDoubleTapSub?.cancel();
    _lassoController.removeListener(_onLassoChanged);
    _lassoController.dispose();
    _laserController.dispose();
    _transformController.dispose();
    _whiteboardTransformController.dispose();
    for (final ctrl in _stickyControllers.values) {
      ctrl.dispose();
    }
    _verticalScrollController.dispose();
    _horizontalPageController.dispose();
    _activeStrokeNotifier.dispose();
    _eraserCursorNotifier.dispose();
    _lassoPathNotifier.dispose();
    _tapeDraftNotifier.dispose();
    _whiteboardZoomNotifier.dispose();
    _imageDragNotifier.dispose();
    _stickyDragNotifier.dispose();
    _activeStickyStrokeNotifier.dispose();
    _lassoDragOffsetNotifier.dispose();
    _erasingStrokesNotifier.dispose();
    _cropDraftNotifier.dispose();
    _pullAddProgressNotifier.dispose();
    _recordingElapsedMsNotifier.dispose();
    _audioPositionMsNotifier.dispose();
    _activeTextController?.dispose();
    _activeTextFocusNode?.dispose();
    for (final img in _pdfImageCache.values) {
      img.dispose();
    }
    for (final img in _elementImageCache.values) {
      img.dispose();
    }
    _pdfImageCache.clear();
    _elementImageCache.clear();
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

  Future<void> _switchNotebookTab(String notebookId) async {
    if (notebookId == _activeNotebookId) return;
    _commitActiveTextEdit();
    // Auto-stop and save active audio recording on current page before switching tabs
    if (_isRecordingAudio) {
      final curNb = _getNotebook(context, listen: false);
      final curPage = _getCurrentPage(curNb);
      if (curPage != null) {
        await _toggleAudioRecording(curPage);
      }
    }
    if (!mounted) return;
    setState(() {
      _activeNotebookId = notebookId;
      _currentPageIndex = 0;
      _renderedWindowCenter = 0;
      _isScrubbingPages = false;
      _scrubPrefetchTimer?.cancel();
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

  void _ensureVerticalLayoutCache(Notebook notebook) {
    final count = notebook.pages.length;
    if (_cachedLayoutNotebookId == notebook.id &&
        identical(_cachedLayoutPagesRef, notebook.pages) &&
        _cachedLayoutPageCount == count) {
      return;
    }
    _cachedLayoutNotebookId = notebook.id;
    _cachedLayoutPagesRef = notebook.pages;
    _cachedLayoutPageCount = count;
    if (count == 0) {
      _cachedPageTops = const [];
      _cachedMaxPageWidth = 0.0;
      _cachedTotalHeight = 18.0 + 18.0 + 18.0 + 44.0 + 36.0;
      return;
    }
    final tops = List<double>.filled(count, 18.0);
    double cursorY = 18.0;
    double maxW = 0.0;
    for (int i = 0; i < count; i++) {
      tops[i] = cursorY;
      final size =
          PaperMetrics.pageSize(isLandscape: notebook.pages[i].isLandscape);
      if (size.width > maxW) maxW = size.width;
      cursorY += size.height;
      if (i < count - 1) cursorY += 14.0;
    }
    _cachedPageTops = tops;
    _cachedMaxPageWidth = maxW;
    _cachedTotalHeight = cursorY + 18.0 + 18.0 + 44.0 + 36.0;
  }

  double _totalVerticalContentHeight(Notebook notebook) {
    _ensureVerticalLayoutCache(notebook);
    return _cachedTotalHeight;
  }

  double _maxVerticalPageWidth(Notebook notebook) {
    _ensureVerticalLayoutCache(notebook);
    return _cachedMaxPageWidth;
  }

  double _pageTopOffsetY(Notebook notebook, int pageIndex) {
    if (notebook.pages.isEmpty) return 18.0;
    _ensureVerticalLayoutCache(notebook);
    final clamped = pageIndex.clamp(0, _cachedPageTops.length - 1);
    return _cachedPageTops[clamped];
  }

  void _jumpToPage(int index) {
    final appState = context.read<AppState>();
    final notebook = _getNotebook(context, listen: false);
    if (notebook == null || notebook.pages.isEmpty) return;
    final prevIdx = _currentPageIndex;
    final clampedIdx = index.clamp(0, notebook.pages.length - 1);
    setState(() {
      _currentPageIndex = clampedIdx;
      _renderedWindowCenter = clampedIdx;
    });
    if (!appState.verticalContinuousScroll &&
        _horizontalPageController.hasClients) {
      if ((clampedIdx - prevIdx).abs() > 3) {
        _horizontalPageController.jumpToPage(clampedIdx);
      } else {
        _horizontalPageController.animateToPage(
          clampedIdx,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    } else if (appState.verticalContinuousScroll && !notebook.isWhiteboard) {
      final m = _transformController.value;
      final double scale = m.getMaxScaleOnAxis().clamp(0.5, 4.0);
      final double maxPageW = _maxVerticalPageWidth(notebook);
      final double contentW = maxPageW + 48.0;
      final double scaledW = contentW * scale;
      double tx = m.getTranslation().x;
      if (!appState.freePaperMovement && _editorViewportSize.width > 0) {
        tx = scaledW <= _editorViewportSize.width
            ? (_editorViewportSize.width - scaledW) * 0.5
            : tx.clamp(_editorViewportSize.width - scaledW, 0.0).toDouble();
      }
      final double contentH = _totalVerticalContentHeight(notebook);
      final double scaledH = contentH * scale;
      final double pageTopY = _pageTopOffsetY(notebook, clampedIdx);
      double targetTy = -(pageTopY * scale);
      if (_editorViewportSize.height > 0) {
        if (appState.freePaperMovement) {
          final double padTop = _editorViewportSize.height * 0.40;
          final double padBottom = _editorViewportSize.height * 0.45;
          final double minTy =
              math.min(0.0, _editorViewportSize.height - scaledH) - padBottom;
          targetTy = targetTy
              .clamp(math.min(minTy, padTop), math.max(minTy, padTop))
              .toDouble();
        } else {
          final double minTy =
              math.min(0.0, _editorViewportSize.height - scaledH) - 100.0;
          targetTy = targetTy.clamp(minTy, 24.0).toDouble();
        }
      }
      _transformController.value = Matrix4.identity()
        ..translate(tx, targetTy)
        ..scale(scale, scale);
    }
    _prefetchNearbyPdfPages(notebook);
  }

  // ===========================================================================
  // PDF BACKGROUND & ELEMENT IMAGE DECODING (Windowed LRU to prevent OOM)
  // ===========================================================================

  static const int _maxCachedPdfPages = 12;
  static const int _pdfPreloadRadius = 4;

  void _touchPdfCache(String path) {
    final existing = _pdfImageCache.remove(path);
    if (existing != null) {
      _pdfImageCache[path] = existing;
    }
  }

  Set<String> _nearbyPdfKeepPaths(Notebook notebook) {
    final int center = _currentPageIndex.clamp(0, notebook.pages.length - 1);
    final int keepStart = math.max(0, center - (_pdfPreloadRadius + 2));
    final int keepEnd =
        math.min(notebook.pages.length - 1, center + (_pdfPreloadRadius + 2));
    final keepPaths = <String>{};
    for (int i = keepStart; i <= keepEnd; i++) {
      final p = notebook.pages[i].pdfBackgroundPath;
      if (p != null && p.isNotEmpty) keepPaths.add(p);
    }
    return keepPaths;
  }

  void _prefetchNearbyPdfPages(Notebook notebook) {
    if (notebook.pages.isEmpty) return;
    final int center = _currentPageIndex.clamp(0, notebook.pages.length - 1);
    final int start = math.max(0, center - _pdfPreloadRadius);
    final int end = math.min(notebook.pages.length - 1, center + _pdfPreloadRadius);
    for (int i = start; i <= end; i++) {
      final path = notebook.pages[i].pdfBackgroundPath;
      if (path != null && path.isNotEmpty) {
        if (_pdfImageCache.containsKey(path)) {
          _touchPdfCache(path);
        } else {
          _ensurePdfImageLoaded(path);
        }
      }
    }

    if (_pdfImageCache.length <= _maxCachedPdfPages) return;
    final keepPaths = _nearbyPdfKeepPaths(notebook);

    final evictedImages = <ui.Image>[];
    final candidates = _pdfImageCache.keys.toList();
    for (final key in candidates) {
      if (_pdfImageCache.length <= _maxCachedPdfPages) break;
      if (keepPaths.contains(key)) continue;
      final removed = _pdfImageCache.remove(key);
      if (removed != null) evictedImages.add(removed);
    }
    if (evictedImages.isNotEmpty) {
      // Wait 2 frames before native ui.Image.dispose() so active display lists stop referencing it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _repaintVersion++);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final img in evictedImages) {
            img.dispose();
          }
        });
      });
    }
  }

  void _ensurePdfImageLoaded(String? path) {
    if (path == null || path.isEmpty) return;
    if (_pdfImageCache.containsKey(path)) {
      _touchPdfCache(path);
      return;
    }
    if (_loadingPdfPaths.contains(path)) return;
    _loadingPdfPaths.add(path);
    _loadPdfImage(path);
  }

  Future<void> _loadPdfImage(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 2048);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final notebook = _getNotebook(context, listen: false);
      final Set<String> keepPaths =
          notebook != null && notebook.pages.isNotEmpty
              ? _nearbyPdfKeepPaths(notebook)
              : const <String>{};
      if (keepPaths.isNotEmpty && !keepPaths.contains(path)) {
        // Bỏ qua ảnh cũ vừa giải mã xong sau khi người dùng đã kéo tới vị trí khác xa
        frame.image.dispose();
        return;
      }
      final evictedImages = <ui.Image>[];
      setState(() {
        _pdfImageCache[path] = frame.image;
        if (_pdfImageCache.length > _maxCachedPdfPages + 4) {
          final keys = _pdfImageCache.keys.toList();
          for (final k in keys) {
            if (_pdfImageCache.length <= _maxCachedPdfPages + 4) break;
            if (k == path || keepPaths.contains(k)) continue;
            final removed = _pdfImageCache.remove(k);
            if (removed != null) evictedImages.add(removed);
          }
        }
        _repaintVersion++;
      });
      if (evictedImages.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final img in evictedImages) {
            img.dispose();
          }
        });
      }
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
    }
  }

  void _handlePointerDown(
    PointerDownEvent event,
    NotePage page,
    int pageIndex,
  ) {
    _currentPageIndex = pageIndex;
    _activeDrawingPageId = page.id;

    final bool isStylusEvent = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    if (isStylusEvent) {
      if (!_isStylusDown) {
        setState(() => _isStylusDown = true);
        _syncStylusDrawingState();
      }
      // When Stylus-Pan Mode is ON, M-Pencil 3 ONLY scrolls/pans and never draws!
      if (_stylusPanMode) return;
    } else if (event.kind == PointerDeviceKind.touch) {
      // _activeTouchPointers is managed by the outer viewport Listener.
      if (_activeTouchPointers.length >= 2 && !_isStylusDown) {
        _cancelActiveGesture();
        return;
      }
    }

    // Track multi-finger gestures (touch only — NEVER let resting touch block a real stylus!)
    if (!isStylusEvent) {
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
    }

    final appState = context.read<AppState>();
    _palmFilter.stylusOnlyMode = appState.palmRejectionEnabled;

    if (appState.readOnlyMode || _activeTool == EditorTool.panZoom) return;
    // Unconditionally accept real M-Pencil 3 stylus events; only filter touch events!
    final bool allowThisPointer =
        isStylusEvent || _palmFilter.shouldAccept(event);

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
      _persistPenPrefs();
      return;
    }

    final pos = (_rulerVisible && _activeTool.isDrawingTool)
        ? _snapToViewportRuler(event, rawPos, page)
        : rawPos;

    // Study Tape: tap existing tape to toggle reveal/hide, or drag to create new tape
    if (_activeTool == EditorTool.studyTape) {
      if (!allowThisPointer) return;
      final hitTape = _findTapeAt(page, rawPos);
      if (hitTape != null) {
        final updatedTapes = page.tapeElements
            .map((t) =>
                t.id == hitTape.id ? t.copyWith(isRevealed: !t.isRevealed) : t)
            .toList();
        _commitPage(page.copyWith(tapeElements: updatedTapes));
        return;
      }
      if (!_isDrawingPointerDown) {
        setState(() => _isDrawingPointerDown = true);
        _syncStylusDrawingState();
      }
      _tapeDragStart = rawPos;
      _tapeDraftNotifier.value = Rect.fromPoints(rawPos, rawPos);
      return;
    }

    // Laser Pointer: lock viewport pan while laser pointer is held down
    if (_activeTool == EditorTool.laserPointer) {
      if (!allowThisPointer) return;
      _currentPageIndex = pageIndex;
      if (!_isDrawingPointerDown) {
        setState(() => _isDrawingPointerDown = true);
        _syncStylusDrawingState();
      }
      _laserController.beginStroke(rawPos, pageId: page.id);
      return;
    }

    if (_activeTool == EditorTool.textBox) {
      if (!allowThisPointer) return;
      _createTextElementAt(page, rawPos);
      return;
    }

    if (!allowThisPointer) return;

    if (!_isDrawingPointerDown) {
      setState(() => _isDrawingPointerDown = true);
      _syncStylusDrawingState();
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
      _workingEraseStrokes = List<Stroke>.from(page.strokes);
      _lastEraserPoint = rawPos;
      _eraserCursorNotifier.value = rawPos;
      _eraseAlongSegment(page, rawPos, rawPos);
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
      _shapeSnappedLive = false;
      _liveStrokePoints
        ..clear()
        ..add(firstPoint);
      _activeStrokeNotifier.value = Stroke(
        id: _uuid.v4(),
        toolType: _activeTool.toStrokeToolType(),
        // ignore: deprecated_member_use
        colorValue: effectiveInkColor.value,
        width: _effectiveWidth / zoomScale,
        points: _liveStrokePoints,
        isSmoothed: false,
        shapeType: ShapeType.none,
        audioId: _isRecordingAudio ? _activeRecordingId : null,
        audioTimeMs: _isRecordingAudio
            ? (DateTime.now().millisecondsSinceEpoch - _recordingStartMs)
            : null,
        zIndex: DateTime.now().millisecondsSinceEpoch,
      );
      _lastHoldCheckPos = pos;
      _scheduleShapeHoldTimer();
    }
  }

  void _handlePointerMove(PointerMoveEvent event, NotePage page) {
    final bool isStylusEvent = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    if (!isStylusEvent) {
      final startPos = _pointerDownPositions[event.pointer];
      if (startPos != null && (event.position - startPos).distance > 16.0) {
        _multiFingerMovedTooMuch = true;
      }
      if (_pointerDownPositions.length >= 2) return;
    }

    if (context.read<AppState>().readOnlyMode ||
        _activeTool == EditorTool.panZoom) {
      return;
    }
    if (isStylusEvent && _stylusPanMode) {
      return;
    }
    if (!isStylusEvent && !_palmFilter.shouldAccept(event)) return;

    final rawPos = event.localPosition;
    final pos = (_rulerVisible && _activeTool.isDrawingTool)
        ? _snapToViewportRuler(event, rawPos, page)
        : rawPos;

    if (_activeTool == EditorTool.studyTape && _tapeDragStart != null) {
      _tapeDraftNotifier.value = Rect.fromPoints(_tapeDragStart!, rawPos);
      return;
    }

    if (_activeTool == EditorTool.laserPointer) {
      _laserController.addPoint(rawPos, pageId: page.id);
      return;
    }

    if (_activeTool == EditorTool.lasso) {
      if (_isDraggingLassoSelection && _lastLassoDragPos != null) {
        final delta = rawPos - _lastLassoDragPos!;
        _lastLassoDragPos = rawPos;
        _lassoDragOffsetNotifier.value = _lassoDragOffsetNotifier.value + delta;
      } else if (_lassoController.isDrawingLasso) {
        _lassoController.updateLasso(rawPos);
      }
      return;
    }

    if (_activeTool == EditorTool.eraser) {
      _eraserCursorNotifier.value = rawPos;
      _eraseAlongSegment(page, _lastEraserPoint ?? rawPos, rawPos);
      _lastEraserPoint = rawPos;
      return;
    }

    final current = _activeStrokeNotifier.value;
    if (current != null && _activeTool.isDrawingTool) {
      // Once hold-to-snap triggers:
      // - For ShapeType.line: smoothly aim/stretch ONLY the 2nd endpoint (NEVER append a 3rd point -> ZERO 90° hook!)
      // - For other snapped shapes (circle/rect/triangle): freeze points completely!
      if (_shapeSnappedLive || current.shapeType != ShapeType.none) {
        if (current.shapeType == ShapeType.line && current.points.length >= 2) {
          final startPt = current.points.first;
          double endX = pos.dx;
          double endY = pos.dy;
          if (current.toolType == ToolType.highlighter) {
            final dx = (endX - startPt.x).abs();
            final dy = (endY - startPt.y).abs();
            // Snap within ±12° of horizontal to dead-level textbook highlighting
            if (dx > 8.0 && dy <= dx * 0.2126) {
              endY = startPt.y;
            }
          }
          _activeStrokeNotifier.value = current.copyWith(
            points: [
              startPt,
              StrokePoint(
                x: endX,
                y: endY,
                pressure: startPt.pressure,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            ],
          );
        }
        return;
      }
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

      _liveStrokePoints.add(filtered);
      _activeStrokeNotifier.value = current.copyWith(
        points: _liveStrokePoints,
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
    final bool isStylusEvent = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    _shapeHoldTimer?.cancel();
    if (isStylusEvent) {
      if (_isStylusDown || _isDrawingPointerDown) {
        setState(() {
          _isStylusDown = false;
          _isDrawingPointerDown = false;
        });
        _syncStylusDrawingState();
      }
    } else if (_pointerDownPositions.isEmpty && _isDrawingPointerDown) {
      setState(() => _isDrawingPointerDown = false);
      _syncStylusDrawingState();
    }

    // Multi-finger tap Undo/Redo is handled by the top-level viewport Listener
    // so InteractiveViewer never swallows it and it never triggers twice.
    if (_pointerDownPositions.isEmpty && _maxSimultaneousPointers >= 2) {
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
        final totalDelta = _lassoDragOffsetNotifier.value;
        _lassoDragOffsetNotifier.value = Offset.zero;
        _isDraggingLassoSelection = false;
        _lastLassoDragPos = null;
        if (totalDelta != Offset.zero) {
          final movedPage = _lassoController.moveSelection(page, totalDelta);
          _commitPage(
            movedPage,
            undoSnapshot: _pageBeforeGesture ?? page,
          );
        }
        _pageBeforeGesture = null;
      } else if (_lassoController.isDrawingLasso) {
        _lassoController.finishLasso(page);
      }
      return;
    }

    if (_activeTool == EditorTool.eraser) {
      _eraserCursorNotifier.value = null;
      final finalStrokes = _workingEraseStrokes;
      _workingEraseStrokes = null;
      _lastEraserPoint = null;
      _erasingStrokesNotifier.value = null;
      if (_eraserChangedPage && finalStrokes != null) {
        _commitPage(
          page.copyWith(strokes: finalStrokes, updatedAt: DateTime.now()),
          undoSnapshot: _pageBeforeGesture ?? page,
        );
      }
      _pageBeforeGesture = null;
      _eraserChangedPage = false;
      return;
    }

    final live = _activeStrokeNotifier.value;
    _shapeSnappedLive = false;
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
          _commitPage(
            page.copyWith(strokes: remaining),
            undoSnapshot: page,
          );
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
      } else if (finalized.shapeType == ShapeType.none &&
          _autoNeatenEnabled &&
          _smoothingStrength > 0.01) {
        final smoothed = StrokeEngine.smoothAndNeatenStroke(
          finalized.points,
          stabilization: _smoothingStrength,
          autoNeaten: _autoNeatenEnabled,
          toolType: finalized.toolType,
        );
        finalized = finalized.copyWith(points: smoothed, isSmoothed: true);
      }

      if (finalized.shapeType == ShapeType.line &&
          finalized.points.length >= 2) {
        // Keep exact clean 2-point straight line (ZERO 90° end hook!)
        finalized = finalized.copyWith(
          points: [finalized.points.first, finalized.points.last],
          isSmoothed: true,
        );
      } else if (identical(finalized.points, _liveStrokePoints)) {
        finalized = finalized.copyWith(
          points: List<StrokePoint>.from(finalized.points),
        );
      }
      _liveStrokePoints.clear();

      _commitPage(
        page.copyWith(strokes: [...page.strokes, finalized]),
        undoSnapshot: page,
      );
    } else {
      _liveStrokePoints.clear();
    }
  }

  void _cancelActiveGesture() {
    _shapeHoldTimer?.cancel();
    _shapeSnappedLive = false;
    _activeStrokeNotifier.value = null;
    _liveStrokePoints.clear();
    _eraserCursorNotifier.value = null;
    _tapeDraftNotifier.value = null;
    _lassoDragOffsetNotifier.value = Offset.zero;
    _tapeDragStart = null;
    if (_isDrawingPointerDown) {
      setState(() => _isDrawingPointerDown = false);
      _syncStylusDrawingState();
    }
  }

  void _scheduleShapeHoldTimer() {
    _shapeHoldTimer?.cancel();
    if (_shapeSnappedLive) return;
    final appState = context.read<AppState>();
    if (!appState.holdToSnapShape && _activeTool != EditorTool.shape) return;

    _shapeHoldTimer = Timer(const Duration(milliseconds: 450), () {
      final live = _activeStrokeNotifier.value;
      if (!mounted || live == null || live.points.length < 4) return;

      // Highlighter hold-to-snap: snap directly to dead-straight 2-point line
      // (auto-level to horizontal if within ±12°!)
      if (live.toolType == ToolType.highlighter) {
        final startPt = live.points.first;
        final lastPt = live.points.last;
        final dx = lastPt.x - startPt.x;
        final dy = lastPt.y - startPt.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 24.0) return;
        final double snappedY =
            (dx.abs() > 8.0 && dy.abs() <= dx.abs() * 0.2126)
                ? startPt.y
                : lastPt.y;
        _shapeSnappedLive = true;
        _activeStrokeNotifier.value = live.copyWith(
          points: [
            startPt,
            StrokePoint(
              x: lastPt.x,
              y: snappedY,
              pressure: lastPt.pressure,
              timestamp: lastPt.timestamp,
            ),
          ],
          shapeType: ShapeType.line,
          isSmoothed: true,
        );
        return;
      }

      if (live.points.length < 6) return;
      final res = StrokeEngine.recognizeShape(live.points);
      if (res.recognized) {
        _shapeSnappedLive = true;
        final snappedPts = res.shapeType == ShapeType.line &&
                res.snappedPoints.length >= 2
            ? [res.snappedPoints.first, res.snappedPoints.last]
            : res.snappedPoints;
        _activeStrokeNotifier.value = live.copyWith(
          points: snappedPts,
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

  Offset _snapToViewportRuler(PointerEvent event, Offset rawPos, NotePage page) {
    final renderBox =
        _viewportStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return _rulerState.snapPointIfNearEdge(rawPos);
    final vpPos = renderBox.globalToLocal(event.position);
    final snappedVp = _rulerState.snapPointIfNearEdge(vpPos);
    if (snappedVp == vpPos) return rawPos;
    final Matrix4 m = page.isInfiniteWhiteboard
        ? _whiteboardTransformController.value
        : _transformController.value;
    final double scale = m.getMaxScaleOnAxis().clamp(0.25, 4.0);
    return rawPos + (snappedVp - vpPos) / scale;
  }

  /// Fast AABB check for whether [stroke] could possibly intersect [box].
  bool _strokeIntersectsBox(Stroke stroke, Rect box) {
    final bounds = CanvasPainter.strokeBounds(stroke);
    return !bounds.isEmpty && bounds.overlaps(box);
  }

  /// Zero-lag 144fps swept-segment eraser with fast AABB pre-filtering:
  /// skips non-overlapping strokes in nanoseconds and samples along [from -> to]
  /// every `max(3.0, radius * 0.4)` px so fast swipes never miss spots.
  void _eraseAlongSegment(NotePage page, Offset from, Offset to) {
    final working = _workingEraseStrokes ?? List<Stroke>.from(page.strokes);
    _workingEraseStrokes = working;
    final double eraserRadius = _eraserRadius.clamp(5.0, 35.0);
    final Rect sweepBox = Rect.fromLTRB(
      math.min(from.dx, to.dx) - eraserRadius,
      math.min(from.dy, to.dy) - eraserRadius,
      math.max(from.dx, to.dx) + eraserRadius,
      math.max(from.dy, to.dy) + eraserRadius,
    );

    // Fast AABB pre-filter: if zero strokes overlap the swept box, return immediately!
    bool anyCandidate = false;
    for (final s in working) {
      if (_strokeIntersectsBox(s, sweepBox)) {
        anyCandidate = true;
        break;
      }
    }
    if (!anyCandidate) return;

    final double segLen = (to - from).distance;
    final double step = math.max(3.0, eraserRadius * 0.4);
    final int steps = math.max(1, (segLen / step).ceil());

    bool changedAny = false;
    List<Stroke> cur = working;
    for (int sIdx = 0; sIdx <= steps; sIdx++) {
      final double t = steps == 0 ? 1.0 : sIdx / steps;
      final Offset pos = Offset(
        from.dx + (to.dx - from.dx) * t,
        from.dy + (to.dy - from.dy) * t,
      );
      final Rect ptBox = Rect.fromCircle(center: pos, radius: eraserRadius);
      if (_eraserMode == EraserMode.stroke) {
        final beforeLen = cur.length;
        cur = cur
            .where((s) =>
                !_strokeIntersectsBox(s, ptBox) ||
                !StrokeEngine.hitTestStroke(s, pos, tolerance: eraserRadius))
            .toList();
        if (cur.length != beforeLen) changedAny = true;
      } else {
        final nextStrokes = <Stroke>[];
        bool stepChanged = false;
        for (final s in cur) {
          if (!_strokeIntersectsBox(s, ptBox) ||
              !StrokeEngine.hitTestStroke(s, pos, tolerance: eraserRadius)) {
            nextStrokes.add(s);
            continue;
          }
          final split = StrokeEngine.precisionEraseStroke(
            s,
            pos,
            eraserRadius,
            idGenerator: _uuid.v4,
          );
          if (split.length != 1 || split.first.id != s.id) stepChanged = true;
          nextStrokes.addAll(split);
        }
        if (stepChanged) {
          cur = nextStrokes;
          changedAny = true;
        }
      }
    }

    if (changedAny) {
      _workingEraseStrokes = cur;
      _eraserChangedPage = true;
      _erasingStrokesNotifier.value = (pageId: page.id, strokes: cur);
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
      zIndex: DateTime.now().millisecondsSinceEpoch,
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

  /// Computes the local `(x, y)` coordinates on [page] (at [pageIdx])
  /// corresponding to the center of the currently visible editor viewport!
  Offset _visibleCenterOnPage(NotePage page, int pageIdx) {
    final pageSize = PaperMetrics.pageSize(
      isLandscape: page.isLandscape,
      isInfiniteWhiteboard: page.isInfiniteWhiteboard,
    );
    final viewportCenter = Offset(
      _editorViewportSize.width * 0.5,
      _editorViewportSize.height * 0.5,
    );

    if (page.isInfiniteWhiteboard) {
      final inv = Matrix4.tryInvert(_whiteboardTransformController.value);
      if (inv != null) {
        final pt = MatrixUtils.transformPoint(inv, viewportCenter);
        return Offset(
          pt.dx.clamp(120.0, pageSize.width - 120.0),
          pt.dy.clamp(120.0, pageSize.height - 120.0),
        );
      }
      return PaperMetrics.whiteboardCenter;
    }

    final inv = Matrix4.tryInvert(_transformController.value);
    if (inv != null) {
      final scenePt = MatrixUtils.transformPoint(inv, viewportCenter);
      final notebook = _getNotebook(context, listen: false);
      // In continuous vertical layout, accumulate Y offset of preceding pages + 14px gaps + 18px top padding
      double pageTopY = 18.0;
      if (notebook != null &&
          context.read<AppState>().verticalContinuousScroll) {
        for (int i = 0; i < pageIdx && i < notebook.pages.length; i++) {
          final p = notebook.pages[i];
          pageTopY += PaperMetrics.pageSize(isLandscape: p.isLandscape).height +
              14.0;
        }
      }
      // Horizontal padding is 24.0 in the vertical Column
      final localX = (scenePt.dx - 24.0).clamp(90.0, pageSize.width - 90.0);
      final localY =
          (scenePt.dy - pageTopY).clamp(90.0, pageSize.height - 90.0);
      return Offset(localX, localY);
    }

    return Offset(pageSize.width * 0.5, pageSize.height * 0.4);
  }

  Future<void> _insertTextFromChemistryHub(NotePage page, String text) async {
    final center = _visibleCenterOnPage(page, _currentPageIndex);
    final element = TextElement(
      id: _uuid.v4(),
      x: (center.dx - 140).clamp(16.0, 5600.0),
      y: (center.dy - 42).clamp(16.0, 5600.0),
      width: 280.0,
      height: 84.0,
      text: text,
      fontSize: 17.0,
      // ignore: deprecated_member_use
      colorValue: _penColor.value,
      zIndex: DateTime.now().millisecondsSinceEpoch,
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
    final center = _visibleCenterOnPage(page, _currentPageIndex);
    final stencil = StencilElement(
      id: _uuid.v4(),
      stencilId: stencilId,
      x: (center.dx - 70).clamp(16.0, 5700.0),
      y: (center.dy - 70).clamp(16.0, 5700.0),
      width: 140.0,
      height: 140.0,
      rotation: 0.0,
      // ignore: deprecated_member_use
      colorValue: _penColor.value,
      strokeWidth: 2.2,
      zIndex: DateTime.now().millisecondsSinceEpoch,
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
    ui.Image? decoded = _elementImageCache[savedPath];
    if (decoded == null) {
      try {
        final file = File(savedPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          if (mounted) {
            decoded = frame.image;
            _elementImageCache[savedPath] = decoded;
          } else {
            frame.image.dispose();
            return;
          }
        }
      } catch (_) {}
    }
    _ensureElementImageLoaded(savedPath);
    if (!mounted) return;
    context.read<AppState>().addRecentImagePath(savedPath);
    double w = 280.0;
    double h = 220.0;
    if (decoded != null && decoded.width > 0 && decoded.height > 0) {
      final double natW = decoded.width.toDouble();
      final double natH = decoded.height.toDouble();
      final double ratio = natW / natH;
      const double maxDim = 340.0;
      if (ratio >= 1.0) {
        w = maxDim;
        h = (maxDim / ratio).clamp(48.0, 520.0);
      } else {
        h = maxDim;
        w = (maxDim * ratio).clamp(48.0, 520.0);
      }
    }
    final center = _visibleCenterOnPage(page, _currentPageIndex);
    final imgEl = ImageElement(
      id: _uuid.v4(),
      x: (center.dx - w * 0.5).clamp(16.0, 5600.0),
      y: (center.dy - h * 0.5).clamp(16.0, 5600.0),
      width: w,
      height: h,
      rotation: 0.0,
      filePath: savedPath,
      zIndex: DateTime.now().millisecondsSinceEpoch,
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
    final deviceRecents =
        await HardwareService.instance.getDeviceRecentImages(limit: 9);
    if (!mounted) return;

    // Build unified list of up to 9 items (device MediaStore photos first, then local recents)
    final gridItems = <({String thumbPath, DeviceRecentImage? deviceItem, String? localPath})>[
      for (final d in deviceRecents)
        (thumbPath: d.thumbPath, deviceItem: d, localPath: null),
    ];
    for (final p in [...appState.recentImagePaths, ...appState.customStickers]) {
      if (gridItems.length >= 9) break;
      if (!gridItems.any((g) => g.localPath == p || g.thumbPath == p)) {
        gridItems.add((thumbPath: p, deviceItem: null, localPath: p));
      }
    }

    final selected = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Ảnh gần đây',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (gridItems.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 290),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: gridItems.length,
                    itemBuilder: (c, i) {
                      final item = gridItems[i];
                      final thumbFile = File(item.thumbPath);
                      return GestureDetector(
                        onTap: () => Navigator.pop(ctx, item),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                            color: Colors.black26,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: thumbFile.existsSync()
                                ? Image.file(thumbFile, fit: BoxFit.cover)
                                : const Icon(Icons.image_outlined),
                          ),
                        ),
                      );
                    },
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Chưa có ảnh gần đây. Chọn ảnh từ thiết bị bên dưới.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                ),
              const Divider(height: 20),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Tùy chọn khác',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Chụp ảnh'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Chọn từ Bộ sưu tập'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;

    if (selected is ({String thumbPath, DeviceRecentImage? deviceItem, String? localPath})) {
      if (selected.deviceItem != null) {
        final rootDir = await appState.storage.getRootDirectory();
        final imgDir = Directory('${rootDir.path}${Platform.pathSeparator}images');
        if (!await imgDir.exists()) {
          await imgDir.create(recursive: true);
        }
        final destPath =
            '${imgDir.path}${Platform.pathSeparator}${_uuid.v4()}.jpg';
        final copied = await HardwareService.instance.copyUriToFile(
          selected.deviceItem!.uri,
          destPath,
        );
        final finalPath = copied ??
            (selected.deviceItem!.filePath.isNotEmpty
                ? selected.deviceItem!.filePath
                : selected.deviceItem!.thumbPath);
        if (mounted && finalPath.isNotEmpty) {
          await _insertSavedImagePath(page, finalPath);
        }
      } else if (selected.localPath != null) {
        await _insertSavedImagePath(page, selected.localPath!);
      }
      return;
    }

    final source =
        selected == 'camera' ? ImageSource.camera : ImageSource.gallery;
    try {
      // Never downscale on import: keep full original resolution for crisp cropping!
      String? pickedPath;
      if (source == ImageSource.gallery) {
        pickedPath = await HardwareService.instance.pickImageFromSystemGallery();
      }
      if (pickedPath == null) {
        final picked = await _imagePicker.pickImage(source: source);
        pickedPath = picked?.path;
      }
      if (pickedPath == null || !mounted) return;

      final savedPath = await appState.storage.saveImportedFile(
        File(pickedPath),
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
              isInfiniteWhiteboard: false,
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
      case InsertMenuAction.newWhiteboard:
        await context.read<AppState>().addPage(
              notebook.id,
              templateType: PaperTemplateType.dotted,
              paperColor: currentPage.paperColor,
              isInfiniteWhiteboard: true,
              insertAfterIndex: currentIdx,
            );
        if (mounted) {
          setState(() => _whiteboardCenteredOnce = false);
          _jumpToPage(currentIdx + 1);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(milliseconds: 1200),
              content: Text('Đã thêm Bảng vô cực (6000 × 6000)'),
            ),
          );
        }
        break;
      case InsertMenuAction.stickyNote:
        await _addStickyNote(currentPage);
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
        await _handleImportDocxOrAttachment(notebook, currentPage);
        break;
    }
  }

  Future<void> _pickAndInsertAttachment(
    NotePage page, {
    List<String>? allowedExtensions,
    String emptyLabel = 'tệp đính kèm',
  }) async {
    try {
      String pickedName = 'file';
      String savedPath = '';
      int pickedSize = 0;

      final nativePick = await HardwareService.instance.pickDocumentFile(
        allowedExtensions: allowedExtensions ?? const <String>[],
      );
      if (nativePick.handled) {
        final f = nativePick.file;
        if (f == null || !mounted) return;
        pickedName = f.name;
        savedPath = f.path;
        pickedSize = f.size;
      } else {
        final res = await FilePicker.platform.pickFiles(
          type: allowedExtensions != null ? FileType.custom : FileType.any,
          allowedExtensions: allowedExtensions,
        );
        if (res == null || res.files.isEmpty || !mounted) return;
        final picked = res.files.first;
        pickedName = picked.name;
        savedPath = picked.path ?? '';
        pickedSize = picked.size;
      }

      if (savedPath.isNotEmpty && File(savedPath).existsSync()) {
        savedPath = await context.read<AppState>().storage.saveImportedFile(
              File(savedPath),
              subfolder: 'attachments',
            );
      }
      final ext = (pickedName.contains('.')
              ? pickedName.split('.').last
              : 'FILE')
          .toUpperCase();
      final pageSize = PaperMetrics.pageSize(isLandscape: page.isLandscape);
      final attachment = AttachmentElement(
        id: _uuid.v4(),
        x: (pageSize.width - 260) * 0.5,
        y: (pageSize.height - 64) * 0.35,
        width: 260.0,
        height: 64.0,
        fileName: pickedName,
        filePath: savedPath,
        fileExtension: ext,
        fileSizeBytes: pickedSize,
      );
      await _commitPage(
        page.copyWith(
          attachmentElements: [...page.attachmentElements, attachment],
        ),
        undoSnapshot: page,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã đính kèm $emptyLabel: $pickedName')),
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

  Future<void> _handleImportDocxOrAttachment(
    Notebook notebook,
    NotePage currentPage,
  ) async {
    try {
      String pickedName = 'file';
      String savedPath = '';
      int pickedSize = 0;

      final nativePick = await HardwareService.instance.pickDocumentFile(
        allowedExtensions: const ['doc', 'docx', 'ppt', 'pptx'],
      );
      if (nativePick.handled) {
        final f = nativePick.file;
        if (f == null || !mounted) return;
        pickedName = f.name;
        savedPath = f.path;
        pickedSize = f.size;
      } else {
        final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['doc', 'docx', 'ppt', 'pptx'],
        );
        if (res == null || res.files.isEmpty || !mounted) return;
        final picked = res.files.first;
        pickedName = picked.name;
        savedPath = picked.path ?? '';
        pickedSize = picked.size;
      }

      final ext = (pickedName.contains('.')
              ? pickedName.split('.').last
              : '')
          .toLowerCase();

      if (ext == 'docx' &&
          savedPath.isNotEmpty &&
          File(savedPath).existsSync()) {
        await _runImportWithProgress(
          title: 'Đang nhập tài liệu Word (.docx)',
          notebook: notebook,
          task: (onProgress) => _pdfImportService.importDocxFile(
            File(savedPath),
            startIndex: notebook.pages.length,
            onProgress: onProgress,
          ),
        );
        return;
      }

      // Graceful attachment fallback for legacy binary .doc / .ppt / .pptx
      if (savedPath.isNotEmpty && File(savedPath).existsSync()) {
        savedPath = await context.read<AppState>().storage.saveImportedFile(
              File(savedPath),
              subfolder: 'attachments',
            );
      }
      final pageSize =
          PaperMetrics.pageSize(isLandscape: currentPage.isLandscape);
      final attachment = AttachmentElement(
        id: _uuid.v4(),
        x: (pageSize.width - 260) * 0.5,
        y: (pageSize.height - 64) * 0.35,
        width: 260.0,
        height: 64.0,
        fileName: pickedName,
        filePath: savedPath,
        fileExtension: ext.toUpperCase(),
        fileSizeBytes: pickedSize,
      );
      await _commitPage(
        currentPage.copyWith(
          attachmentElements: [...currentPage.attachmentElements, attachment],
        ),
        undoSnapshot: currentPage,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi nhập tài liệu: $e')),
        );
      }
    }
  }

  Future<void> _runImportWithProgress({
    required String title,
    required Notebook notebook,
    required Future<PdfImportResult?> Function(PdfImportProgressCallback onProgress)
        task,
  }) async {
    final progressBar = PdfImportBottomProgressOverlay();
    try {
      final result = await task((current, total, stage) {
        if (!mounted) return;
        progressBar.show(context, title: title);
        progressBar.update(current, total, stage);
      });
      progressBar.hide();
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
      progressBar.hide();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi nhập tài liệu: $e')),
        );
      }
    } finally {
      progressBar.hide();
    }
  }

  Future<void> _handleImportPdf(Notebook notebook) async {
    await _runImportWithProgress(
      title: 'Đang nhập tệp PDF',
      notebook: notebook,
      task: (onProgress) => _pdfImportService.pickAndImportPdf(
        startIndex: notebook.pages.length,
        onProgress: onProgress,
      ),
    );
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
    final customDir = context.read<AppState>().pdfExportDirectory;
    final bool showProgressDialog = action == 'share' || action == 'save';
    final progressNotifier =
        ValueNotifier<({int current, int total, String stage})>((
      current: 0,
      total: math.max(1, notebook.pages.length),
      stage: 'Đang chuẩn bị xuất PDF...',
    ));
    bool dialogOpen = false;

    if (showProgressDialog && mounted) {
      dialogOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
          final bg = isDark ? EditorColors.obsidianSurface : Colors.white;
          final fg = isDark ? Colors.white : const Color(0xFF0F172A);
          final sub = isDark ? Colors.white70 : const Color(0xFF475569);
          return PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              contentPadding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              content: ValueListenableBuilder<
                  ({int current, int total, String stage})>(
                valueListenable: progressNotifier,
                builder: (_, state, __) {
                  final double ratio = state.total > 0
                      ? (state.current / state.total).clamp(0.0, 1.0)
                      : 0.0;
                  final int pct = (ratio * 100).round();
                  return SizedBox(
                    width: 310,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: EditorColors.activeBlue,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                action == 'share'
                                    ? 'Đang tạo & chia sẻ PDF'
                                    : 'Đang xuất tệp PDF',
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '$pct%',
                              style: const TextStyle(
                                color: EditorColors.activeBlue,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: state.current == 0 ? null : ratio,
                            minHeight: 7,
                            backgroundColor: isDark
                                ? Colors.white12
                                : const Color(0xFFE2E8F0),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              EditorColors.activeBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          state.stage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: sub, fontSize: 12.5),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    }

    void closeProgressDialog() {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    try {
      if (action == 'share') {
        await _pdfExportService.shareNotebookPdf(
          notebook,
          customDirectory: customDir,
          onProgress: (current, total, stage) {
            progressNotifier.value = (
              current: current,
              total: total,
              stage: stage,
            );
          },
        );
        closeProgressDialog();
      } else if (action == 'print') {
        await _pdfExportService.printNotebookPdf(notebook);
      } else if (action == 'save') {
        final file = await _pdfExportService.exportNotebookToFile(
          notebook,
          customDirectory: customDir,
          onProgress: (current, total, stage) {
            progressNotifier.value = (
              current: current,
              total: total,
              stage: stage,
            );
          },
        );
        closeProgressDialog();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã lưu PDF tại: ${file.path}')),
          );
        }
      }
    } catch (e) {
      closeProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất PDF: $e')),
        );
      }
    } finally {
      closeProgressDialog();
      progressNotifier.dispose();
      if (mounted) setState(() => _isBusyPdf = false);
    }
  }

  void _updatePullToAddProgress(Notebook notebook, Size viewportSize) {
    if (notebook.pages.isEmpty || _isAddingPullPage) return;
    _ensureVerticalLayoutCache(notebook);
    final double totalContentHeight = _cachedTotalHeight;
    final m = _transformController.value;
    final scale = m.getMaxScaleOnAxis().clamp(0.35, 4.0);
    final ty = m.getTranslation().y;

    // Keep current page index in sync using O(log N) binary search
    final double centerContentY = (-ty + viewportSize.height * 0.45) / scale;
    int visibleIdx = 0;
    if (_cachedPageTops.length > 1) {
      int lo = 0;
      int hi = _cachedPageTops.length - 1;
      while (lo < hi) {
        final mid = (lo + hi + 1) >> 1;
        if (_cachedPageTops[mid] < centerContentY) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      visibleIdx = lo;
    }
    if (visibleIdx != _currentPageIndex) {
      _currentPageIndex = visibleIdx;
      if ((visibleIdx - _renderedWindowCenter).abs() >= 3) {
        setState(() => _renderedWindowCenter = visibleIdx);
      }
      _prefetchNearbyPdfPages(notebook);
    }

    final contentBottom = ty + totalContentHeight * scale;
    final thresholdY = viewportSize.height - 50.0;
    if (contentBottom < thresholdY) {
      final overscroll = thresholdY - contentBottom;
      _pullAddProgressNotifier.value = (overscroll / 75.0).clamp(0.0, 1.0);
    } else if (_pullAddProgressNotifier.value != 0.0) {
      _pullAddProgressNotifier.value = 0.0;
    }
  }

  void _finishPullToAddIfReady(Notebook notebook) {
    final progress = _pullAddProgressNotifier.value;
    _pullAddProgressNotifier.value = 0.0;
    if (progress >= 0.85 && notebook.pages.isNotEmpty && !_isAddingPullPage) {
      _handlePullAddPage(notebook, notebook.pages.last);
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
      }
    } finally {
      _isAddingPullPage = false;
    }
  }

  // ===========================================================================
  // AUDIO NOTE RECORDING, SYNCED STROKE REPLAY & IN-APP APK UPDATER
  // ===========================================================================

  Future<void> _handleMicToolbarTap(NotePage page) async {
    if (_isRecordingAudio) {
      await _toggleAudioRecording(page);
      return;
    }
    if (page.audioRecordings.isNotEmpty && !_isAudioBarVisible) {
      setState(() => _isAudioBarVisible = true);
      return;
    }
    await _toggleAudioRecording(page);
  }

  Future<void> _toggleAudioRecording(NotePage page) async {
    if (_isRecordingAudio) {
      _recordingElapsedTimer?.cancel();
      _recordingElapsedTimer = null;
      final durationMs = await HardwareService.instance.stopAudioRecording();
      final recId = _activeRecordingId;
      final recPath = _activeRecordingPath;
      final fallbackDuration =
          DateTime.now().millisecondsSinceEpoch - _recordingStartMs;
      _recordingElapsedMsNotifier.value = 0;
      setState(() {
        _isRecordingAudio = false;
        _activeRecordingId = null;
        _activeRecordingPath = null;
      });
      if (recId != null && recPath != null) {
        final rec = AudioRecording(
          id: recId,
          filePath: recPath,
          durationMs:
              durationMs > 0 ? durationMs : math.max(1000, fallbackDuration),
          createdAt: DateTime.now(),
        );
        _selectedAudioId = rec.id;
        _isAudioBarVisible = true;
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

    if (_isAudioPlaying) {
      _audioPollTimer?.cancel();
      await HardwareService.instance.stopAudio();
      _playingAudioId = null;
      _isAudioPlaying = false;
      _audioPositionMsNotifier.value = 0;
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
    _recordingElapsedTimer?.cancel();
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    _recordingElapsedMsNotifier.value = 0;
    setState(() {
      _isRecordingAudio = true;
      _activeRecordingId = recId;
      _activeRecordingPath = path;
      _recordingStartMs = startedAtMs;
    });
    _recordingElapsedTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || !_isRecordingAudio) return;
      _recordingElapsedMsNotifier.value =
          DateTime.now().millisecondsSinceEpoch - _recordingStartMs;
    });
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

    final bool switchingTrack =
        _playingAudioId != null && _playingAudioId != rec.id;
    if (switchingTrack) {
      _audioPollTimer?.cancel();
      await HardwareService.instance.stopAudio();
      _audioPositionMsNotifier.value = 0;
    }

    final ok = await HardwareService.instance.playAudio(rec.filePath);
    if (!mounted) return;
    if (ok) {
      await HardwareService.instance.setAudioSpeed(_audioSpeed);
      if (!switchingTrack &&
          _playingAudioId == rec.id &&
          _audioPositionMsNotifier.value > 0) {
        await HardwareService.instance.seekAudio(_audioPositionMsNotifier.value);
      }
    }
    if (switchingTrack) _audioPositionMsNotifier.value = 0;
    setState(() {
      _selectedAudioId = rec.id;
      _playingAudioId = rec.id;
      _isAudioPlaying = true;
      _repaintVersion++;
    });
    _audioPollTimer?.cancel();
    _audioPollTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (!mounted || !_isAudioPlaying) return;
      final pos = await HardwareService.instance.getAudioPositionMs();
      if (!mounted) return;
      if (pos >= rec.durationMs && rec.durationMs > 0) {
        _audioPollTimer?.cancel();
        _audioPositionMsNotifier.value = rec.durationMs;
        setState(() {
          _isAudioPlaying = false;
          _repaintVersion++;
        });
      } else {
        _audioPositionMsNotifier.value = pos;
      }
    });
  }

  Future<void> _seekAudio(AudioRecording rec, int ms) async {
    _audioPositionMsNotifier.value = ms;
    if (_selectedAudioId != rec.id || _playingAudioId != rec.id) {
      setState(() {
        _selectedAudioId = rec.id;
        _playingAudioId = rec.id;
        _repaintVersion++;
      });
    }
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
      _audioPositionMsNotifier.value = 0;
    }
    final updated =
        page.audioRecordings.where((r) => r.id != rec.id).toList();
    if (_selectedAudioId == rec.id) {
      _selectedAudioId = updated.isNotEmpty ? updated.last.id : null;
    }
    if (updated.isEmpty) {
      _isAudioBarVisible = false;
    }
    await _commitPage(
      page.copyWith(audioRecordings: updated),
      undoSnapshot: page,
    );
  }

  Future<void> _showAudioRecordingsDialog(NotePage page) async {
    String fmtDuration(int ms) {
      final totalSec = (ms / 1000).floor().clamp(0, 35999);
      final m = (totalSec ~/ 60).toString().padLeft(2, '0');
      final s = (totalSec % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    String fmtDate(DateTime dt) {
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$d/$m/${dt.year} $hh:$mm';
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final livePage = _getCurrentPage(_getNotebook(context, listen: false)) ??
              page;
          final recs = livePage.audioRecordings;
          final String? currentId =
              _selectedAudioId ?? (recs.isNotEmpty ? recs.last.id : null);

          return Dialog(
            backgroundColor: EditorColors.obsidianSurface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Ghi âm',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (!_isRecordingAudio)
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _toggleAudioRecording(livePage);
                            },
                            icon: const Icon(Icons.mic_rounded, size: 17),
                            label: const Text('Ghi mới'),
                          ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 12),
                    if (recs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Text(
                          'Chưa có bản ghi âm nào trên trang này.',
                          style: TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: recs.length,
                          separatorBuilder: (_, __) => const Divider(
                            color: Colors.white10,
                            height: 1,
                          ),
                          itemBuilder: (_, idx) {
                            final r = recs[idx];
                            final bool isSelected = r.id == currentId;
                            final bool isPlayingThis =
                                _isAudioPlaying && _playingAudioId == r.id;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              tileColor: isSelected
                                  ? EditorColors.activeBlue.withAlpha(32)
                                  : Colors.transparent,
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: isSelected
                                    ? EditorColors.activeBlue
                                    : Colors.white12,
                                child: Icon(
                                  isPlayingThis
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                'Ghi âm (${idx + 1})',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                '${fmtDate(r.createdAt)}  •  ${fmtDuration(r.durationMs)}',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: 'Xóa bản ghi âm này',
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Color(0xFFEF4444),
                                  size: 19,
                                ),
                                onPressed: () async {
                                  await _deleteAudioRecording(livePage, r);
                                  if (ctx.mounted) setModalState(() {});
                                },
                              ),
                              onTap: () async {
                                setModalState(() => _selectedAudioId = r.id);
                                await _togglePlayAudio(r);
                                if (ctx.mounted) setModalState(() {});
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addStickyNote(NotePage page) async {
    final center = _visibleCenterOnPage(page, _currentPageIndex);
    final stagger = (page.stickyNotes.length % 5) * 16.0;
    final note = StickyNoteElement(
      id: _uuid.v4(),
      x: (center.dx - 105 + stagger).clamp(16.0, 5700.0),
      y: (center.dy - 95 + stagger).clamp(16.0, 5700.0),
      width: 210.0,
      height: 190.0,
      text: '',
      colorValue: 0xFFFEF08A,
      isCollapsed: false,
      updatedAt: DateTime.now(),
      zIndex: DateTime.now().millisecondsSinceEpoch,
    );
    await _commitPage(
      page.copyWith(stickyNotes: [...page.stickyNotes, note]),
      undoSnapshot: page,
    );
  }

  Future<void> _handlePickPdfExportDir() async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Chọn thư mục xuất PDF mặc định',
      );
      if (dir == null || dir.isEmpty || !mounted) return;
      context.read<AppState>().setPdfExportDirectory(dir);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã đặt thư mục xuất PDF: $dir')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể chọn thư mục: $e')),
        );
      }
    }
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
                cacheExtent: 360,
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
                                    child: () {
                                      final thumbSize = PaperMetrics.pageSize(
                                        isLandscape: p.isLandscape,
                                      );
                                      return RepaintBoundary(
                                        child: FittedBox(
                                          fit: BoxFit.contain,
                                          child: SizedBox(
                                            width: thumbSize.width,
                                            height: thumbSize.height,
                                            child: IgnorePointer(
                                              child: Stack(
                                                children: [
                                                  Positioned.fill(
                                                    child: (p.pdfBackgroundPath !=
                                                                null &&
                                                            _pdfImageCache[p
                                                                    .pdfBackgroundPath!] ==
                                                                null)
                                                        ? ColoredBox(
                                                            color: Colors.white,
                                                            child: Image.file(
                                                              File(p
                                                                  .pdfBackgroundPath!),
                                                              fit: BoxFit.contain,
                                                              cacheWidth:
                                                                  notebook.pages
                                                                              .length <=
                                                                          80
                                                                      ? 720
                                                                      : 480,
                                                              filterQuality:
                                                                  FilterQuality
                                                                      .medium,
                                                              gaplessPlayback:
                                                                  true,
                                                              errorBuilder: (
                                                                _,
                                                                __,
                                                                ___,
                                                              ) =>
                                                                  const SizedBox
                                                                      .shrink(),
                                                            ),
                                                          )
                                                        : CustomPaint(
                                                            size: thumbSize,
                                                            painter:
                                                                CanvasPainter(
                                                              page: p,
                                                              pdfBackgroundImage:
                                                                  p.pdfBackgroundPath !=
                                                                          null
                                                                      ? _pdfImageCache[
                                                                          p.pdfBackgroundPath!]
                                                                      : null,
                                                              elementImageCache:
                                                                  _elementImageCache,
                                                              repaintVersion:
                                                                  _repaintVersion,
                                                            ),
                                                          ),
                                                  ),
                                                  for (final txt
                                                      in p.textElements)
                                                    Positioned(
                                                      left: txt.x,
                                                      top: txt.y,
                                                      width: txt.width,
                                                      child: Text(
                                                        txt.text,
                                                        style: TextStyle(
                                                          color: Color(
                                                              txt.colorValue),
                                                          fontSize:
                                                              txt.fontSize,
                                                        ),
                                                      ),
                                                    ),
                                                  for (final st in p.stickyNotes)
                                                    Positioned(
                                                      left: st.x,
                                                      top: st.y,
                                                      width: st.isCollapsed
                                                          ? math.min(
                                                              st.width, 210.0)
                                                          : st.width,
                                                      height: st.isCollapsed
                                                          ? 40.0
                                                          : st.height,
                                                      child: Container(
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Color(
                                                              st.colorValue),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(10),
                                                          border: Border.all(
                                                              color: Colors
                                                                  .black26),
                                                        ),
                                                        child: st.isCollapsed
                                                            ? null
                                                            : CustomPaint(
                                                                painter:
                                                                    _StickyCanvasPainter(
                                                                  strokes: st
                                                                      .strokes,
                                                                  activeStrokeNotifier:
                                                                      _activeStickyStrokeNotifier,
                                                                  noteId: st.id,
                                                                  getActiveNoteId:
                                                                      () =>
                                                                          null,
                                                                ),
                                                              ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }(),
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
    // Unified viewport pan/zoom gating (v3.5.0):
    // - When _stylusPanMode is ON: M-Pencil 3 ONLY scrolls/pans and never draws.
    // - When _stylusPanMode is OFF: M-Pencil 3 NEVER scrolls/pans (strictly draws/uses active tool, including Study Tape!).
    // - When Palm Lock is ON: 1 finger scrolls, 2 fingers zoom/pan.
    // - When Palm Lock is OFF: 1 finger writes, 2 fingers immediately cancel stroke & zoom/pan.
    final bool allowZoomPan = !_isOverlayDragging &&
        (_stylusPanMode
            ? (_isStylusDown || _activeTouchPointers.isNotEmpty)
            : (!_isStylusDown &&
                (_activeTouchPointers.length >= 2 ||
                    appState.readOnlyMode ||
                    (appState.palmRejectionEnabled &&
                        !_isDrawingPointerDown &&
                        _activeTouchPointers.isNotEmpty) ||
                    (!_isDrawingPointerDown &&
                        _activeTool == EditorTool.panZoom))));

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
            stickyNotes: const [],
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
        onPickPdfExportDir: _handlePickPdfExportDir,
        onToggleLockNotebook: () async {
          await appState.setNotebookLock(
            notebook.id,
            isLocked: !notebook.isLocked,
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
        audioRecordingsCount: currentPage.audioRecordings.length,
        onOpenAudioRecordings: () {
          if (currentPage.audioRecordings.isNotEmpty) {
            setState(() => _isAudioBarVisible = true);
            _showAudioRecordingsDialog(currentPage);
          } else {
            _toggleAudioRecording(currentPage);
          }
        },
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
            stylusPanMode: _stylusPanMode,
            isRecordingAudio: _isRecordingAudio,
            onUndo: () => _undo(currentPage),
            onRedo: () => _redo(currentPage),
            onSelectTool: (tool) {
              _commitActiveTextEdit();
              setState(() {
                // Item 3: Tapping an active toggleable mode (Study Tape / Laser / Shape / Lasso / Text) a 2nd time cleanly turns it OFF!
                final isToggleOff = _activeTool == tool &&
                    (tool == EditorTool.studyTape ||
                        tool == EditorTool.laserPointer ||
                        tool == EditorTool.shape ||
                        tool == EditorTool.lasso ||
                        tool == EditorTool.textBox);
                _activeTool = isToggleOff ? _lastPenTool : tool;
                if (_activeTool.isPenFamily) _lastPenTool = _activeTool;
                if (_activeTool != EditorTool.lasso) _lassoController.clear();
                if (_activeTool != EditorTool.image) _selectedImageId = null;
              });
              if (_activeTool.isPenFamily) _persistPenPrefs();
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
              onSelectPen: (p) {
                setState(() {
                  _lastPenTool = p;
                  _activeTool = p;
                });
                _persistPenPrefs();
              },
              onSelectColor: (c) {
                setState(() {
                  if (_activeTool == EditorTool.highlighter) {
                    _highlighterColor = c;
                  } else {
                    _penColor = c;
                  }
                });
                _persistPenPrefs();
              },
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
                onSelectColor: (c) {
                  setState(() {
                    if (_activeTool == EditorTool.highlighter) {
                      _highlighterColor = c;
                    } else {
                      _penColor = c;
                    }
                  });
                  _persistPenPrefs();
                },
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
                    _autoNeatenEnabled = smoothingStrength > 0.01;
                  }
                });
                _persistPenPrefs();
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
              eraserRadius: _eraserRadius,
              onEraserRadiusChanged: (r) {
                setState(() => _eraserRadius = r);
                _persistPenPrefs();
              },
              onSelectMode: (m) => setState(() => _eraserMode = m),
              onClearCurrentPage: () => _commitPage(
                currentPage.copyWith(strokes: const []),
                undoSnapshot: currentPage,
              ),
            ),
            onInsertImage: () => _handleImageToolButtonTap(currentPage),
            onOpenStickerPicker: () => _openQuickStencilPicker(currentPage),
            onAddStickyNote: () => _addStickyNote(currentPage),
            onToggleZoomWindow: () =>
                setState(() => _zoomWindowEnabled = !_zoomWindowEnabled),
            onToggleRuler: () => setState(() {
              _rulerVisible = !_rulerVisible;
              if (_rulerVisible &&
                  _editorViewportSize.width > 0 &&
                  _editorViewportSize.height > 0) {
                _rulerState.center = Offset(
                  _editorViewportSize.width * 0.5,
                  _editorViewportSize.height * 0.5,
                );
              }
            }),
            onTogglePalmRejection: () {
              appState.togglePalmRejection();
              _palmFilter.stylusOnlyMode = appState.palmRejectionEnabled;
            },
            onToggleStylusPan: () {
              setState(() => _stylusPanMode = !_stylusPanMode);
            },
            onToggleAudioRecording: () => _handleMicToolbarTap(currentPage),
            onSelectColor: (c) {
              setState(() {
                if (_activeTool == EditorTool.highlighter) {
                  _highlighterColor = c;
                } else {
                  _penColor = c;
                }
              });
              _persistPenPrefs();
            },
            onOpenColorPalette: () => showColorPaletteSheet(
              context: context,
              isHighlighter: _activeTool == EditorTool.highlighter,
              currentColor: _effectiveColor,
              onSelectColor: (c) {
                setState(() {
                  if (_activeTool == EditorTool.highlighter) {
                    _highlighterColor = c;
                  } else {
                    _penColor = c;
                  }
                });
                _persistPenPrefs();
              },
            ),
          ),

          // Live Audio Recording Bar OR On-Demand Multi-Recording Audio Replay Bar
          if (_isRecordingAudio)
            ValueListenableBuilder<int>(
              valueListenable: _recordingElapsedMsNotifier,
              builder: (_, elapsedMs, __) => AudioLiveRecordingBar(
                elapsedMs: elapsedMs,
                totalRecordings: currentPage.audioRecordings.length,
                onStop: () => _toggleAudioRecording(currentPage),
                onShowList: currentPage.audioRecordings.isNotEmpty
                    ? () => _showAudioRecordingsDialog(currentPage)
                    : null,
              ),
            )
          else if ((_isAudioBarVisible || _isAudioPlaying) &&
              currentPage.audioRecordings.isNotEmpty)
            Builder(
              builder: (_) {
                final recs = currentPage.audioRecordings;
                final idx = recs.indexWhere((r) => r.id == _selectedAudioId);
                final activeIdx = idx >= 0 ? idx : recs.length - 1;
                final activeRec = recs[activeIdx];
                return ValueListenableBuilder<int>(
                  valueListenable: _audioPositionMsNotifier,
                  builder: (_, posMs, __) => AudioReplayBar(
                    recording: activeRec,
                    recordingIndex: activeIdx + 1,
                    totalRecordings: recs.length,
                    isPlaying:
                        _isAudioPlaying && _playingAudioId == activeRec.id,
                    positionMs:
                        _playingAudioId == activeRec.id ? posMs : 0,
                    speed: _audioSpeed,
                    onTogglePlay: () => _togglePlayAudio(activeRec),
                    onSeek: (ms) => _seekAudio(activeRec, ms),
                    onCycleSpeed: _cycleAudioSpeed,
                    onShowList: () => _showAudioRecordingsDialog(currentPage),
                    onStartNewRecording: () =>
                        _toggleAudioRecording(currentPage),
                    onDelete: () =>
                        _deleteAudioRecording(currentPage, activeRec),
                    onClose: () async {
                      if (_isAudioPlaying) {
                        _audioPollTimer?.cancel();
                        await HardwareService.instance.stopAudio();
                      }
                      _audioPositionMsNotifier.value = 0;
                      if (mounted) {
                        setState(() {
                          _isAudioBarVisible = false;
                          _isAudioPlaying = false;
                          _playingAudioId = null;
                          _repaintVersion++;
                        });
                      }
                    },
                  ),
                );
              },
            ),

          // Main Canvas Area (Infinite Whiteboard, Unified Vertical InteractiveViewer, or Horizontal Flip)
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, viewportConstraints) {
                final vpSize = Size(
                  viewportConstraints.maxWidth,
                  viewportConstraints.maxHeight,
                );
                _editorViewportSize = vpSize;
                if (!_verticalCenteredOnce &&
                    !currentPage.isInfiniteWhiteboard &&
                    !notebook.isWhiteboard &&
                    appState.verticalContinuousScroll &&
                    vpSize.width > 0) {
                  _verticalCenteredOnce = true;
                  final pageW =
                      PaperMetrics.pageSize(isLandscape: currentPage.isLandscape)
                          .width +
                      48.0;
                  final initScale = (vpSize.width / pageW).clamp(0.55, 1.0);
                  final tx = (vpSize.width - pageW * initScale) * 0.5;
                  _transformController.value = Matrix4.identity()
                    ..translate(tx, 0.0)
                    ..scale(initScale, initScale);
                }

                final bool stylusBlocksViewport =
                    !_stylusPanMode && (_isStylusDown || _isStylusHovering);

                final bool allowZoomPan = !_isOverlayDragging &&
                    (_stylusPanMode ||
                        (!stylusBlocksViewport &&
                            (_activeTouchPointers.length >= 2 ||
                                appState.readOnlyMode ||
                                (appState.palmRejectionEnabled &&
                                    !_isDrawingPointerDown) ||
                                (!_isDrawingPointerDown &&
                                    _activeTool == EditorTool.panZoom))));

                final double scrollMult =
                    appState.scrollSpeedMultiplier.clamp(1.0, 25.0);
                final bool useFastVerticalPan = scrollMult > 1.01 &&
                    !currentPage.isInfiniteWhiteboard &&
                    !notebook.isWhiteboard &&
                    appState.verticalContinuousScroll;

                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerHover: (e) {
                    if ((e.kind == PointerDeviceKind.stylus ||
                            e.kind == PointerDeviceKind.invertedStylus) &&
                        !_stylusPanMode) {
                      _stylusHoverTimer?.cancel();
                      _stylusHoverTimer = Timer(
                        const Duration(milliseconds: 350),
                        () {
                          if (mounted && _isStylusHovering) {
                            setState(() => _isStylusHovering = false);
                          }
                        },
                      );
                      if (!_isStylusHovering) {
                        setState(() => _isStylusHovering = true);
                      }
                    }
                  },
                  onPointerDown: (e) {
                    final bool isStylus = e.kind == PointerDeviceKind.stylus ||
                        e.kind == PointerDeviceKind.invertedStylus;
                    if (isStylus) {
                      if (!_stylusPanMode) {
                        _lockedMatrixDuringStylus =
                            _transformController.value.clone();
                        _lockedWhiteboardMatrixDuringStylus =
                            _whiteboardTransformController.value.clone();
                      }
                      if (!_isStylusDown) {
                        setState(() => _isStylusDown = true);
                        _syncStylusDrawingState();
                      }
                      return;
                    }
                    if (e.kind == PointerDeviceKind.touch) {
                      final int prevLen = _activeTouchPointers.length;
                      _activeTouchPointers.add(e.pointer);
                      if (_activeTouchPointers.length >= 2 && !_isStylusDown) {
                        _stylusHoverTimer?.cancel();
                        _isStylusHovering = false;
                        _cancelActiveGesture();
                        if (prevLen < 2) {
                          setState(() {});
                        }
                      }
                      if (_tapTouchStarts.isEmpty) {
                        _tapTouchStartTime = DateTime.now();
                        _tapMaxTouchCount = 0;
                        _tapMovedTooFar = false;
                      }
                      _tapTouchStarts[e.pointer] = e.position;
                      _tapMaxTouchCount =
                          math.max(_tapMaxTouchCount, _tapTouchStarts.length);
                    }
                  },
                  onPointerMove: (e) {
                    if (e.kind == PointerDeviceKind.touch &&
                        !_tapMovedTooFar) {
                      final start = _tapTouchStarts[e.pointer];
                      if (start != null && (e.position - start).distance > 18.0) {
                        _tapMovedTooFar = true;
                      }
                    }

                    final bool isTouchPan = e.kind == PointerDeviceKind.touch &&
                        _activeTouchPointers.length == 1 &&
                        _activeTouchPointers.contains(e.pointer);
                    final bool isStylusPan = _stylusPanMode &&
                        _isStylusDown &&
                        e.down &&
                        (e.kind == PointerDeviceKind.stylus ||
                            e.kind == PointerDeviceKind.invertedStylus);
                    if (useFastVerticalPan &&
                        allowZoomPan &&
                        !_isOverlayDragging &&
                        _overlayTouchPointers.isEmpty &&
                        !stylusBlocksViewport &&
                        !_isDrawingPointerDown &&
                        _croppingImageId == null &&
                        (isTouchPan || isStylusPan)) {
                      final m = _transformController.value;
                      final double scale =
                          m.getMaxScaleOnAxis().clamp(0.35, 4.0);
                      final double curTx = m.getTranslation().x;
                      final double curTy = m.getTranslation().y;
                      final double contentH =
                          _totalVerticalContentHeight(notebook);
                      final double scaledH = contentH * scale;
                      final double maxPageW = _maxVerticalPageWidth(notebook);
                      final double scaledW = (maxPageW + 48.0) * scale;

                      final double dx = (appState.freePaperMovement ||
                              scaledW > vpSize.width)
                          ? e.delta.dx
                          : 0.0;
                      final double dy = e.delta.dy * scrollMult;

                      final double nextTx = appState.freePaperMovement
                          ? (curTx + dx)
                              .clamp(
                                math.min(0.0, vpSize.width - scaledW) - 800.0,
                                800.0,
                              )
                              .toDouble()
                          : (scaledW <= vpSize.width
                              ? (vpSize.width - scaledW) * 0.5
                              : (curTx + dx)
                                  .clamp(vpSize.width - scaledW, 0.0)
                                  .toDouble());

                      final double minTy = appState.freePaperMovement
                          ? math.min(0.0, vpSize.height - scaledH) - 800.0
                          : math.min(0.0, vpSize.height - scaledH) - 120.0;
                      final double maxTy =
                          appState.freePaperMovement ? 800.0 : 120.0;
                      final double nextTy =
                          (curTy + dy).clamp(minTy, maxTy).toDouble();

                      _transformController.value = m.clone()
                        ..setTranslationRaw(nextTx, nextTy, 0.0);
                      _updatePullToAddProgress(notebook, vpSize);
                    }
                  },
                  onPointerUp: (e) {
                    if (e.kind == PointerDeviceKind.stylus ||
                        e.kind == PointerDeviceKind.invertedStylus) {
                      _overlayTouchPointers.remove(e.pointer);
                      _lockedMatrixDuringStylus = null;
                      _lockedWhiteboardMatrixDuringStylus = null;
                      if (_stylusPanMode && useFastVerticalPan) {
                        _finishPullToAddIfReady(notebook);
                      }
                      if (_isStylusDown || _isDrawingPointerDown) {
                        setState(() {
                          _isStylusDown = false;
                          _isDrawingPointerDown = false;
                        });
                        _syncStylusDrawingState();
                      }
                      return;
                    }
                    if (e.kind != PointerDeviceKind.touch) return;
                    _activeTouchPointers.remove(e.pointer);
                    _overlayTouchPointers.remove(e.pointer);
                    _pointerDownPositions.remove(e.pointer);
                    if (useFastVerticalPan && _activeTouchPointers.isEmpty) {
                      _finishPullToAddIfReady(notebook);
                    }
                    if (_activeTouchPointers.isEmpty &&
                        !_isStylusDown &&
                        _isDrawingPointerDown) {
                      setState(() => _isDrawingPointerDown = false);
                      _syncStylusDrawingState();
                    }
                    _tapTouchStarts.remove(e.pointer);
                    if (_tapTouchStarts.isEmpty && _tapTouchStartTime != null) {
                      final elapsed = DateTime.now()
                          .difference(_tapTouchStartTime!)
                          .inMilliseconds;
                      final maxFingers = _tapMaxTouchCount;
                      final moved = _tapMovedTooFar;
                      _tapTouchStartTime = null;
                      _tapMaxTouchCount = 0;
                      _tapMovedTooFar = false;
                      if (appState.quickGesturesEnabled &&
                          !moved &&
                          elapsed < 350 &&
                          maxFingers >= 2) {
                        if (maxFingers == 2) {
                          _undo(currentPage);
                        } else {
                          _redo(currentPage);
                        }
                      }
                    }
                  },
                  onPointerCancel: (e) {
                    if (e.kind == PointerDeviceKind.stylus ||
                        e.kind == PointerDeviceKind.invertedStylus) {
                      _overlayTouchPointers.remove(e.pointer);
                      _lockedMatrixDuringStylus = null;
                      _lockedWhiteboardMatrixDuringStylus = null;
                      if (_isStylusDown || _isDrawingPointerDown) {
                        setState(() {
                          _isStylusDown = false;
                          _isDrawingPointerDown = false;
                        });
                        _syncStylusDrawingState();
                      }
                      return;
                    }
                    if (e.kind != PointerDeviceKind.touch) return;
                    _activeTouchPointers.remove(e.pointer);
                    _overlayTouchPointers.remove(e.pointer);
                    _pointerDownPositions.remove(e.pointer);
                    if (useFastVerticalPan && _activeTouchPointers.isEmpty) {
                      _pullAddProgressNotifier.value = 0.0;
                    }
                    if (_activeTouchPointers.isEmpty &&
                        !_isStylusDown &&
                        _isDrawingPointerDown) {
                      setState(() => _isDrawingPointerDown = false);
                      _syncStylusDrawingState();
                    }
                    _tapTouchStarts.remove(e.pointer);
                    if (_tapTouchStarts.isEmpty) {
                      _tapTouchStartTime = null;
                      _tapMaxTouchCount = 0;
                      _tapMovedTooFar = false;
                    }
                  },
                  child: Stack(
                    key: _viewportStackKey,
                    children: [
                    if (currentPage.isInfiniteWhiteboard ||
                        notebook.isWhiteboard)
                      _buildInfiniteWhiteboardView(
                        notebook,
                        currentPage,
                        currentIdx,
                        appState,
                      )
                    else if (appState.verticalContinuousScroll)
                      InteractiveViewer(
                        transformationController: _transformController,
                        constrained: false,
                        minScale: 0.35,
                        maxScale: 4.0,
                        panAxis: appState.freePaperMovement
                            ? PanAxis.free
                            : PanAxis.aligned,
                        boundaryMargin: appState.freePaperMovement
                            ? const EdgeInsets.all(800)
                            : const EdgeInsets.symmetric(
                                horizontal: 360,
                                vertical: 120,
                              ),
                        panEnabled: allowZoomPan &&
                            (!useFastVerticalPan ||
                                _activeTouchPointers.length >= 2),
                        scaleEnabled:
                            !_isOverlayDragging && !stylusBlocksViewport,
                        onInteractionUpdate: (_) {
                          if (!_stylusPanMode &&
                              _isStylusDown &&
                              _lockedMatrixDuringStylus != null) {
                            _transformController.value =
                                _lockedMatrixDuringStylus!.clone();
                            return;
                          }
                          _updatePullToAddProgress(notebook, vpSize);
                        },
                        onInteractionEnd: (_) =>
                            _finishPullToAddIfReady(notebook),
                        child: _buildVerticalContinuousPages(notebook),
                      )
                    else
                      InteractiveViewer(
                        transformationController: _transformController,
                        minScale: 0.35,
                        maxScale: 4.0,
                        boundaryMargin: const EdgeInsets.all(800),
                        panEnabled: allowZoomPan,
                        scaleEnabled:
                            !_isOverlayDragging && !stylusBlocksViewport,
                        onInteractionUpdate: (_) {
                          if (!_stylusPanMode &&
                              _isStylusDown &&
                              _lockedMatrixDuringStylus != null) {
                            _transformController.value =
                                _lockedMatrixDuringStylus!.clone();
                          }
                        },
                        child: _buildHorizontalFlipPages(notebook),
                      ),

                    // Pull-down-to-add-new-page animated spring pill (vertical continuous mode)
                    if (appState.verticalContinuousScroll &&
                        !currentPage.isInfiniteWhiteboard &&
                        !notebook.isWhiteboard)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 18,
                        child: IgnorePointer(
                          child: ValueListenableBuilder<double>(
                            valueListenable: _pullAddProgressNotifier,
                            builder: (_, progress, __) {
                              if (progress <= 0.05) {
                                return const SizedBox.shrink();
                              }
                              final bool ready = progress >= 0.85;
                              return Padding(
                                padding: EdgeInsets.only(bottom: progress * 10.0),
                                child: Center(
                                  child: AnimatedScale(
                                    scale: ready ? 1.05 : 0.94 + progress * 0.08,
                                    duration: const Duration(milliseconds: 90),
                                    child: Material(
                                      elevation: 6,
                                      borderRadius: BorderRadius.circular(22),
                                      color: ready
                                          ? EditorColors.activeBlue
                                          : EditorColors.obsidianSurface
                                              .withAlpha(235),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              ready
                                                  ? Icons.add_circle_rounded
                                                  : Icons.arrow_downward_rounded,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              ready
                                                  ? 'Thả tay để thêm trang mới'
                                                  : 'Kéo mạnh để thêm trang mới',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                    // Single Viewport-Centered Interactive Ruler (never duplicates on new pages!)
                    if (_rulerVisible)
                      InteractiveRulerOverlay(
                        ruler: _rulerState,
                        onChanged: () => setState(() {}),
                        onClose: () => setState(() => _rulerVisible = false),
                        onDragStart: () =>
                            setState(() => _isOverlayDragging = true),
                        onDragEnd: () =>
                            setState(() => _isOverlayDragging = false),
                      ),

                    // Floating Study Tape close pill
                    if (_activeTool == EditorTool.studyTape)
                      Positioned(
                        top: 10,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Material(
                            elevation: 6,
                            borderRadius: BorderRadius.circular(20),
                            color: EditorColors.obsidianSurface.withAlpha(235),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.visibility_off_outlined,
                                    size: 15,
                                    color: EditorColors.activeBlue,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Băng che học thuộc (Chạm băng để ẩn/hiện)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => setState(
                                      () => _activeTool = _lastPenTool,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 17,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Huawei-Notes-style Floating Laser Control Bar (Mode + 6 Neon Colors + Close)
                    if (_activeTool == EditorTool.laserPointer)
                      Positioned(
                        top: 10,
                        left: 12,
                        right: 12,
                        child: Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Material(
                              elevation: 8,
                              borderRadius: BorderRadius.circular(24),
                              color:
                                  EditorColors.obsidianSurface.withAlpha(242),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(28),
                                  ),
                                ),
                                child: AnimatedBuilder(
                                  animation: _laserController,
                                  builder: (_, __) {
                                    final mode = _laserController.mode;
                                    final curColor = _laserController.color;
                                    Widget modeChip({
                                      required LaserPointerMode targetMode,
                                      required IconData icon,
                                      required String label,
                                    }) {
                                      final active = mode == targetMode;
                                      return GestureDetector(
                                        onTap: () => _laserController
                                            .setMode(targetMode),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: active
                                                ? EditorColors.activeBlue
                                                    .withAlpha(65)
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                              color: active
                                                  ? EditorColors.activeBlue
                                                  : Colors.transparent,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                icon,
                                                size: 15,
                                                color: active
                                                    ? Colors.white
                                                    : Colors.white70,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                label,
                                                style: TextStyle(
                                                  color: active
                                                      ? Colors.white
                                                      : Colors.white70,
                                                  fontSize: 12,
                                                  fontWeight: active
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }

                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        modeChip(
                                          targetMode: LaserPointerMode.line,
                                          icon: Icons.gesture_rounded,
                                          label: 'Nét',
                                        ),
                                        const SizedBox(width: 4),
                                        modeChip(
                                          targetMode: LaserPointerMode.dot,
                                          icon: Icons
                                              .radio_button_checked_rounded,
                                          label: 'Chỉ điểm',
                                        ),
                                        Container(
                                          width: 1,
                                          height: 18,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          color: Colors.white24,
                                        ),
                                        for (final c in LaserPointerController
                                            .presetColors)
                                          GestureDetector(
                                            onTap: () =>
                                                _laserController.setColor(c),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4),
                                              child: Container(
                                                width: 22,
                                                height: 22,
                                                decoration: BoxDecoration(
                                                  color: c,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: curColor == c
                                                        ? Colors.white
                                                        : Colors.white30,
                                                    width:
                                                        curColor == c ? 2.5 : 1,
                                                  ),
                                                  boxShadow: curColor == c
                                                      ? [
                                                          BoxShadow(
                                                            color: c.withAlpha(
                                                                180),
                                                            blurRadius: 6,
                                                          ),
                                                        ]
                                                      : null,
                                                ),
                                              ),
                                            ),
                                          ),
                                        Container(
                                          width: 1,
                                          height: 18,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          color: Colors.white24,
                                        ),
                                        GestureDetector(
                                          onTap: () {
                                            _laserController.clear();
                                            setState(() =>
                                                _activeTool = _lastPenTool);
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.all(2),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Item 7: Star-Only Floating Left Quick-Pen Favorites Dock flush to far left edge (left: 4)
                    if (appState.showFavoritesBar &&
                        appState.favoritePens.isNotEmpty)
                      Positioned(
                        left: 4,
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
                                final tool = EditorToolX.fromStrokeToolType(
                                  preset.toolType,
                                );
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
                                  _pressureSensitivity =
                                      preset.pressureSensitivity;
                                }
                                _selectedImageId = null;
                              });
                              _persistPenPrefs();
                            },
                            onRemovePreset: (preset) {
                              appState.toggleStarPen(preset);
                            },
                          ),
                        ),
                      ),

                // Draggable Right-Side Page Number Pill Fast-Scrollbar (tap = Page Grid, drag = scrub pages!)
                if (!currentPage.isInfiniteWhiteboard && !notebook.isWhiteboard)
                  () {
                    final int pageCount = math.max(1, notebook.pages.length);
                    final double trackTop = 14.0;
                    final double trackHeight =
                        math.max(80.0, vpSize.height - 64.0);
                    final double frac = pageCount <= 1
                        ? 0.0
                        : (currentIdx / (pageCount - 1)).clamp(0.0, 1.0);
                    final double thumbTop = trackTop + frac * trackHeight;

                    void scrubToDy(double localDy) {
                      if (pageCount <= 1) return;
                      final double nextFrac =
                          ((localDy - trackTop) / trackHeight).clamp(0.0, 1.0);
                      final int targetPage =
                          (nextFrac * (pageCount - 1)).round();
                      if (appState.verticalContinuousScroll) {
                        final m = _transformController.value;
                        final scale = m.getMaxScaleOnAxis().clamp(0.5, 4.0);
                        final tx = m.getTranslation().x;
                        final maxScrollY = math.max(
                          0.0,
                          _totalVerticalContentHeight(notebook) -
                              vpSize.height / scale,
                        );
                        final targetTy = -(nextFrac * maxScrollY * scale);
                        _transformController.value = Matrix4.identity()
                          ..translate(tx, targetTy)
                          ..scale(scale, scale);
                        if (_currentPageIndex != targetPage) {
                          setState(() {
                            _currentPageIndex = targetPage;
                            _renderedWindowCenter = targetPage;
                          });
                        }
                        _scrubPrefetchTimer?.cancel();
                        _scrubPrefetchTimer =
                            Timer(const Duration(milliseconds: 90), () {
                          if (!mounted) return;
                          final curNb = _getNotebook(context, listen: false);
                          if (curNb != null) {
                            _prefetchNearbyPdfPages(curNb);
                          }
                        });
                      } else if (_currentPageIndex != targetPage) {
                        _jumpToPage(targetPage);
                      }
                    }

                    return Positioned(
                      top: thumbTop,
                      right: 10,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openPageGridModal(notebook),
                        onVerticalDragStart: (_) {
                          _scrubPrefetchTimer?.cancel();
                          setState(() {
                            _isOverlayDragging = true;
                            _isScrubbingPages = true;
                          });
                        },
                        onVerticalDragUpdate: (d) {
                          final box = _viewportStackKey.currentContext
                              ?.findRenderObject() as RenderBox?;
                          if (box != null) {
                            final local = box.globalToLocal(d.globalPosition);
                            scrubToDy(local.dy);
                          }
                        },
                        onVerticalDragEnd: (_) {
                          _scrubPrefetchTimer?.cancel();
                          setState(() {
                            _isOverlayDragging = false;
                            _isScrubbingPages = false;
                            _renderedWindowCenter = _currentPageIndex;
                          });
                          final curNb = _getNotebook(context, listen: false);
                          if (curNb != null) {
                            _prefetchNearbyPdfPages(curNb);
                          }
                        },
                        onVerticalDragCancel: () {
                          _scrubPrefetchTimer?.cancel();
                          setState(() {
                            _isOverlayDragging = false;
                            _isScrubbingPages = false;
                            _renderedWindowCenter = _currentPageIndex;
                          });
                          final curNb = _getNotebook(context, listen: false);
                          if (curNb != null) {
                            _prefetchNearbyPdfPages(curNb);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: EditorColors.obsidianSurface.withAlpha(225),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: EditorColors.activeBlue.withAlpha(110),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.unfold_more_rounded,
                                size: 13,
                                color: EditorColors.activeBlue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Trang ${currentIdx + 1} / $pageCount',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }(),

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
                );
              },
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
  // INFINITE WHITEBOARD (6000 × 6000) + CONTINUOUS VERTICAL PAGES
  // ===========================================================================

  void _centerWhiteboard(Size viewportSize) {
    final tx = viewportSize.width * 0.5 - PaperMetrics.whiteboardCenter.dx;
    final ty = viewportSize.height * 0.5 - PaperMetrics.whiteboardCenter.dy;
    _whiteboardTransformController.value = Matrix4.identity()..translate(tx, ty);
    _whiteboardZoomNotifier.value = 1.0;
  }

  Widget _buildInfiniteWhiteboardView(
    Notebook notebook,
    NotePage page,
    int pageIndex,
    AppState appState,
  ) {
    final bool stylusBlocksViewport =
        !_stylusPanMode && (_isStylusDown || _isStylusHovering);
    final bool allowWhiteboardPanZoom = !_isOverlayDragging &&
        (_stylusPanMode ||
            (!stylusBlocksViewport &&
                (_pointerDownPositions.length >= 2 ||
                    _activeTouchPointers.length >= 2 ||
                    appState.readOnlyMode ||
                    (!_isDrawingPointerDown &&
                        (appState.palmRejectionEnabled ||
                            _activeTool == EditorTool.panZoom)))));

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (!_whiteboardCenteredOnce &&
            viewportSize.width > 0 &&
            viewportSize.height > 0) {
          _whiteboardCenteredOnce = true;
          _centerWhiteboard(viewportSize);
        }

        return Stack(
          children: [
            InteractiveViewer(
              transformationController: _whiteboardTransformController,
              constrained: false,
              minScale: 0.25,
              maxScale: 4.0,
              boundaryMargin: const EdgeInsets.all(800),
              panEnabled: allowWhiteboardPanZoom,
              scaleEnabled: !_isOverlayDragging && !stylusBlocksViewport,
              onInteractionUpdate: (_) {
                if (!_stylusPanMode &&
                    _isStylusDown &&
                    _lockedWhiteboardMatrixDuringStylus != null) {
                  _whiteboardTransformController.value =
                      _lockedWhiteboardMatrixDuringStylus!.clone();
                  return;
                }
                final scale = _whiteboardTransformController.value
                    .getMaxScaleOnAxis()
                    .clamp(0.25, 4.0);
                if ((scale - _whiteboardZoomNotifier.value).abs() > 0.015) {
                  _whiteboardZoomNotifier.value = scale;
                }
              },
              child: _buildSinglePageCanvas(
                notebook,
                page.isInfiniteWhiteboard
                    ? page
                    : page.copyWith(isInfiniteWhiteboard: true),
                pageIndex,
              ),
            ),
            // Floating bottom-right Về tâm (Center) + Zoom % pill
            Positioned(
              right: 16,
              bottom: 16,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(22),
                color: EditorColors.obsidianSurface.withAlpha(235),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => _centerWhiteboard(viewportSize),
                        borderRadius: BorderRadius.circular(14),
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.my_location_rounded,
                                size: 15,
                                color: EditorColors.activeBlue,
                              ),
                              SizedBox(width: 5),
                              Text(
                                'Về tâm',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: Colors.white12,
                      ),
                      InkWell(
                        onTap: () => _centerWhiteboard(viewportSize),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 5),
                          child: ValueListenableBuilder<double>(
                            valueListenable: _whiteboardZoomNotifier,
                            builder: (_, zoom, __) => Text(
                              '${(zoom * 100).round()}%',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVerticalContinuousPages(Notebook notebook) {
    // No nested SingleChildScrollView fighting InteractiveViewer!
    // One unified InteractiveViewer handles 144fps 1-finger scroll & 2-finger pinch-zoom cleanly.
    const int liveRadius = 8;
    final bool useWindowing = notebook.pages.length > 24;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < notebook.pages.length; i++) ...[
            if (!useWindowing ||
                (i - _renderedWindowCenter).abs() <= liveRadius)
              _buildSinglePageCanvas(notebook, notebook.pages[i], i)
            else
              () {
                final phSize = PaperMetrics.pageSize(
                  isLandscape: notebook.pages[i].isLandscape,
                  isInfiniteWhiteboard: notebook.pages[i].isInfiniteWhiteboard,
                );
                return SizedBox(
                  width: phSize.width,
                  height: phSize.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: PaperPalette.of(notebook.pages[i].paperColor)
                          .background,
                    ),
                  ),
                );
              }(),
            if (i < notebook.pages.length - 1) const SizedBox(height: 14),
          ],
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => _handlePullAddPage(notebook, notebook.pages.last),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: EditorColors.obsidianSurface.withAlpha(200),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 16,
                    color: EditorColors.activeBlue,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Chạm để thêm trang mới',
                    style: TextStyle(
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
    );
  }

  Widget _buildHorizontalFlipPages(Notebook notebook) {
    return PageView.builder(
      controller: _horizontalPageController,
      physics: !_isStylusDown &&
              !_isDrawingPointerDown &&
              (context.read<AppState>().palmRejectionEnabled ||
                  context.read<AppState>().readOnlyMode ||
                  _activeTool == EditorTool.panZoom)
          ? const PageScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: notebook.pages.length,
      onPageChanged: (i) {
        setState(() {
          _currentPageIndex = i;
          _renderedWindowCenter = i;
        });
        _prefetchNearbyPdfPages(notebook);
      },
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
    if (!_isScrubbingPages &&
        (pageIndex - _currentPageIndex).abs() <= _pdfPreloadRadius) {
      _ensurePdfImageLoaded(page.pdfBackgroundPath);
    }
    for (final img in page.imageElements) {
      _ensureElementImageLoaded(img.filePath);
    }
    final pageSize = PaperMetrics.pageSize(
      isLandscape: page.isLandscape,
      isInfiniteWhiteboard: page.isInfiniteWhiteboard,
    );
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
            // Layer 1 (Cached RepaintBoundary): Paper + PDF + Chronological Z-Index Images/Ink/Stencils
            // When Sticky Notes exist, base layer paints everything <= first sticky note's zIndex,
            // and upper slices paint newer images/strokes cleanly ON TOP OF earlier Sticky Notes!
            ...() {
              final sortedStickies = List<StickyNoteElement>.from(page.stickyNotes)
                ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
              final bool hasStickies = sortedStickies.isNotEmpty;
              final int? baseMaxZ =
                  hasStickies ? sortedStickies.first.zIndex : null;
              final bool readOnly = context.read<AppState>().readOnlyMode;

              bool hasCanvasItemInRange(int minExcl, int? maxIncl) {
                bool match(int z) =>
                    z > minExcl && (maxIncl == null || z <= maxIncl);
                return page.strokes.any((s) => match(s.zIndex)) ||
                    page.imageElements.any((e) => match(e.zIndex)) ||
                    page.stencilElements.any((e) => match(e.zIndex));
              }

              return <Widget>[
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
                        lassoSelectionBounds: isLassoOwner
                            ? _lassoController.selectionBounds
                            : null,
                        lassoDragOffset:
                            isLassoOwner ? _lassoDragOffsetNotifier : null,
                        erasingStrokesNotifier: _erasingStrokesNotifier,
                        hiddenImageId: _selectedImageId,
                        playingAudioId: _playingAudioId,
                        playingAudioTimeMsNotifier: (_playingAudioId != null &&
                                page.strokes.any((s) => s.audioId == _playingAudioId))
                            ? _audioPositionMsNotifier
                            : null,
                        repaintVersion: _repaintVersion,
                        drawBackground: true,
                        drawOverlays: !hasStickies,
                        drawTapes: false,
                        maxZInclusive: baseMaxZ,
                      ),
                    ),
                  ),
                ),

                // Layer 2 (144Hz Live Ink Overlay in its own RepaintBoundary — Zero Widget Rebuilds)
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerHover: (e) => _handlePointerHover(e, page),
                    onPointerDown: (e) => _handlePointerDown(e, page, pageIndex),
                    onPointerMove: (e) => _handlePointerMove(e, page),
                    onPointerUp: (e) => _handlePointerUp(e, page),
                    onPointerCancel: (e) => _handlePointerUp(e, page),
                    child: (_activeDrawingPageId == page.id ||
                            (_activeDrawingPageId == null && isActivePage))
                        ? RepaintBoundary(
                            child: CustomPaint(
                              size: pageSize,
                              painter: ActiveStrokePainter(
                                activeStroke: _activeStrokeNotifier,
                                eraserCursor: _eraserCursorNotifier,
                                lassoPath: _lassoPathNotifier,
                                tapeDraftRect: _tapeDraftNotifier,
                                isDarkPaper:
                                    page.paperColor == PaperColorType.dark,
                                eraserRadius: _eraserRadius,
                              ),
                            ),
                          )
                        : const SizedBox.expand(),
                  ),
                ),

                // Laser Pointer Fading Trail Overlay in its own RepaintBoundary
                if (isActivePage ||
                    _laserController.activePageId == page.id ||
                    (_activeTool == EditorTool.laserPointer &&
                        (pageIndex - _currentPageIndex).abs() <= 2))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: LaserPointerPainter(
                            controller: _laserController,
                            pageId: page.id,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Chronological Sticky Notes interleaved with newer Images/Strokes/Stencils
                for (int si = 0; si < sortedStickies.length; si++) ...[
                  _buildStickyNoteOverlay(page, sortedStickies[si], readOnly),
                  if (hasCanvasItemInRange(
                        sortedStickies[si].zIndex,
                        si + 1 < sortedStickies.length
                            ? sortedStickies[si + 1].zIndex
                            : null,
                      ) ||
                      si == sortedStickies.length - 1)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: pageSize,
                            painter: CanvasPainter(
                              page: page,
                              elementImageCache: _elementImageCache,
                              lassoSelection: isLassoOwner
                                  ? _lassoController.selection
                                  : const LassoSelection(),
                              lassoSelectionBounds: isLassoOwner
                                  ? _lassoController.selectionBounds
                                  : null,
                              lassoDragOffset: isLassoOwner
                                  ? _lassoDragOffsetNotifier
                                  : null,
                              erasingStrokesNotifier: _erasingStrokesNotifier,
                              hiddenImageId: _selectedImageId,
                              playingAudioId: _playingAudioId,
                              playingAudioTimeMsNotifier: (_playingAudioId != null &&
                                      page.strokes
                                          .any((s) => s.audioId == _playingAudioId))
                                  ? _audioPositionMsNotifier
                                  : null,
                              repaintVersion: _repaintVersion,
                              drawBackground: false,
                              drawOverlays: si == sortedStickies.length - 1,
                              drawTapes: false,
                              minZExclusive: sortedStickies[si].zIndex,
                              maxZInclusive: si + 1 < sortedStickies.length
                                  ? sortedStickies[si + 1].zIndex
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ];
            }(),

            // Interactive Image Overlays (8 handles; 6-button Pill rendered as outer Stack sibling below)
            for (final img in page.imageElements) _buildImageOverlay(page, img),

            // Interactive Attachment Cards (DOC/PPT/PDF/Files)
            for (final att in page.attachmentElements)
              _buildAttachmentOverlay(page, att),

            // Interactive Stencil Overlays
            for (final st in page.stencilElements)
              _buildStencilOverlay(page, st),

            // Interactive Text Overlays (zero-lag local controller + 144fps drag)
            for (final txt in page.textElements) _buildTextOverlay(page, txt),

            // 100% Opaque & Deletable Study Tape Overlays (ABOVE all strokes!)
            for (final tape in page.tapeElements)
              _buildStudyTapeOverlay(
                page,
                tape,
                context.read<AppState>().readOnlyMode,
              ),

            // 6-Button Floating Image Action Pill (Direct sibling in outer Stack so hit-testing works 100%!)
            if ((_activeTool == EditorTool.image ||
                    _activeTool == EditorTool.lasso) &&
                _selectedImageId != null)
              ...() {
                ImageElement? selImg;
                for (final e in page.imageElements) {
                  if (e.id == _selectedImageId) {
                    selImg = e;
                    break;
                  }
                }
                if (selImg == null) return const <Widget>[];
                final targetImg = selImg;
                return <Widget>[
                  ValueListenableBuilder<
                      ({String id, double x, double y, double w, double h})?>(
                    valueListenable: _imageDragNotifier,
                    builder: (_, drag, __) {
                      final bool draggingThis =
                          drag != null && drag.id == targetImg.id;
                      final double imgX =
                          draggingThis ? drag.x : targetImg.x;
                      final double imgY =
                          draggingThis ? drag.y : targetImg.y;
                      final double pillLeft = imgX.clamp(
                        8.0,
                        math.max(8.0, pageSize.width - 420.0),
                      );
                      final double pillTop = (imgY - 52.0).clamp(
                        8.0,
                        math.max(8.0, pageSize.height - 56.0),
                      );
                      final bool isCroppingThis =
                          _croppingImageId == targetImg.id;
                      return Positioned(
                        left: pillLeft,
                        top: pillTop,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          child: isCroppingThis
                              ? _buildInlineCropPill(page, targetImg)
                              : ImageActionPill(
                                  onCropRect: () {
                                    setState(() {
                                      _croppingImageId = targetImg.id;
                                    });
                                    _cropDraftNotifier.value = (
                                      id: targetImg.id,
                                      left: targetImg.cropLeft,
                                      top: targetImg.cropTop,
                                      right: targetImg.cropRight,
                                      bottom: targetImg.cropBottom,
                                    );
                                  },
                                  onCropFreehand: () => _openImageCrop(
                                    page,
                                    targetImg,
                                    ImageCropMode.freehand,
                                  ),
                                  onCopy: () {
                                    final dup = targetImg.copyWith(
                                      id: _uuid.v4(),
                                      x: targetImg.x + 24,
                                      y: targetImg.y + 24,
                                      zIndex:
                                          DateTime.now().millisecondsSinceEpoch,
                                    );
                                    _commitPage(
                                      page.copyWith(
                                        imageElements: [
                                          ...page.imageElements,
                                          dup
                                        ],
                                      ),
                                      undoSnapshot: page,
                                    );
                                    setState(() => _selectedImageId = dup.id);
                                  },
                                  onCut: () {
                                    _lassoController.clear();
                                    _selectedImageId = null;
                                    _croppingImageId = null;
                                    _cropDraftNotifier.value = null;
                                    final updated = page.imageElements
                                        .where((e) => e.id != targetImg.id)
                                        .toList();
                                    _commitPage(
                                      page.copyWith(imageElements: updated),
                                      undoSnapshot: page,
                                    );
                                  },
                                  onAddToStickers: () {
                                    context
                                        .read<AppState>()
                                        .addCustomSticker(targetImg.filePath);
                                  },
                                  onDelete: () {
                                    _selectedImageId = null;
                                    _croppingImageId = null;
                                    _cropDraftNotifier.value = null;
                                    final updated = page.imageElements
                                        .where((e) => e.id != targetImg.id)
                                        .toList();
                                    _commitPage(
                                      page.copyWith(imageElements: updated),
                                      undoSnapshot: page,
                                    );
                                  },
                                ),
                        ),
                      );
                    },
                  ),
                ];
              }(),

            // Movable Zoom Window Focus Indicator on Active Page (locks page pan while dragging!)
            if (_zoomWindowEnabled && isActivePage)
              Positioned(
                left: _zoomFocusRect.left,
                top: _zoomFocusRect.top,
                child: GestureDetector(
                  onPanStart: (_) => setState(() => _isOverlayDragging = true),
                  onPanUpdate: (d) {
                    setState(() {
                      _zoomFocusRect = _zoomFocusRect.shift(d.delta);
                    });
                  },
                  onPanEnd: (_) => setState(() => _isOverlayDragging = false),
                  onPanCancel: () => setState(() => _isOverlayDragging = false),
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
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: pageSize,
                        painter: CanvasPainter(
                          page: page,
                          pdfBackgroundImage: page.pdfBackgroundPath != null
                              ? _pdfImageCache[page.pdfBackgroundPath!]
                              : null,
                          elementImageCache: _elementImageCache,
                          repaintVersion: _repaintVersion,
                        ),
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
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: pageSize,
                          painter: ActiveStrokePainter(
                            activeStroke: _activeStrokeNotifier,
                            eraserCursor: _eraserCursorNotifier,
                            lassoPath: _lassoPathNotifier,
                            tapeDraftRect: _tapeDraftNotifier,
                            isDarkPaper: page.paperColor == PaperColorType.dark,
                          ),
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

  Widget _buildStudyTapeOverlay(
    NotePage page,
    TapeElement tape,
    bool readOnly,
  ) {
    final baseColor = Color(tape.colorValue);
    return Positioned(
      left: tape.x,
      top: tape.y,
      width: tape.width,
      height: tape.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final updated = page.tapeElements
              .map((t) => t.id == tape.id
                  ? t.copyWith(isRevealed: !t.isRevealed)
                  : t)
              .toList();
          _commitPage(
            page.copyWith(tapeElements: updated),
            undoSnapshot: page,
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 100% solid opaque fill when unrevealed (0% ink bleed-through!)
            Container(
              decoration: BoxDecoration(
                color: tape.isRevealed
                    ? baseColor.withAlpha(24)
                    : baseColor.withAlpha(255),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: tape.isRevealed
                      ? baseColor.withAlpha(170)
                      : Colors.black.withAlpha(35),
                  width: 1.4,
                ),
              ),
              alignment: Alignment.center,
              child: tape.isRevealed
                  ? null
                  : Text(
                      'Chạm để hiện',
                      style: TextStyle(
                        color: Colors.white.withAlpha(220),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            // Crisp 32x32 Delete (`×`) button on the right edge
            if (!readOnly)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final updated = page.tapeElements
                          .where((t) => t.id != tape.id)
                          .toList();
                      _commitPage(
                        page.copyWith(tapeElements: updated),
                        undoSnapshot: page,
                      );
                    },
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(110),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextOverlay(NotePage page, TextElement element) {
    final bool isSelected = _selectedTextId == element.id;
    final bool readOnly = context.read<AppState>().readOnlyMode;
    final bool interactive = !readOnly &&
        (_activeTool == EditorTool.panZoom ||
            _activeTool == EditorTool.textBox ||
            isSelected);

    return _DraggableTextBoxOverlay(
      key: ValueKey('txt_${element.id}'),
      element: element,
      interactive: interactive,
      isSelected: isSelected,
      onSelect: () {
        if (_selectedTextId != element.id) {
          setState(() {
            _selectedTextId = element.id;
            _selectedImageId = null;
            _selectedStencilId = null;
          });
        }
      },
      onDragStart: () => setState(() => _isOverlayDragging = true),
      onDragEnd: () => setState(() => _isOverlayDragging = false),
      onCommit: (updatedEl) {
        final updated = page.textElements
            .map((t) => t.id == element.id ? updatedEl : t)
            .toList();
        _commitPage(
          page.copyWith(textElements: updated),
          undoSnapshot: page,
        );
      },
      onDelete: () {
        _editingTextId = null;
        _selectedTextId = null;
        final updated =
            page.textElements.where((t) => t.id != element.id).toList();
        _commitPage(
          page.copyWith(textElements: updated),
          undoSnapshot: page,
        );
      },
      resizeHandle: _buildResizeHandle(),
    );
  }

  Widget _buildInlineCropPill(NotePage page, ImageElement img) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(22),
      color: EditorColors.obsidianSurface.withAlpha(242),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: EditorColors.activeBlue.withAlpha(140)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () {
                final draft = _cropDraftNotifier.value;
                if (draft != null && draft.id == img.id) {
                  // Compute new on-page bounds matching the trimmed region
                  final oldSpanX = math.max(0.01, img.cropRight - img.cropLeft);
                  final oldSpanY = math.max(0.01, img.cropBottom - img.cropTop);
                  final fullW = img.width / oldSpanX;
                  final fullH = img.height / oldSpanY;
                  final fullX = img.x - img.cropLeft * fullW;
                  final fullY = img.y - img.cropTop * fullH;

                  final newW = math.max(8.0, (draft.right - draft.left) * fullW);
                  final newH = math.max(8.0, (draft.bottom - draft.top) * fullH);
                  final newX = fullX + draft.left * fullW;
                  final newY = fullY + draft.top * fullH;

                  final updated = page.imageElements
                      .map((e) => e.id == img.id
                          ? e.copyWith(
                              x: newX,
                              y: newY,
                              width: newW,
                              height: newH,
                              cropLeft: draft.left,
                              cropTop: draft.top,
                              cropRight: draft.right,
                              cropBottom: draft.bottom,
                              freehandClipPath: const [],
                            )
                          : e)
                      .toList();
                  _commitPage(
                    page.copyWith(imageElements: updated),
                    undoSnapshot: page,
                  );
                }
                _cropDraftNotifier.value = null;
                setState(() => _croppingImageId = null);
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: EditorColors.activeBlue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, size: 15, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Xong',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () {
                _cropDraftNotifier.value = (
                  id: img.id,
                  left: 0.0,
                  top: 0.0,
                  right: 1.0,
                  bottom: 1.0,
                );
              },
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Text(
                  'Đặt lại',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () {
                _cropDraftNotifier.value = null;
                setState(() => _croppingImageId = null);
              },
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded, size: 15, color: Colors.white70),
                    SizedBox(width: 3),
                    Text(
                      'Hủy',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCropBracketHandle() {
    return SizedBox(
      width: 56,
      height: 56,
      child: Center(
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: EditorColors.activeBlue,
            borderRadius: BorderRadius.circular(3.5),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 3),
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
    final bool isCropping = isSelected && _croppingImageId == img.id;
    final ui.Image? cachedUiImg = _elementImageCache[img.filePath];
    final file = File(img.filePath);

    // IN-PLACE ON-CANVAS RECTANGULAR CROP MODE (144fps ValueNotifier, ZERO modal!)
    if (isCropping) {
      final oldSpanX = math.max(0.01, img.cropRight - img.cropLeft);
      final oldSpanY = math.max(0.01, img.cropBottom - img.cropTop);
      final fullW = img.width / oldSpanX;
      final fullH = img.height / oldSpanY;
      final fullX = img.x - img.cropLeft * fullW;
      final fullY = img.y - img.cropTop * fullH;
      final minNormX = (8.0 / fullW).clamp(0.01, 0.45);
      final minNormY = (8.0 / fullH).clamp(0.01, 0.45);
      const double cropPad = 32.0;

      void updateCrop(
        ({String id, double left, double top, double right, double bottom})
                Function(
          ({String id, double left, double top, double right, double bottom}) c,
        )
            fn,
      ) {
        final cur = _cropDraftNotifier.value ??
            (
              id: img.id,
              left: img.cropLeft,
              top: img.cropTop,
              right: img.cropRight,
              bottom: img.cropBottom,
            );
        _cropDraftNotifier.value = fn(cur);
      }

      return ValueListenableBuilder<
          ({String id, double left, double top, double right, double bottom})?>(
        valueListenable: _cropDraftNotifier,
        builder: (_, draft, __) {
          final double cl =
              (draft != null && draft.id == img.id) ? draft.left : img.cropLeft;
          final double ct =
              (draft != null && draft.id == img.id) ? draft.top : img.cropTop;
          final double cr = (draft != null && draft.id == img.id)
              ? draft.right
              : img.cropRight;
          final double cb = (draft != null && draft.id == img.id)
              ? draft.bottom
              : img.cropBottom;

          final cropRect = Rect.fromLTRB(
            cl * fullW,
            ct * fullH,
            cr * fullW,
            cb * fullH,
          );
          final uiRect = cropRect.shift(const Offset(cropPad, cropPad));

          return Positioned(
            left: fullX - cropPad,
            top: fullY - cropPad,
            child: Transform.rotate(
              angle: img.rotation,
              child: SizedBox(
                width: fullW + cropPad * 2,
                height: fullH + cropPad * 2,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Full uncropped image with dimmed veil outside live cropRect
                    Positioned(
                      left: cropPad,
                      top: cropPad,
                      width: fullW,
                      height: fullH,
                      child: RepaintBoundary(
                        child: cachedUiImg != null
                            ? CustomPaint(
                                painter: _SelectedImagePainter(
                                  image: cachedUiImg,
                                  cropLeft: 0.0,
                                  cropTop: 0.0,
                                  cropRight: 1.0,
                                  cropBottom: 1.0,
                                  dimOutsideRect: cropRect,
                                ),
                              )
                            : (file.existsSync()
                                ? Image.file(
                                    file,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                  )
                                : const SizedBox.expand()),
                      ),
                    ),
                    // Crisp blue live crop border
                    Positioned.fromRect(
                      rect: uiRect,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: EditorColors.activeBlue,
                              width: 2.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 4 Edge-Drag Strips along crop border (placed BELOW 56x56 corner/mid handles)
                    if (uiRect.width > 36) ...[
                      Positioned(
                        left: uiRect.left + 14,
                        top: uiRect.top - 14,
                        width: uiRect.width - 28,
                        height: 28,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) =>
                              setState(() => _isOverlayDragging = true),
                          onPanUpdate: (d) => updateCrop((c) => (
                                id: c.id,
                                left: c.left,
                                top: (c.top + d.delta.dy / fullH)
                                    .clamp(0.0, c.bottom - minNormY),
                                right: c.right,
                                bottom: c.bottom,
                              )),
                          onPanEnd: (_) =>
                              setState(() => _isOverlayDragging = false),
                          onPanCancel: () =>
                              setState(() => _isOverlayDragging = false),
                        ),
                      ),
                      Positioned(
                        left: uiRect.left + 14,
                        top: uiRect.bottom - 14,
                        width: uiRect.width - 28,
                        height: 28,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) =>
                              setState(() => _isOverlayDragging = true),
                          onPanUpdate: (d) => updateCrop((c) => (
                                id: c.id,
                                left: c.left,
                                top: c.top,
                                right: c.right,
                                bottom: (c.bottom + d.delta.dy / fullH)
                                    .clamp(c.top + minNormY, 1.0),
                              )),
                          onPanEnd: (_) =>
                              setState(() => _isOverlayDragging = false),
                          onPanCancel: () =>
                              setState(() => _isOverlayDragging = false),
                        ),
                      ),
                    ],
                    if (uiRect.height > 36) ...[
                      Positioned(
                        left: uiRect.left - 14,
                        top: uiRect.top + 14,
                        width: 28,
                        height: uiRect.height - 28,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) =>
                              setState(() => _isOverlayDragging = true),
                          onPanUpdate: (d) => updateCrop((c) => (
                                id: c.id,
                                left: (c.left + d.delta.dx / fullW)
                                    .clamp(0.0, c.right - minNormX),
                                top: c.top,
                                right: c.right,
                                bottom: c.bottom,
                              )),
                          onPanEnd: (_) =>
                              setState(() => _isOverlayDragging = false),
                          onPanCancel: () =>
                              setState(() => _isOverlayDragging = false),
                        ),
                      ),
                      Positioned(
                        left: uiRect.right - 14,
                        top: uiRect.top + 14,
                        width: 28,
                        height: uiRect.height - 28,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) =>
                              setState(() => _isOverlayDragging = true),
                          onPanUpdate: (d) => updateCrop((c) => (
                                id: c.id,
                                left: c.left,
                                top: c.top,
                                right: (c.right + d.delta.dx / fullW)
                                    .clamp(c.left + minNormX, 1.0),
                                bottom: c.bottom,
                              )),
                          onPanEnd: (_) =>
                              setState(() => _isOverlayDragging = false),
                          onPanCancel: () =>
                              setState(() => _isOverlayDragging = false),
                        ),
                      ),
                    ],
                    // 8 In-Place Crop Handles (56x56 px stylus-friendly hitboxes, 100% inside cropPad bounds!)
                    // Top-Left
                    Positioned(
                      left: uiRect.left - 28,
                      top: uiRect.top - 28,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) =>
                            setState(() => _isOverlayDragging = true),
                        onPanUpdate: (d) => updateCrop((c) => (
                              id: c.id,
                              left: (c.left + d.delta.dx / fullW)
                                  .clamp(0.0, c.right - minNormX),
                              top: (c.top + d.delta.dy / fullH)
                                  .clamp(0.0, c.bottom - minNormY),
                              right: c.right,
                              bottom: c.bottom,
                            )),
                        onPanEnd: (_) =>
                            setState(() => _isOverlayDragging = false),
                        onPanCancel: () =>
                            setState(() => _isOverlayDragging = false),
                        child: _buildCropBracketHandle(),
                      ),
                    ),
                    // Top-Center
                    Positioned(
                      left: (uiRect.left + uiRect.right) * 0.5 - 28,
                      top: uiRect.top - 28,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) =>
                            setState(() => _isOverlayDragging = true),
                        onPanUpdate: (d) => updateCrop((c) => (
                              id: c.id,
                              left: c.left,
                              top: (c.top + d.delta.dy / fullH)
                                  .clamp(0.0, c.bottom - minNormY),
                              right: c.right,
                              bottom: c.bottom,
                            )),
                        onPanEnd: (_) =>
                            setState(() => _isOverlayDragging = false),
                        onPanCancel: () =>
                            setState(() => _isOverlayDragging = false),
                        child: _buildCropBracketHandle(),
                      ),
                    ),
                    // Top-Right
                    Positioned(
                      left: uiRect.right - 28,
                      top: uiRect.top - 28,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) =>
                            setState(() => _isOverlayDragging = true),
                        onPanUpdate: (d) => updateCrop((c) => (
                              id: c.id,
                              left: c.left,
                              top: (c.top + d.delta.dy / fullH)
                                  .clamp(0.0, c.bottom - minNormY),
                              right: (c.right + d.delta.dx / fullW)
                                  .clamp(c.left + minNormX, 1.0),
                              bottom: c.bottom,
                            )),
                        onPanEnd: (_) =>
                            setState(() => _isOverlayDragging = false),
                        onPanCancel: () =>
                            setState(() => _isOverlayDragging = false),
                        child: _buildCropBracketHandle(),
                      ),
                    ),
                    // Middle-Left
                    Positioned(
                      left: uiRect.left - 28,
                      top: (uiRect.top + uiRect.bottom) * 0.5 - 28,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) =>
                            setState(() => _isOverlayDragging = true),
                        onPanUpdate: (d) => updateCrop((c) => (
                              id: c.id,
                              left: (c.left + d.delta.dx / fullW)
                                  .clamp(0.0, c.right - minNormX),
                              top: c.top,
                              right: c.right,
                              bottom: c.bottom,
                            )),
                        onPanEnd: (_) =>
                            setState(() => _isOverlayDragging = false),
                        onPanCancel: () =>
                            setState(() => _isOverlayDragging = false),
                        child: _buildCropBracketHandle(),
                      ),
                    ),
                    // Middle-Right
                    Positioned(
                      left: uiRect.right - 28,
                      top: (uiRect.top + uiRect.bottom) * 0.5 - 28,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) =>
                            setState(() => _isOverlayDragging = true),
                        onPanUpdate: (d) => updateCrop((c) => (
                              id: c.id,
                              left: c.left,
                              top: c.top,
                              right: (c.right + d.delta.dx / fullW)
                                  .clamp(c.left + minNormX, 1.0),
                              bottom: c.bottom,
                            )),
                        onPanEnd: (_) =>
                            setState(() => _isOverlayDragging = false),
                        onPanCancel: () =>
                            setState(() => _isOverlayDragging = false),
                        child: _buildCropBracketHandle(),
                      ),
                    ),
                    // Bottom-Left
                    Positioned(
                      left: uiRect.left - 28,
                      top: uiRect.bottom - 28,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) =>
                            setState(() => _isOverlayDragging = true),
                        onPanUpdate: (d) => updateCrop((c) => (
                              id: c.id,
                              left: (c.left + d.delta.dx / fullW)
                                  .clamp(0.0, c.right - minNormX),
                              top: c.top,
                              right: c.right,
                              bottom: (c.bottom + d.delta.dy / fullH)
                                  .clamp(c.top + minNormY, 1.0),
                            )),
                        onPanEnd: (_) =>
                            setState(() => _isOverlayDragging = false),
                        onPanCancel: () =>
                            setState(() => _isOverlayDragging = false),
                        child: _buildCropBracketHandle(),
                      ),
                    ),
                    // Bottom-Center
                    Positioned(
                      left: (uiRect.left + uiRect.right) * 0.5 - 28,
                      top: uiRect.bottom - 28,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) =>
                            setState(() => _isOverlayDragging = true),
                        onPanUpdate: (d) => updateCrop((c) => (
                              id: c.id,
                              left: c.left,
                              top: c.top,
                              right: c.right,
                              bottom: (c.bottom + d.delta.dy / fullH)
                                  .clamp(c.top + minNormY, 1.0),
                            )),
                        onPanEnd: (_) =>
                            setState(() => _isOverlayDragging = false),
                        onPanCancel: () =>
                            setState(() => _isOverlayDragging = false),
                        child: _buildCropBracketHandle(),
                      ),
                    ),
                    // Bottom-Right
                    Positioned(
                      left: uiRect.right - 28,
                      top: uiRect.bottom - 28,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) =>
                            setState(() => _isOverlayDragging = true),
                        onPanUpdate: (d) => updateCrop((c) => (
                              id: c.id,
                              left: c.left,
                              top: c.top,
                              right: (c.right + d.delta.dx / fullW)
                                  .clamp(c.left + minNormX, 1.0),
                              bottom: (c.bottom + d.delta.dy / fullH)
                                  .clamp(c.top + minNormY, 1.0),
                            )),
                        onPanEnd: (_) =>
                            setState(() => _isOverlayDragging = false),
                        onPanCancel: () =>
                            setState(() => _isOverlayDragging = false),
                        child: _buildCropBracketHandle(),
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

    void beginDrag() {
      _imageDragNotifier.value = (
        id: img.id,
        x: img.x,
        y: img.y,
        w: img.width,
        h: img.height,
      );
      if (!_isOverlayDragging) {
        setState(() => _isOverlayDragging = true);
      }
    }

    void updateDrag(
      ({String id, double x, double y, double w, double h}) Function(
        ({String id, double x, double y, double w, double h}) cur,
      ) transform,
    ) {
      final cur = _imageDragNotifier.value ??
          (id: img.id, x: img.x, y: img.y, w: img.width, h: img.height);
      if (cur.id != img.id) return;
      _imageDragNotifier.value = transform(cur);
    }

    void endDrag() {
      _cornerResizeStart = null;
      final finalDrag = _imageDragNotifier.value;
      _imageDragNotifier.value = null;
      if (finalDrag != null && finalDrag.id == img.id) {
        final updated = page.imageElements
            .map((e) => e.id == img.id
                ? e.copyWith(
                    x: finalDrag.x,
                    y: finalDrag.y,
                    width: finalDrag.w,
                    height: finalDrag.h,
                  )
                : e)
            .toList();
        _commitPage(
          page.copyWith(imageElements: updated),
          undoSnapshot: page,
        );
      }
      if (_isOverlayDragging) {
        setState(() => _isOverlayDragging = false);
      }
    }

    void beginCornerResize(DragStartDetails d) {
      final double canvasScale = (page.isInfiniteWhiteboard
              ? _whiteboardTransformController.value
              : _transformController.value)
          .getMaxScaleOnAxis()
          .clamp(0.25, 4.0);
      _cornerResizeStart = (
        startGlobal: d.globalPosition,
        startX: img.x,
        startY: img.y,
        startW: img.width,
        startH: img.height,
        canvasScale: canvasScale,
      );
      beginDrag();
    }

    void updateCornerResize(
      DragUpdateDetails d, {
      required double signX,
      required double signY,
      required bool anchorRight,
      required bool anchorBottom,
    }) {
      final st = _cornerResizeStart;
      if (st == null) return;
      final screenDelta = d.globalPosition - st.startGlobal;
      final double pageDx = screenDelta.dx / st.canvasScale;
      final double pageDy = screenDelta.dy / st.canvasScale;
      final double cosR = math.cos(-img.rotation);
      final double sinR = math.sin(-img.rotation);
      final double localDx = pageDx * cosR - pageDy * sinR;
      final double localDy = pageDx * sinR + pageDy * cosR;
      final double diagLen = math.max(
        1.0,
        math.sqrt(st.startW * st.startW + st.startH * st.startH),
      );
      final double dirX = signX * (st.startW / diagLen);
      final double dirY = signY * (st.startH / diagLen);
      final double proj = localDx * dirX + localDy * dirY;
      final double minScale = math.max(
        32.0 / math.max(1.0, st.startW),
        32.0 / math.max(1.0, st.startH),
      );
      final double scaleFactor =
          math.max(minScale, (diagLen + proj) / diagLen);
      final double nw = st.startW * scaleFactor;
      final double nh = st.startH * scaleFactor;
      final double nx = anchorRight ? st.startX + (st.startW - nw) : st.startX;
      final double ny = anchorBottom ? st.startY + (st.startH - nh) : st.startY;
      _imageDragNotifier.value = (
        id: img.id,
        x: nx,
        y: ny,
        w: nw,
        h: nh,
      );
    }

    return ValueListenableBuilder<
        ({String id, double x, double y, double w, double h})?>(
      valueListenable: _imageDragNotifier,
      builder: (_, drag, __) {
        final bool draggingThis = drag != null && drag.id == img.id;
        final double x = draggingThis ? drag.x : img.x;
        final double y = draggingThis ? drag.y : img.y;
        final double w = draggingThis ? drag.w : img.width;
        final double h = draggingThis ? drag.h : img.height;

        // Expand Positioned bounds by 24px on all 4 sides when selected so all 8
        // 48x48 px stylus-friendly circular handles sit 100% INSIDE hit-test bounds!
        final double pad = isSelected ? 24.0 : 0.0;
        return Positioned(
          left: x - pad,
          top: y - pad,
          width: w + pad * 2,
          height: h + pad * 2,
          child: IgnorePointer(
            ignoring: !interactive,
            child: Listener(
              onPointerDown: isSelected
                  ? (e) => _overlayTouchPointers.add(e.pointer)
                  : null,
              onPointerUp: isSelected
                  ? (e) => _overlayTouchPointers.remove(e.pointer)
                  : null,
              onPointerCancel: isSelected
                  ? (e) => _overlayTouchPointers.remove(e.pointer)
                  : null,
              child: Transform.rotate(
                angle: img.rotation,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Image body drag area (placed BELOW the 8 resize handles in Stack!)
                  Positioned(
                    left: pad,
                    top: pad,
                    width: w,
                    height: h,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        _selectedImageId = img.id;
                        _croppingImageId = null;
                        _cropDraftNotifier.value = null;
                        _selectedTextId = null;
                        _selectedStencilId = null;
                      }),
                      onPanStart: (_) => beginDrag(),
                      onPanUpdate: (d) => updateDrag(
                        (c) => (
                          id: c.id,
                          x: c.x + d.delta.dx,
                          y: c.y + d.delta.dy,
                          w: c.w,
                          h: c.h,
                        ),
                      ),
                      onPanEnd: (_) => endDrag(),
                      onPanCancel: endDrag,
                      child: RepaintBoundary(
                        child: Container(
                          width: w,
                          height: h,
                          decoration: BoxDecoration(
                            border: isSelected
                                ? Border.all(
                                    color: EditorColors.activeBlue,
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: isSelected
                              ? (cachedUiImg != null
                                  ? CustomPaint(
                                      painter: _SelectedImagePainter(
                                        image: cachedUiImg,
                                        cropLeft: img.cropLeft,
                                        cropTop: img.cropTop,
                                        cropRight: img.cropRight,
                                        cropBottom: img.cropBottom,
                                        freehandClipPath: img.freehandClipPath,
                                      ),
                                    )
                                  : (file.existsSync()
                                      ? Image.file(
                                          file,
                                          fit: BoxFit.contain,
                                          filterQuality: FilterQuality.medium,
                                          cacheWidth: 1600,
                                          gaplessPlayback: true,
                                        )
                                      : Container(
                                          color: Colors.grey.shade200,
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.broken_image_outlined,
                                            size: 32,
                                          ),
                                        )))
                              : (cachedUiImg != null
                                  ? const SizedBox.expand()
                                  : (file.existsSync()
                                      ? Image.file(
                                          file,
                                          fit: BoxFit.contain,
                                          filterQuality: FilterQuality.medium,
                                          cacheWidth: 1600,
                                          gaplessPlayback: true,
                                        )
                                      : const SizedBox.expand())),
                        ),
                      ),
                    ),
                  ),
                  if (isSelected) ...[
                    // Rotate handle (bottom-center stem)
                    Positioned(
                      left: pad + w * 0.5 - 24,
                      bottom: -26,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          final updated = page.imageElements
                              .map((e) => e.id == img.id
                                  ? e.copyWith(
                                      rotation: e.rotation + math.pi / 12,
                                    )
                                  : e)
                              .toList();
                          _commitPage(
                            page.copyWith(imageElements: updated),
                            undoSnapshot: page,
                          );
                        },
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: EditorColors.activeBlue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.rotate_right_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 8 Resize Handles — 100% INSIDE the 24px-padded bounds, ABOVE body drag!
                    // Top-Left (1:1 aspect-locked uniform corner scaling anchored at bottom-right)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: beginCornerResize,
                        onPanUpdate: (d) => updateCornerResize(
                          d,
                          signX: -1,
                          signY: -1,
                          anchorRight: true,
                          anchorBottom: true,
                        ),
                        onPanEnd: (_) => endDrag(),
                        onPanCancel: endDrag,
                        child: _buildResizeHandle(),
                      ),
                    ),
                    // Top-Center
                    Positioned(
                      left: pad + w * 0.5 - 24,
                      top: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => beginDrag(),
                        onPanUpdate: (d) => updateDrag((c) {
                          final nh = math.max(32.0, c.h - d.delta.dy);
                          return (
                            id: c.id,
                            x: c.x,
                            y: c.y + (c.h - nh),
                            w: c.w,
                            h: nh,
                          );
                        }),
                        onPanEnd: (_) => endDrag(),
                        onPanCancel: endDrag,
                        child: _buildResizeHandle(),
                      ),
                    ),
                    // Top-Right (1:1 aspect-locked uniform corner scaling anchored at bottom-left)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: beginCornerResize,
                        onPanUpdate: (d) => updateCornerResize(
                          d,
                          signX: 1,
                          signY: -1,
                          anchorRight: false,
                          anchorBottom: true,
                        ),
                        onPanEnd: (_) => endDrag(),
                        onPanCancel: endDrag,
                        child: _buildResizeHandle(),
                      ),
                    ),
                    // Middle-Left
                    Positioned(
                      left: 0,
                      top: pad + h * 0.5 - 24,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => beginDrag(),
                        onPanUpdate: (d) => updateDrag((c) {
                          final nw = math.max(32.0, c.w - d.delta.dx);
                          return (
                            id: c.id,
                            x: c.x + (c.w - nw),
                            y: c.y,
                            w: nw,
                            h: c.h,
                          );
                        }),
                        onPanEnd: (_) => endDrag(),
                        onPanCancel: endDrag,
                        child: _buildResizeHandle(),
                      ),
                    ),
                    // Middle-Right
                    Positioned(
                      right: 0,
                      top: pad + h * 0.5 - 24,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => beginDrag(),
                        onPanUpdate: (d) => updateDrag((c) => (
                              id: c.id,
                              x: c.x,
                              y: c.y,
                              w: math.max(32.0, c.w + d.delta.dx),
                              h: c.h,
                            )),
                        onPanEnd: (_) => endDrag(),
                        onPanCancel: endDrag,
                        child: _buildResizeHandle(),
                      ),
                    ),
                    // Bottom-Left (1:1 aspect-locked uniform corner scaling anchored at top-right)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: beginCornerResize,
                        onPanUpdate: (d) => updateCornerResize(
                          d,
                          signX: -1,
                          signY: 1,
                          anchorRight: true,
                          anchorBottom: false,
                        ),
                        onPanEnd: (_) => endDrag(),
                        onPanCancel: endDrag,
                        child: _buildResizeHandle(),
                      ),
                    ),
                    // Bottom-Center
                    Positioned(
                      left: pad + w * 0.5 - 24,
                      bottom: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => beginDrag(),
                        onPanUpdate: (d) => updateDrag((c) => (
                              id: c.id,
                              x: c.x,
                              y: c.y,
                              w: c.w,
                              h: math.max(32.0, c.h + d.delta.dy),
                            )),
                        onPanEnd: (_) => endDrag(),
                        onPanCancel: endDrag,
                        child: _buildResizeHandle(),
                      ),
                    ),
                    // Bottom-Right (1:1 aspect-locked uniform corner scaling anchored at top-left)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: beginCornerResize,
                        onPanUpdate: (d) => updateCornerResize(
                          d,
                          signX: 1,
                          signY: 1,
                          anchorRight: false,
                          anchorBottom: false,
                        ),
                        onPanEnd: (_) => endDrag(),
                        onPanCancel: endDrag,
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
      },
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
          onPanStart: (_) => setState(() => _isOverlayDragging = true),
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
          onPanEnd: (_) => setState(() => _isOverlayDragging = false),
          onPanCancel: () => setState(() => _isOverlayDragging = false),
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

  static const List<int> _stickyPastelColors = [
    0xFFFEF08A, // Vàng
    0xFFFBCFE8, // Hồng
    0xFFBBF7D0, // Xanh lá
    0xFFBAE6FD, // Xanh dương
    0xFFDDD6FE, // Tím
  ];

  Future<void> _editStickyNoteTitle(
    NotePage page,
    StickyNoteElement note,
  ) async {
    final ctrl = TextEditingController(text: note.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tiêu đề giấy nhớ'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Nhập tiêu đề ngắn (tùy chọn)...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    final updated = page.stickyNotes
        .map((s) => s.id == note.id
            ? s.copyWith(text: result, updatedAt: DateTime.now())
            : s)
        .toList();
    _commitPage(page.copyWith(stickyNotes: updated), undoSnapshot: page);
  }

  Widget _buildStickyNoteOverlay(
    NotePage page,
    StickyNoteElement note,
    bool readOnly,
  ) {
    final bgColor = Color(note.colorValue);
    final headerColor = Color.lerp(bgColor, Colors.black, 0.08) ?? bgColor;

    void commitSticky(StickyNoteElement Function(StickyNoteElement s) fn) {
      final updated = page.stickyNotes
          .map((s) => s.id == note.id ? fn(s) : s)
          .toList();
      _commitPage(
        page.copyWith(stickyNotes: updated),
        undoSnapshot: page,
      );
    }

    void beginStickyDrag() {
      _stickyDragNotifier.value = (
        id: note.id,
        x: note.x,
        y: note.y,
        w: note.width,
        h: note.height,
      );
      if (!_isOverlayDragging) {
        setState(() => _isOverlayDragging = true);
      }
    }

    void updateStickyDrag(
      ({String id, double x, double y, double w, double h}) Function(
        ({String id, double x, double y, double w, double h}) cur,
      ) transform,
    ) {
      final cur = _stickyDragNotifier.value ??
          (id: note.id, x: note.x, y: note.y, w: note.width, h: note.height);
      if (cur.id != note.id) return;
      _stickyDragNotifier.value = transform(cur);
    }

    void endStickyDrag() {
      final finalDrag = _stickyDragNotifier.value;
      _stickyDragNotifier.value = null;
      if (finalDrag != null && finalDrag.id == note.id) {
        commitSticky(
          (s) => s.copyWith(
            x: finalDrag.x,
            y: finalDrag.y,
            width: finalDrag.w,
            height: finalDrag.h,
            updatedAt: DateTime.now(),
          ),
        );
      }
      if (_isOverlayDragging) {
        setState(() => _isOverlayDragging = false);
      }
    }

    ToolType stickyToolType() {
      switch (_activeTool) {
        case EditorTool.ballpointPen:
          return ToolType.ballpointPen;
        case EditorTool.pencil:
          return ToolType.pencil;
        case EditorTool.brushPen:
          return ToolType.brushPen;
        case EditorTool.highlighter:
          return ToolType.highlighter;
        default:
          return ToolType.fountainPen;
      }
    }

    int stickyInkColorValue() {
      if (_activeTool == EditorTool.highlighter) {
        return _highlighterColor.value;
      }
      // Avoid invisible white ink on bright pastel sticky notes
      final c = _penColor;
      final lum = c.computeLuminance();
      if (lum > 0.88) return 0xFF1E293B;
      return c.value;
    }

    void eraseStickyAt(Offset localPos) {
      final remaining = note.strokes
          .where((s) => !StrokeEngine.hitTestStroke(s, localPos, tolerance: 14.0))
          .toList();
      if (remaining.length != note.strokes.length) {
        commitSticky(
          (s) => s.copyWith(strokes: remaining, updatedAt: DateTime.now()),
        );
      }
    }

    final collapsedLabel = note.text.trim().isNotEmpty
        ? note.text.trim().split('\n').first
        : 'Ghi chú';

    return ValueListenableBuilder<
        ({String id, double x, double y, double w, double h})?>(
      valueListenable: _stickyDragNotifier,
      builder: (_, drag, __) {
        final bool draggingThis = drag != null && drag.id == note.id;
        final double x = draggingThis ? drag.x : note.x;
        final double y = draggingThis ? drag.y : note.y;
        final double w = draggingThis ? drag.w : note.width;
        final double h = draggingThis ? drag.h : note.height;

        return Positioned(
          left: x,
          top: y,
          child: Container(
            width: note.isCollapsed ? math.min(w, 210.0) : w,
            height: note.isCollapsed ? 40.0 : h,
            decoration: BoxDecoration(
              color: note.isTransparent ? bgColor.withAlpha(89) : bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.black.withAlpha(note.isTransparent ? 45 : 28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(note.isTransparent ? 20 : 42),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Drag Header Bar (zero-rebuild ValueNotifier drag)
                    GestureDetector(
                      onPanStart: readOnly ? null : (_) => beginStickyDrag(),
                      onPanUpdate: readOnly
                          ? null
                          : (d) => updateStickyDrag(
                                (c) => (
                                  id: c.id,
                                  x: c.x + d.delta.dx,
                                  y: c.y + d.delta.dy,
                                  w: c.w,
                                  h: c.h,
                                ),
                              ),
                      onPanEnd: readOnly ? null : (_) => endStickyDrag(),
                      onPanCancel: readOnly ? null : endStickyDrag,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: headerColor,
                          borderRadius: BorderRadius.vertical(
                            top: const Radius.circular(9),
                            bottom: note.isCollapsed
                                ? const Radius.circular(9)
                                : Radius.zero,
                          ),
                        ),
                        child: Row(
                          children: [
                            if (note.isCollapsed)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    collapsedLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF1E293B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                            else ...[
                              for (final cVal in _stickyPastelColors)
                                GestureDetector(
                                  onTap: readOnly
                                      ? null
                                      : () => commitSticky(
                                            (s) => s.copyWith(colorValue: cVal),
                                          ),
                                  child: Container(
                                    width: 13,
                                    height: 13,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Color(cVal),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: note.colorValue == cVal
                                            ? const Color(0xFF1E293B)
                                            : Colors.black26,
                                        width:
                                            note.colorValue == cVal ? 1.8 : 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              if (!readOnly)
                                Tooltip(
                                  message: note.isTransparent
                                      ? 'Tắt nền trong suốt'
                                      : 'Nền trong suốt',
                                  child: InkWell(
                                    onTap: () => commitSticky(
                                      (s) => s.copyWith(
                                        isTransparent: !s.isTransparent,
                                        updatedAt: DateTime.now(),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(3.5),
                                      child: Icon(
                                        Icons.opacity_outlined,
                                        size: 15,
                                        color: note.isTransparent
                                            ? EditorColors.activeBlue
                                            : const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ),
                              if (!readOnly)
                                Tooltip(
                                  message: 'Tiêu đề',
                                  child: InkWell(
                                    onTap: () =>
                                        _editStickyNoteTitle(page, note),
                                    child: const Padding(
                                      padding: EdgeInsets.all(3.5),
                                      child: Icon(
                                        Icons.title_rounded,
                                        size: 15,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ),
                              if (!readOnly && note.strokes.isNotEmpty)
                                Tooltip(
                                  message: 'Xóa nét viết',
                                  child: InkWell(
                                    onTap: () => commitSticky(
                                      (s) => s.copyWith(
                                        strokes: const [],
                                        updatedAt: DateTime.now(),
                                      ),
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.all(3.5),
                                      child: Icon(
                                        Icons.cleaning_services_outlined,
                                        size: 14,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                            InkWell(
                              onTap: () => commitSticky(
                                (s) => s.copyWith(isCollapsed: !s.isCollapsed),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(3.5),
                                child: Icon(
                                  note.isCollapsed
                                      ? Icons.unfold_more_rounded
                                      : Icons.unfold_less_rounded,
                                  size: 16,
                                  color: const Color(0xFF334155),
                                ),
                              ),
                            ),
                            if (!readOnly)
                              InkWell(
                                onTap: () {
                                  _stickyControllers
                                      .remove(note.id)
                                      ?.dispose();
                                  final updated = page.stickyNotes
                                      .where((s) => s.id != note.id)
                                      .toList();
                                  _commitPage(
                                    page.copyWith(stickyNotes: updated),
                                    undoSnapshot: page,
                                  );
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(3.5),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 15,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // 144fps Direct M-Pencil 3 Handwriting Canvas Body
                    if (!note.isCollapsed)
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(9),
                          ),
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (e) {
                              if (readOnly || !_palmFilter.shouldAccept(e)) {
                                return;
                              }
                              if (!_isOverlayDragging) {
                                setState(() => _isOverlayDragging = true);
                              }
                              if (_activeTool == EditorTool.eraser) {
                                eraseStickyAt(e.localPosition);
                                return;
                              }
                              final rawP =
                                  (e.pressure > 0 && e.pressure <= 1.0)
                                      ? e.pressure
                                      : 0.55;
                              final pt = StrokePoint(
                                x: e.localPosition.dx,
                                y: e.localPosition.dy,
                                pressure: StrokeEngine.applyMPencilPressureCurve(
                                  rawP,
                                  gamma: _pressureGamma,
                                ),
                                tilt: e.tilt,
                                timestamp:
                                    DateTime.now().millisecondsSinceEpoch,
                              );
                              final width =
                                  _activeTool == EditorTool.highlighter
                                      ? _highlighterWidth * 0.7
                                      : _penWidth.clamp(1.2, 6.0);
                              _activeStickyStrokeNoteId = note.id;
                              _activeStickyStrokeNotifier.value = Stroke(
                                id: _uuid.v4(),
                                toolType: stickyToolType(),
                                colorValue: stickyInkColorValue(),
                                width: width,
                                points: [pt],
                              );
                            },
                            onPointerMove: (e) {
                              if (readOnly) return;
                              if (_activeTool == EditorTool.eraser &&
                                  _isOverlayDragging) {
                                eraseStickyAt(e.localPosition);
                                return;
                              }
                              final current = _activeStickyStrokeNotifier.value;
                              if (_activeStickyStrokeNoteId != note.id ||
                                  current == null) {
                                return;
                              }
                              final rawP =
                                  (e.pressure > 0 && e.pressure <= 1.0)
                                      ? e.pressure
                                      : 0.55;
                              final candidate = StrokePoint(
                                x: e.localPosition.dx,
                                y: e.localPosition.dy,
                                pressure: StrokeEngine.applyMPencilPressureCurve(
                                  rawP,
                                  gamma: _pressureGamma,
                                ),
                                tilt: e.tilt,
                                timestamp:
                                    DateTime.now().millisecondsSinceEpoch,
                              );
                              final filtered = StrokeEngine.filterLivePoint(
                                candidate,
                                current.points,
                                stabilization: _smoothingStrength * 0.65,
                              );
                              if (filtered != null) {
                                _activeStickyStrokeNotifier.value =
                                    current.copyWith(
                                  points: [...current.points, filtered],
                                );
                              }
                            },
                            onPointerUp: (_) {
                              final current = _activeStickyStrokeNotifier.value;
                              if (_activeStickyStrokeNoteId == note.id &&
                                  current != null) {
                                _activeStickyStrokeNotifier.value = null;
                                _activeStickyStrokeNoteId = null;
                                final smoothed =
                                    StrokeEngine.smoothAndNeatenStroke(
                                  current.points,
                                  stabilization: _smoothingStrength * 0.65,
                                  autoNeaten: _autoNeatenEnabled,
                                  toolType: current.toolType,
                                );
                                final finalStroke =
                                    current.copyWith(points: smoothed);
                                commitSticky(
                                  (s) => s.copyWith(
                                    strokes: [...s.strokes, finalStroke],
                                    updatedAt: DateTime.now(),
                                  ),
                                );
                              }
                              if (_isOverlayDragging) {
                                setState(() => _isOverlayDragging = false);
                              }
                            },
                            onPointerCancel: (_) {
                              if (_activeStickyStrokeNoteId == note.id) {
                                _activeStickyStrokeNotifier.value = null;
                                _activeStickyStrokeNoteId = null;
                              }
                              if (_isOverlayDragging) {
                                setState(() => _isOverlayDragging = false);
                              }
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (note.text.trim().isNotEmpty)
                                  Positioned(
                                    left: 8,
                                    right: 8,
                                    top: 4,
                                    child: IgnorePointer(
                                      child: Text(
                                        note.text.trim(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFF1E293B)
                                              .withAlpha(190),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (note.strokes.isEmpty &&
                                    note.text.trim().isEmpty)
                                  Center(
                                    child: IgnorePointer(
                                      child: Text(
                                        'Viết tay trực tiếp bằng bút...',
                                        style: TextStyle(
                                          color: const Color(0xFF475569)
                                              .withAlpha(140),
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ),
                                RepaintBoundary(
                                  child: CustomPaint(
                                    painter: _StickyCanvasPainter(
                                      strokes: note.strokes,
                                      activeStrokeNotifier:
                                          _activeStickyStrokeNotifier,
                                      noteId: note.id,
                                      getActiveNoteId: () =>
                                          _activeStickyStrokeNoteId,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // Bottom-Right Resize Handle (40x40 px stylus-friendly opaque hitbox)
                if (!note.isCollapsed && !readOnly)
                  Positioned(
                    right: -8,
                    bottom: -8,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => beginStickyDrag(),
                      onPanUpdate: (d) => updateStickyDrag(
                        (c) => (
                          id: c.id,
                          x: c.x,
                          y: c.y,
                          w: math.max(140.0, c.w + d.delta.dx),
                          h: math.max(110.0, c.h + d.delta.dy),
                        ),
                      ),
                      onPanEnd: (_) => endStickyDrag(),
                      onPanCancel: endStickyDrag,
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.drag_handle_rounded,
                          size: 15,
                          color: Colors.black.withAlpha(115),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Sleek 14x14 visual resize dot centered inside a 48x48 stylus-friendly hitbox.
  Widget _buildResizeHandle() {
    return SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: EditorColors.activeBlue, width: 2.2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 3),
            ],
          ),
        ),
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

/// Lightweight 144fps CustomPainter for handwritten strokes inside a Sticky Note.
class _StickyCanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final ValueNotifier<Stroke?> activeStrokeNotifier;
  final String noteId;
  final String? Function() getActiveNoteId;

  _StickyCanvasPainter({
    required this.strokes,
    required this.activeStrokeNotifier,
    required this.noteId,
    required this.getActiveNoteId,
  }) : super(repaint: activeStrokeNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Paint highlighters first so ink stays crisp on top
    for (final s in strokes) {
      if (s.toolType == ToolType.highlighter) {
        CanvasPainter.paintHighlighterStroke(
          canvas,
          s,
          isDarkPaper: false,
          isSelected: false,
        );
      }
    }
    for (final s in strokes) {
      if (s.toolType != ToolType.highlighter) {
        CanvasPainter.paintInkStroke(canvas, s, isSelected: false);
      }
    }

    // Live 144Hz stroke belonging to this sticky note
    final active = activeStrokeNotifier.value;
    if (active != null && getActiveNoteId() == noteId) {
      if (active.toolType == ToolType.highlighter) {
        CanvasPainter.paintHighlighterStroke(
          canvas,
          active,
          isDarkPaper: false,
          isSelected: false,
        );
      } else {
        CanvasPainter.paintInkStroke(canvas, active, isSelected: false);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StickyCanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.noteId != noteId;
  }
}

/// High-resolution live painter for the single selected/cropping [ImageElement]
/// inside `_buildImageOverlay` (while [CanvasPainter] hides `hiddenImageId`
/// to guarantee ZERO double-image ghosting during resize/drag/in-place crop).
class _SelectedImagePainter extends CustomPainter {
  final ui.Image image;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final List<StrokePoint> freehandClipPath;
  final Rect? dimOutsideRect;

  const _SelectedImagePainter({
    required this.image,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    this.freehandClipPath = const [],
    this.dimOutsideRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final src = Rect.fromLTRB(
      cropLeft.clamp(0.0, 0.99) * image.width,
      cropTop.clamp(0.0, 0.99) * image.height,
      cropRight.clamp(0.01, 1.0) * image.width,
      cropBottom.clamp(0.01, 1.0) * image.height,
    );

    canvas.save();
    if (freehandClipPath.length >= 3) {
      final path = Path()
        ..moveTo(
          freehandClipPath.first.x * size.width,
          freehandClipPath.first.y * size.height,
        );
      for (int i = 1; i < freehandClipPath.length; i++) {
        path.lineTo(
          freehandClipPath[i].x * size.width,
          freehandClipPath[i].y * size.height,
        );
      }
      path.close();
      canvas.clipPath(path);
    }

    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );

    // Optional dimmed outer veil for in-place on-canvas rectangular cropping
    if (dimOutsideRect != null) {
      final veil = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(dst)
        ..addRect(dimOutsideRect!);
      canvas.drawPath(
        veil,
        Paint()..color = Colors.black.withAlpha(120),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SelectedImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.cropLeft != cropLeft ||
        oldDelegate.cropTop != cropTop ||
        oldDelegate.cropRight != cropRight ||
        oldDelegate.cropBottom != cropBottom ||
        oldDelegate.freehandClipPath != freehandClipPath ||
        oldDelegate.dimOutsideRect != dimOutsideRect;
  }
}

/// Zero-lag, draggable & deletable Text Box overlay.
/// Owns its own [TextEditingController] & [FocusNode] so typing NEVER triggers
/// per-keystroke [AppState.updatePage] rebuilds (commits on focus loss,
/// editing complete, or 500ms debounce), while dragging & resizing run at 144fps
/// via a local [ValueNotifier].
class _DraggableTextBoxOverlay extends StatefulWidget {
  final TextElement element;
  final bool interactive;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<TextElement> onCommit;
  final VoidCallback onDelete;
  final Widget resizeHandle;

  const _DraggableTextBoxOverlay({
    super.key,
    required this.element,
    required this.interactive,
    required this.isSelected,
    required this.onSelect,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onCommit,
    required this.onDelete,
    required this.resizeHandle,
  });

  @override
  State<_DraggableTextBoxOverlay> createState() =>
      _DraggableTextBoxOverlayState();
}

class _DraggableTextBoxOverlayState extends State<_DraggableTextBoxOverlay> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  final ValueNotifier<({double x, double y, double w, double h})?> _dragNotifier =
      ValueNotifier(null);
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.element.text);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _DraggableTextBoxOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        widget.element.text != oldWidget.element.text &&
        _controller.text != widget.element.text) {
      _controller.text = widget.element.text;
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      widget.onSelect();
    } else {
      _debounceTimer?.cancel();
      _commitTextIfChanged();
    }
    if (mounted) setState(() {});
  }

  void _commitTextIfChanged() {
    if (_controller.text != widget.element.text) {
      widget.onCommit(widget.element.copyWith(text: _controller.text));
    }
  }

  void _scheduleDebounceCommit() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _commitTextIfChanged();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    _dragNotifier.dispose();
    super.dispose();
  }

  void _beginDrag() {
    widget.onSelect();
    _dragNotifier.value = (
      x: widget.element.x,
      y: widget.element.y,
      w: widget.element.width,
      h: widget.element.height,
    );
    widget.onDragStart();
  }

  void _endDrag() {
    final finalBox = _dragNotifier.value;
    _dragNotifier.value = null;
    if (finalBox != null) {
      widget.onCommit(
        widget.element.copyWith(
          x: finalBox.x,
          y: finalBox.y,
          width: finalBox.w,
          height: finalBox.h,
          text: _controller.text,
        ),
      );
    }
    widget.onDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    final bool showChrome = widget.isSelected || _focusNode.hasFocus;

    return ValueListenableBuilder<({double x, double y, double w, double h})?>(
      valueListenable: _dragNotifier,
      builder: (_, drag, __) {
        final double x = drag?.x ?? widget.element.x;
        final double y = drag?.y ?? widget.element.y;
        final double w = drag?.w ?? widget.element.width;
        final double h = drag?.h ?? widget.element.height;

        return Positioned(
          left: x,
          top: y,
          child: IgnorePointer(
            ignoring: !widget.interactive,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: w,
                  constraints: BoxConstraints(minHeight: h),
                  decoration: BoxDecoration(
                    color: _focusNode.hasFocus
                        ? Colors.white.withAlpha(230)
                        : Colors.transparent,
                    border: showChrome
                        ? Border.all(color: EditorColors.activeBlue, width: 1.5)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Crisp Top Drag Handle Bar + A- / A+ / Bold / Delete
                      if (showChrome)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) => _beginDrag(),
                          onPanUpdate: (d) {
                            final cur = _dragNotifier.value;
                            if (cur == null) return;
                            _dragNotifier.value = (
                              x: cur.x + d.delta.dx,
                              y: cur.y + d.delta.dy,
                              w: cur.w,
                              h: cur.h,
                            );
                          },
                          onPanEnd: (_) => _endDrag(),
                          onPanCancel: _endDrag,
                          child: Container(
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: const BoxDecoration(
                              color: EditorColors.obsidianSurface,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 15,
                                  color: Colors.white60,
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => widget.onCommit(
                                    widget.element.copyWith(
                                      text: _controller.text,
                                      fontSize: (widget.element.fontSize - 2.0)
                                          .clamp(10.0, 48.0),
                                    ),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'A-',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => widget.onCommit(
                                    widget.element.copyWith(
                                      text: _controller.text,
                                      fontSize: (widget.element.fontSize + 2.0)
                                          .clamp(10.0, 48.0),
                                    ),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'A+',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => widget.onCommit(
                                    widget.element.copyWith(
                                      text: _controller.text,
                                      isBold: !widget.element.isBold,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Icon(
                                      Icons.format_bold_rounded,
                                      size: 15,
                                      color: widget.element.isBold
                                          ? EditorColors.activeBlue
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                InkWell(
                                  onTap: widget.onDelete,
                                  child: const Padding(
                                    padding: EdgeInsets.all(3),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 15,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Zero-lag local TextField (commits on blur/debounce, never per-keystroke!)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          maxLines: null,
                          onTap: widget.onSelect,
                          onChanged: (_) => _scheduleDebounceCommit(),
                          onEditingComplete: () {
                            _debounceTimer?.cancel();
                            _commitTextIfChanged();
                            _focusNode.unfocus();
                          },
                          style: TextStyle(
                            fontSize: widget.element.fontSize,
                            color: Color(widget.element.colorValue),
                            fontWeight: widget.element.isBold
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontStyle: widget.element.isItalic
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            filled: false,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: 'Nhập văn bản / PTHH...',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Bottom-Right Resize Handle (40x40 stylus-friendly opaque hitbox)
                if (showChrome)
                  Positioned(
                    right: -20,
                    bottom: -20,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => _beginDrag(),
                      onPanUpdate: (d) {
                        final cur = _dragNotifier.value;
                        if (cur == null) return;
                        _dragNotifier.value = (
                          x: cur.x,
                          y: cur.y,
                          w: math.max(110.0, cur.w + d.delta.dx),
                          h: math.max(44.0, cur.h + d.delta.dy),
                        );
                      },
                      onPanEnd: (_) => _endDrag(),
                      onPanCancel: _endDrag,
                      child: widget.resizeHandle,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
