import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/drawing_elements.dart';
import '../models/folder.dart';
import '../models/note_page.dart';
import '../models/notebook.dart';
import '../services/hardware_service.dart';
import '../storage/local_storage_service.dart';

class BookmarkedPageRef {
  final Notebook notebook;
  final NotePage page;

  const BookmarkedPageRef({
    required this.notebook,
    required this.page,
  });
}

class SearchResult {
  final Notebook notebook;
  final NotePage? page;
  final String matchSnippet;
  final String matchSource;

  const SearchResult({
    required this.notebook,
    this.page,
    required this.matchSnippet,
    required this.matchSource,
  });
}

class AppState extends ChangeNotifier {
  final LocalStorageService _storage;
  final Uuid _uuid;

  List<Folder> _folders = [];
  List<Notebook> _notebooks = [];
  final List<String> _openNotebookIds = [];
  bool _isLoading = false;

  // Mặc định Obsidian Dark theo phong cách Huawei Notes × GoodNotes 6
  ThemeMode _themeMode = ThemeMode.dark;

  // Danh sách bút ưa thích BẮT ĐẦU TRỐNG — chỉ chứa các bút do người dùng tự ghim bằng nút Sao (★)
  List<PenPreset> _favoritePens = [];
  bool _showFavoritesBar = true;

  // Danh sách đường dẫn hình dán tùy chỉnh được thêm từ ảnh đã cắt ("Thêm vào hình dán")
  List<String> _customStickers = [];

  // Danh sách ảnh bìa cá nhân do người dùng thêm trong "TÙY CHỈNH"
  List<String> _customCoverPaths = [];

  // Danh sách đường dẫn ảnh chèn gần đây ("Ảnh gần đây" trong Image Popover)
  List<String> _recentImagePaths = [];

  // Chế độ Khoá lòng bàn tay (Chống tỳ tay: Bút viết, 1 ngón tay cuộn trang)
  bool _palmRejectionEnabled = true;

  // Chế độ Chỉ đọc (Read-Only): khóa toàn bộ thao tác viết để xem bài an toàn
  bool _readOnlyMode = false;

  // Tùy chọn trình ghi chú (Huawei Notes × GoodNotes 6 + MatePad 11.5"S)
  bool _verticalContinuousScroll = true;
  bool _freePaperMovement = true;
  bool _zoomAdaptiveStroke = false;
  bool _doubleTapToZoom = true;
  bool _quickGesturesEnabled = true;
  bool _mPencilDoubleTapEraser = true;
  bool _keepScreenAwake = false;
  bool _scribbleToErase = false;
  bool _holdToSnapShape = true;

  /// Hook tùy chọn để SyncManager đồng bộ khi sổ tay thay đổi hoặc bị xóa.
  Future<void> Function(Notebook notebook)? onNotebookChangedForSync;
  Future<void> Function(String notebookId)? onNotebookDeletedForSync;

  AppState({
    LocalStorageService? storage,
    Uuid? uuid,
  })  : _storage = storage ?? LocalStorageService(),
        _uuid = uuid ?? const Uuid();

  LocalStorageService get storage => _storage;
  List<Folder> get folders => List.unmodifiable(_folders);
  List<Notebook> get notebooks => List.unmodifiable(_notebooks);
  List<Notebook> get activeNotebooks =>
      List.unmodifiable(_notebooks.where((n) => !n.isTrashed));
  List<Notebook> get favoriteNotebooks => List.unmodifiable(
        _notebooks.where((n) => !n.isTrashed && n.isFavorite),
      );
  List<Notebook> get lockedNotebooks => List.unmodifiable(
        _notebooks.where((n) => !n.isTrashed && n.isLocked),
      );
  List<Notebook> get trashedNotebooks =>
      List.unmodifiable(_notebooks.where((n) => n.isTrashed));

  List<String> get openNotebookIds => List.unmodifiable(_openNotebookIds);
  List<Notebook> get openNotebooks {
    final result = <Notebook>[];
    for (final id in _openNotebookIds) {
      final nb = getNotebookById(id);
      if (nb != null && !nb.isTrashed) {
        result.add(nb);
      }
    }
    return List.unmodifiable(result);
  }

  List<PenPreset> get favoritePens => List.unmodifiable(_favoritePens);
  bool get showFavoritesBar => _showFavoritesBar;
  List<String> get customStickers => List.unmodifiable(_customStickers);
  List<String> get customCoverPaths => List.unmodifiable(_customCoverPaths);
  List<String> get recentImagePaths => List.unmodifiable(_recentImagePaths);
  bool get palmRejectionEnabled => _palmRejectionEnabled;
  bool get readOnlyMode => _readOnlyMode;

  bool get isLoading => _isLoading;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  bool get verticalContinuousScroll => _verticalContinuousScroll;
  bool get freePaperMovement => _freePaperMovement;
  bool get zoomAdaptiveStroke => _zoomAdaptiveStroke;
  bool get doubleTapToZoom => _doubleTapToZoom;
  bool get quickGesturesEnabled => _quickGesturesEnabled;
  bool get mPencilDoubleTapEraser => _mPencilDoubleTapEraser;
  bool get keepScreenAwake => _keepScreenAwake;
  bool get scribbleToErase => _scribbleToErase;
  bool get holdToSnapShape => _holdToSnapShape;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  void setDarkMode(bool dark) {
    setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  }

  void toggleTheme() {
    _themeMode =
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void setShowFavoritesBar(bool value) {
    if (_showFavoritesBar == value) return;
    _showFavoritesBar = value;
    notifyListeners();
  }

  void setPalmRejectionEnabled(bool value) {
    if (_palmRejectionEnabled == value) return;
    _palmRejectionEnabled = value;
    notifyListeners();
  }

  void togglePalmRejection() {
    _palmRejectionEnabled = !_palmRejectionEnabled;
    notifyListeners();
  }

  void setReadOnlyMode(bool value) {
    if (_readOnlyMode == value) return;
    _readOnlyMode = value;
    notifyListeners();
  }

  void toggleReadOnlyMode() {
    _readOnlyMode = !_readOnlyMode;
    notifyListeners();
  }

  /// Băm mã PIN bằng SHA-256 thuần Dart (FIPS 180-4, không phụ thuộc gói ngoài).
  static String hashPin(String pin) {
    final trimmed = pin.trim();
    if (trimmed.startsWith('sha256_')) return trimmed;
    return 'sha256_${_sha256Hex('chemnote_pin_v3:$trimmed')}';
  }

  /// Xác thực mã PIN (tương thích ngược với mã PIN thuần cũ như '1234' hoặc '0000').
  static bool verifyPin(String input, String? storedPin) {
    final candidate = input.trim();
    final expected = (storedPin ?? '0000').trim();
    if (expected.startsWith('sha256_')) {
      return hashPin(candidate) == expected;
    }
    return candidate == expected;
  }

  static String _sha256Hex(String input) {
    const k = <int>[
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
      0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
      0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
      0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
      0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
      0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    int h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    int h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

    final bytes = utf8.encode(input);
    final bitLen = bytes.length * 8;
    final paddedLen = ((bytes.length + 9 + 63) ~/ 64) * 64;
    final msg = Uint8List(paddedLen);
    msg.setRange(0, bytes.length, bytes);
    msg[bytes.length] = 0x80;
    final bd = ByteData.sublistView(msg);
    bd.setUint32(paddedLen - 8, (bitLen ~/ 0x100000000) & 0xffffffff);
    bd.setUint32(paddedLen - 4, bitLen & 0xffffffff);

    int rotr(int x, int n) => ((x & 0xffffffff) >> n) | ((x << (32 - n)) & 0xffffffff);

    final w = Uint32List(64);
    for (int offset = 0; offset < paddedLen; offset += 64) {
      for (int i = 0; i < 16; i++) {
        w[i] = bd.getUint32(offset + i * 4);
      }
      for (int i = 16; i < 64; i++) {
        final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }
      int a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (int i = 0; i < 64; i++) {
        final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final temp1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
        final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;
        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }
      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    String hex8(int v) => (v & 0xffffffff).toRadixString(16).padLeft(8, '0');
    return '${hex8(h0)}${hex8(h1)}${hex8(h2)}${hex8(h3)}'
        '${hex8(h4)}${hex8(h5)}${hex8(h6)}${hex8(h7)}';
  }

  void addRecentImagePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    _recentImagePaths = [
      trimmed,
      ..._recentImagePaths.where((p) => p != trimmed),
    ];
    if (_recentImagePaths.length > 12) {
      _recentImagePaths = _recentImagePaths.sublist(0, 12);
    }
    notifyListeners();
  }

  void setVerticalContinuousScroll(bool value) {
    if (_verticalContinuousScroll == value) return;
    _verticalContinuousScroll = value;
    notifyListeners();
  }

  void setFreePaperMovement(bool value) {
    if (_freePaperMovement == value) return;
    _freePaperMovement = value;
    notifyListeners();
  }

  void setZoomAdaptiveStroke(bool value) {
    if (_zoomAdaptiveStroke == value) return;
    _zoomAdaptiveStroke = value;
    notifyListeners();
  }

  void setDoubleTapToZoom(bool value) {
    if (_doubleTapToZoom == value) return;
    _doubleTapToZoom = value;
    notifyListeners();
  }

  void setQuickGesturesEnabled(bool value) {
    if (_quickGesturesEnabled == value) return;
    _quickGesturesEnabled = value;
    notifyListeners();
  }

  void setMPencilDoubleTapEraser(bool value) {
    if (_mPencilDoubleTapEraser == value) return;
    _mPencilDoubleTapEraser = value;
    notifyListeners();
  }

  Future<void> setKeepScreenAwake(bool value) async {
    if (_keepScreenAwake == value) return;
    _keepScreenAwake = value;
    notifyListeners();
    await HardwareService.instance.setKeepScreenOn(value);
  }

  void setScribbleToErase(bool value) {
    if (_scribbleToErase == value) return;
    _scribbleToErase = value;
    notifyListeners();
  }

  void setHoldToSnapShape(bool value) {
    if (_holdToSnapShape == value) return;
    _holdToSnapShape = value;
    notifyListeners();
  }

  void openTab(String notebookId) {
    if (!_openNotebookIds.contains(notebookId)) {
      _openNotebookIds.add(notebookId);
      notifyListeners();
    }
  }

  void closeTab(String notebookId) {
    if (_openNotebookIds.remove(notebookId)) {
      notifyListeners();
    }
  }

  bool isPenStarred(
    ToolType toolType,
    int colorValue,
    double width, {
    double? opacity,
  }) {
    return _favoritePens.any(
      (p) =>
          p.toolType == toolType &&
          p.colorValue == colorValue &&
          (p.width - width).abs() < 0.25 &&
          (opacity == null || (p.opacity - opacity).abs() < 0.05),
    );
  }

  void toggleStarPen(PenPreset preset) {
    final existingIdx = _favoritePens.indexWhere(
      (p) =>
          p.id == preset.id ||
          (p.toolType == preset.toolType &&
              p.colorValue == preset.colorValue &&
              (p.width - preset.width).abs() < 0.25 &&
              (p.opacity - preset.opacity).abs() < 0.05),
    );
    if (existingIdx >= 0) {
      final updated = [..._favoritePens]..removeAt(existingIdx);
      _favoritePens = updated;
    } else {
      _favoritePens = [..._favoritePens, preset];
    }
    notifyListeners();
    unawaited(_storage.saveFavoritePens(_favoritePens));
  }

  void addFavoritePen(PenPreset preset) {
    _favoritePens = [..._favoritePens, preset];
    notifyListeners();
    unawaited(_storage.saveFavoritePens(_favoritePens));
  }

  void updateFavoritePen(PenPreset preset) {
    _favoritePens =
        _favoritePens.map((p) => p.id == preset.id ? preset : p).toList();
    notifyListeners();
    unawaited(_storage.saveFavoritePens(_favoritePens));
  }

  void removeFavoritePen(String presetId) {
    _favoritePens = _favoritePens.where((p) => p.id != presetId).toList();
    notifyListeners();
    unawaited(_storage.saveFavoritePens(_favoritePens));
  }

  void addCustomSticker(String path) {
    if (path.trim().isEmpty || _customStickers.contains(path)) return;
    _customStickers = [path, ..._customStickers];
    notifyListeners();
    unawaited(_storage.saveCustomStickers(_customStickers));
  }

  void removeCustomSticker(String path) {
    if (!_customStickers.contains(path)) return;
    _customStickers = _customStickers.where((p) => p != path).toList();
    notifyListeners();
    unawaited(_storage.saveCustomStickers(_customStickers));
  }

  void addCustomCoverPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    _customCoverPaths = [
      trimmed,
      ..._customCoverPaths.where((p) => p != trimmed),
    ];
    notifyListeners();
    unawaited(_storage.saveCustomCovers(_customCoverPaths));
  }

  void removeCustomCoverPath(String path) {
    if (!_customCoverPaths.contains(path)) return;
    _customCoverPaths = _customCoverPaths.where((p) => p != path).toList();
    notifyListeners();
    unawaited(_storage.saveCustomCovers(_customCoverPaths));
  }

  Future<void> loadAll() async {
    _isLoading = true;
    notifyListeners();
    try {
      _folders = await _storage.loadFolders();
      _notebooks = await _storage.loadNotebooks();
      _favoritePens = await _storage.loadFavoritePens();
      _customStickers = await _storage.loadCustomStickers();
      _customCoverPaths = await _storage.loadCustomCovers();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<Folder> getSubfolders(String? parentId) {
    final result = _folders.where((f) => f.parentId == parentId).toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Folder? getFolderById(String id) {
    for (final folder in _folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  List<Notebook> getNotebooksInFolder(String? folderId) {
    final result = _notebooks
        .where((n) => !n.isTrashed && n.folderId == folderId)
        .toList();
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Notebook? getNotebookById(String id) {
    for (final notebook in _notebooks) {
      if (notebook.id == id) return notebook;
    }
    return null;
  }

  Future<Folder> createFolder({
    required String name,
    String? parentId,
    int colorValue = 0xFF3B82F6,
    String iconName = 'folder',
  }) async {
    final now = DateTime.now();
    final folder = Folder(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? 'Thư mục mới' : name.trim(),
      parentId: parentId,
      colorValue: colorValue,
      iconName: iconName,
      createdAt: now,
      updatedAt: now,
    );
    _folders = [..._folders, folder];
    await _storage.saveFolders(_folders);
    notifyListeners();
    return folder;
  }

  Future<void> updateFolder(Folder folder) async {
    final updated = folder.copyWith(updatedAt: DateTime.now());
    _folders = _folders.map((f) => f.id == updated.id ? updated : f).toList();
    await _storage.saveFolders(_folders);
    notifyListeners();
  }

  Future<void> deleteFolder(String folderId) async {
    _folders = _folders.where((f) => f.id != folderId).map((f) {
      if (f.parentId == folderId) {
        return f.copyWith(clearParentId: true, updatedAt: DateTime.now());
      }
      return f;
    }).toList();

    final affectedNotebooks = <Notebook>[];
    _notebooks = _notebooks.map((n) {
      if (n.folderId == folderId) {
        final moved = n.copyWith(
          clearFolderId: true,
          updatedAt: DateTime.now(),
        );
        affectedNotebooks.add(moved);
        return moved;
      }
      return n;
    }).toList();

    await _storage.saveFolders(_folders);
    for (final nb in affectedNotebooks) {
      await _storage.saveNotebook(nb);
    }
    notifyListeners();
  }

  Future<Notebook> createNotebook({
    required String title,
    String? folderId,
    String coverStyle = 'molecular',
    int coverColorValue = 0xFF1E3A5F,
    PaperTemplateType defaultTemplate = PaperTemplateType.sageRibbon,
    PaperColorType defaultPaperColor = PaperColorType.cream,
    bool defaultOrientationLandscape = false,
    bool isWhiteboard = false,
    String? customCoverImagePath,
    bool useFirstPageAsCover = false,
    List<NotePage>? initialPages,
  }) async {
    final now = DateTime.now();
    final pages = initialPages ??
        [
          NotePage(
            id: _uuid.v4(),
            index: 0,
            templateType: defaultTemplate,
            paperColor: defaultPaperColor,
            isLandscape: defaultOrientationLandscape,
            isInfiniteWhiteboard: isWhiteboard,
            updatedAt: now,
          ),
        ];

    final notebook = Notebook(
      id: _uuid.v4(),
      title: title.trim().isEmpty ? 'Sổ tay mới' : title.trim(),
      folderId: folderId,
      coverStyle: coverStyle,
      coverColorValue: coverColorValue,
      defaultTemplate: defaultTemplate,
      defaultPaperColor: defaultPaperColor,
      defaultOrientationLandscape: defaultOrientationLandscape,
      isWhiteboard: isWhiteboard,
      customCoverImagePath: customCoverImagePath,
      useFirstPageAsCover: useFirstPageAsCover,
      pages: pages,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.pendingUpload,
    );

    _notebooks = [notebook, ..._notebooks];
    await _storage.saveNotebook(notebook);
    notifyListeners();
    onNotebookChangedForSync?.call(notebook);
    return notebook;
  }

  Future<void> updateNotebook(
    Notebook notebook, {
    bool markPendingSync = true,
  }) async {
    final updated = notebook.copyWith(
      updatedAt: DateTime.now(),
      syncStatus: markPendingSync && notebook.syncStatus != SyncStatus.localOnly
          ? SyncStatus.pendingUpload
          : notebook.syncStatus,
    );
    final exists = _notebooks.any((n) => n.id == updated.id);
    if (exists) {
      _notebooks =
          _notebooks.map((n) => n.id == updated.id ? updated : n).toList();
    } else {
      _notebooks = [updated, ..._notebooks];
    }
    _notebooks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _storage.saveNotebook(updated);
    notifyListeners();
    if (markPendingSync) {
      onNotebookChangedForSync?.call(updated);
    }
  }

  Future<void> deleteNotebook(String notebookId) async {
    _openNotebookIds.remove(notebookId);
    _notebooks = _notebooks.where((n) => n.id != notebookId).toList();
    await _storage.deleteNotebookFile(notebookId);
    notifyListeners();
    onNotebookDeletedForSync?.call(notebookId);
  }

  Future<void> toggleFavorite(String notebookId) async {
    final nb = getNotebookById(notebookId);
    if (nb == null) return;
    await updateNotebook(nb.copyWith(isFavorite: !nb.isFavorite));
  }

  Future<void> setNotebookLock(
    String notebookId, {
    required bool isLocked,
    String? pinCode,
  }) async {
    final nb = getNotebookById(notebookId);
    if (nb == null) return;
    final hashedPin = pinCode != null
        ? hashPin(pinCode)
        : (nb.pinCode != null ? hashPin(nb.pinCode!) : hashPin('0000'));
    final updated = isLocked
        ? nb.copyWith(isLocked: true, pinCode: hashedPin)
        : nb.copyWith(isLocked: false, clearPinCode: true);
    await updateNotebook(updated);
  }

  Future<void> moveToTrash(String notebookId) async {
    final nb = getNotebookById(notebookId);
    if (nb == null) return;
    _openNotebookIds.remove(notebookId);
    await updateNotebook(
      nb.copyWith(isTrashed: true, trashedAt: DateTime.now()),
    );
  }

  Future<void> restoreFromTrash(String notebookId) async {
    final nb = getNotebookById(notebookId);
    if (nb == null) return;
    await updateNotebook(
      nb.copyWith(isTrashed: false, clearTrashedAt: true),
    );
  }

  Future<void> emptyTrash() async {
    final trashedIds =
        _notebooks.where((n) => n.isTrashed).map((n) => n.id).toList();
    for (final id in trashedIds) {
      await deleteNotebook(id);
    }
  }

  Future<void> moveNotebook(String notebookId, String? targetFolderId) async {
    final notebook = getNotebookById(notebookId);
    if (notebook == null) return;
    final updated = targetFolderId == null
        ? notebook.copyWith(clearFolderId: true)
        : notebook.copyWith(folderId: targetFolderId);
    await updateNotebook(updated);
  }

  Future<void> upsertNotebookFromSync(Notebook remoteNotebook) async {
    final synced = remoteNotebook.copyWith(syncStatus: SyncStatus.synced);
    final exists = _notebooks.any((n) => n.id == synced.id);
    if (exists) {
      _notebooks =
          _notebooks.map((n) => n.id == synced.id ? synced : n).toList();
    } else {
      _notebooks = [synced, ..._notebooks];
    }
    _notebooks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _storage.saveNotebook(synced);
    notifyListeners();
  }

  Future<void> updateNotebookSyncStatus(
    String notebookId,
    SyncStatus status, {
    String? driveFileId,
  }) async {
    final notebook = getNotebookById(notebookId);
    if (notebook == null) return;
    final updated = notebook.copyWith(
      syncStatus: status,
      driveFileId: driveFileId ?? notebook.driveFileId,
    );
    _notebooks =
        _notebooks.map((n) => n.id == notebookId ? updated : n).toList();
    await _storage.saveNotebook(updated);
    notifyListeners();
  }

  Future<NotePage?> addPage(
    String notebookId, {
    PaperTemplateType? templateType,
    PaperColorType? paperColor,
    bool? isLandscape,
    bool? isInfiniteWhiteboard,
    String? pdfBackgroundPath,
    int? pdfPageNumber,
    String? title,
    int? insertAfterIndex,
  }) async {
    final notebook = getNotebookById(notebookId);
    if (notebook == null) return null;
    final now = DateTime.now();
    final targetIndex = insertAfterIndex != null
        ? (insertAfterIndex + 1).clamp(0, notebook.pages.length)
        : notebook.pages.length;

    final page = NotePage(
      id: _uuid.v4(),
      index: targetIndex,
      templateType: templateType ?? notebook.defaultTemplate,
      paperColor: paperColor ?? notebook.defaultPaperColor,
      isLandscape: isLandscape ?? notebook.defaultOrientationLandscape,
      isInfiniteWhiteboard: isInfiniteWhiteboard ?? notebook.isWhiteboard,
      pdfBackgroundPath: pdfBackgroundPath,
      pdfPageNumber: pdfPageNumber,
      title: title,
      updatedAt: now,
    );

    final updatedPages = [...notebook.pages]..insert(targetIndex, page);
    final reindexed = [
      for (int i = 0; i < updatedPages.length; i++)
        updatedPages[i].copyWith(index: i)
    ];

    final updatedNotebook = notebook.copyWith(
      pages: reindexed,
      updatedAt: now,
    );
    await updateNotebook(updatedNotebook);
    return reindexed[targetIndex];
  }

  Future<void> updatePage(String notebookId, NotePage page) async {
    final notebook = getNotebookById(notebookId);
    if (notebook == null) return;
    final updatedPage = page.copyWith(updatedAt: DateTime.now());
    final pages = notebook.pages
        .map((p) => p.id == updatedPage.id ? updatedPage : p)
        .toList();
    await updateNotebook(notebook.copyWith(pages: pages));
  }

  Future<void> deletePage(String notebookId, String pageId) async {
    final notebook = getNotebookById(notebookId);
    if (notebook == null || notebook.pages.length <= 1) return;
    final remaining = notebook.pages.where((p) => p.id != pageId).toList();
    final reindexed = [
      for (int i = 0; i < remaining.length; i++) remaining[i].copyWith(index: i)
    ];
    await updateNotebook(notebook.copyWith(pages: reindexed));
  }

  Future<void> toggleBookmark(String notebookId, String pageId) async {
    final notebook = getNotebookById(notebookId);
    if (notebook == null) return;
    final pages = notebook.pages.map((p) {
      if (p.id == pageId) {
        return p.copyWith(
          isBookmarked: !p.isBookmarked,
          updatedAt: DateTime.now(),
        );
      }
      return p;
    }).toList();
    await updateNotebook(notebook.copyWith(pages: pages));
  }

  Future<void> reorderPages(
    String notebookId,
    int oldIndex,
    int newIndex,
  ) async {
    final notebook = getNotebookById(notebookId);
    if (notebook == null) return;
    if (oldIndex < 0 ||
        oldIndex >= notebook.pages.length ||
        newIndex < 0 ||
        newIndex >= notebook.pages.length) {
      return;
    }
    final list = [...notebook.pages];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    final reindexed = [
      for (int i = 0; i < list.length; i++) list[i].copyWith(index: i)
    ];
    await updateNotebook(notebook.copyWith(pages: reindexed));
  }

  List<BookmarkedPageRef> get bookmarkedPages {
    final refs = <BookmarkedPageRef>[];
    for (final notebook in _notebooks) {
      if (notebook.isTrashed) continue;
      for (final page in notebook.pages) {
        if (page.isBookmarked) {
          refs.add(BookmarkedPageRef(notebook: notebook, page: page));
        }
      }
    }
    refs.sort((a, b) => b.page.updatedAt.compareTo(a.page.updatedAt));
    return refs;
  }

  List<SearchResult> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return [];

    final results = <SearchResult>[];
    for (final notebook in _notebooks) {
      if (notebook.isTrashed) continue;
      if (notebook.title.toLowerCase().contains(normalized)) {
        results.add(
          SearchResult(
            notebook: notebook,
            matchSnippet: notebook.title,
            matchSource: 'Tên sổ tay',
          ),
        );
      }

      for (final page in notebook.pages) {
        if (page.title != null &&
            page.title!.toLowerCase().contains(normalized)) {
          results.add(
            SearchResult(
              notebook: notebook,
              page: page,
              matchSnippet: page.title!,
              matchSource: 'Tiêu đề trang ${page.index + 1}',
            ),
          );
        }

        for (final textEl in page.textElements) {
          if (textEl.text.toLowerCase().contains(normalized)) {
            results.add(
              SearchResult(
                notebook: notebook,
                page: page,
                matchSnippet: textEl.text.trim(),
                matchSource: 'Nội dung trang ${page.index + 1}',
              ),
            );
            break;
          }
        }
      }
    }
    return results;
  }
}
