import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/drawing_elements.dart';
import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../core/providers/app_state.dart';
import '../pdf/pdf_export_service.dart';
import 'google_auth_service.dart';
import 'google_drive_service.dart';

/// Một mục nhật ký hoạt động đồng bộ Google Drive.
class SyncLogEntry {
  const SyncLogEntry({
    required this.timestamp,
    required this.message,
    this.isError = false,
  });

  final DateTime timestamp;
  final String message;
  final bool isError;
}

/// Kết quả xử lý xung đột giữa bản cục bộ và bản trên Google Drive.
enum ConflictWinner {
  local,
  remote,
  equal,
}

class ConflictResolutionResult {
  const ConflictResolutionResult({
    required this.winner,
    required this.resolvedNotebook,
    this.conflictBackupCopy,
  });

  final ConflictWinner winner;
  final Notebook resolvedNotebook;

  /// Bản sao dự phòng được tạo ra khi cả hai phía đều thay đổi sau lần đồng bộ gần nhất.
  final Notebook? conflictBackupCopy;
}

/// Trình quản lý đồng bộ ngoại tuyến ưu tiên cục bộ (offline-first) với Google Drive.
/// - Sao lưu kép vào 2 thư mục trên Drive: `ChemNote_Backups/JSON/` và `ChemNote_Backups/PDF/` (PDF vector nhẹ).
/// - Lịch đồng bộ tiết kiệm pin: chu kỳ khi đang mở app (`foregroundSyncMinutes`),
///   nhắc đồng bộ dài hạn (`idleSyncDays`), và tùy chọn chỉ đồng bộ qua Wi-Fi (`wifiOnlySync`).
class SyncManager extends ChangeNotifier {
  SyncManager({
    AppState? appState,
    GoogleAuthService? authService,
    GoogleDriveService? driveService,
    PdfExportService? pdfExportService,
    FlutterSecureStorage? secureStorage,
    Connectivity? connectivity,
    Uuid? uuid,
    this.debounceDuration = const Duration(seconds: 45),
    bool attachConnectivityListener = true,
  })  : _appState = appState,
        _authService = authService ?? GoogleAuthService(),
        _pdfExportService = pdfExportService ?? PdfExportService(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _connectivity = connectivity ?? Connectivity(),
        _uuid = uuid ?? const Uuid(),
        _attachConnectivityListener = attachConnectivityListener {
    _driveService =
        driveService ?? GoogleDriveService(authService: _authService);
    if (_appState != null) {
      attachAppState(_appState!);
    }
  }

  static const String _kLastSyncedAt = 'chemnote_last_synced_at';
  static const String _kPendingDeleteNotebookIds =
      'chemnote_pending_delete_notebook_ids';

  /// Ngưỡng số trang tối đa cho phép tự động xuất PDF khi đồng bộ nền (tránh nóng máy trên Kirin).
  static const int maxBackgroundPdfPages = 30;

  AppState? _appState;
  final GoogleAuthService _authService;
  late final GoogleDriveService _driveService;
  final PdfExportService _pdfExportService;
  final FlutterSecureStorage _secureStorage;
  final Connectivity _connectivity;
  final Uuid _uuid;
  final Duration debounceDuration;
  final bool _attachConnectivityListener;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _debounceTimer;
  Timer? _foregroundTimer;

  bool _autoSyncEnabled = true;
  bool _isSyncing = false;
  bool _pendingPostSyncCleanup = false;
  int _followupDeleteDepth = 0;
  bool _isOnline = true;
  bool _isOnWifi = true;
  DateTime? _lastSyncedAt;
  String _statusMessage = 'Chưa kết nối Google Drive';

  // Giá trị dự phòng khi chạy độc lập không gắn AppState (ví dụ trong unit test).
  int _fallbackForegroundSyncMinutes = 15;
  int _fallbackIdleSyncDays = 1;
  bool _fallbackWifiOnlySync = true;
  bool _fallbackAutoExportPdfOnSync = true;

  final Set<String> _pendingUploadIds = <String>{};
  final Map<String, Notebook> _pendingSnapshots = <String, Notebook>{};
  final Set<String> _pendingDeleteDriveIds = <String>{};
  final Set<String> _pendingDeleteNotebookIds = <String>{};
  final Map<String, Set<String>> _pendingDeleteLegacyAssetKeys =
      <String, Set<String>>{};
  final List<SyncLogEntry> _syncLogs = <SyncLogEntry>[];

  GoogleAuthService get authService => _authService;
  GoogleDriveService get driveService => _driveService;
  AuthUser? get currentUser => _authService.currentUser;
  bool get isSignedIn => _authService.isSignedIn;
  bool get isDemoMode => _authService.isDemoMode;
  bool get autoSyncEnabled => _autoSyncEnabled;
  bool get isSyncing => _isSyncing;
  bool get isOnline => _isOnline;
  bool get isOnWifi => _isOnWifi;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String get statusMessage => _statusMessage;
  List<SyncLogEntry> get syncLogs => List.unmodifiable(_syncLogs);
  Set<String> get pendingUploadIds => Set.unmodifiable(_pendingUploadIds);
  Set<String> get pendingDeleteDriveIds =>
      Set.unmodifiable(_pendingDeleteDriveIds);
  Set<String> get pendingDeleteNotebookIds =>
      Set.unmodifiable(_pendingDeleteNotebookIds);

  /// Chu kỳ đồng bộ khi đang mở app (phút): `0` (thủ công), `5`, `15`, `45`, `120`.
  int get foregroundSyncMinutes =>
      _appState?.foregroundSyncMinutes ?? _fallbackForegroundSyncMinutes;

  /// Chu kỳ nhắc đồng bộ dài hạn khi quay lại app (ngày): `0` (tắt), `1`, `3`, `5`.
  int get idleSyncDays => _appState?.idleSyncDays ?? _fallbackIdleSyncDays;

  /// Chỉ tự động đồng bộ qua Wi-Fi để tiết kiệm pin & dữ liệu di động.
  bool get wifiOnlySync => _appState?.wifiOnlySync ?? _fallbackWifiOnlySync;

  /// Tự động xuất & tải lên bản PDF vector khi đồng bộ (tự bỏ qua sổ > 30 trang khi đồng bộ nền).
  bool get autoExportPdfOnSync =>
      _appState?.autoExportPdfOnSync ?? _fallbackAutoExportPdfOnSync;

  /// Kiểm tra điều kiện mạng hiện tại có cho phép tự động đồng bộ hay không.
  bool get canAutoSyncOnCurrentNetwork =>
      isDemoMode || (_isOnline && (!wifiOnlySync || _isOnWifi));

  /// Gắn `AppState` để tự động nhận sự kiện sửa/xóa sổ tay.
  void attachAppState(AppState appState) {
    _appState = appState;
    appState.onNotebookChangedForSync = (Notebook notebook) async {
      queueNotebookUpload(notebook);
    };
    appState.onNotebookDeletedForSync = (String notebookId) async {
      queueNotebookDelete(notebookId);
    };
    appState.onNotebookPermanentlyDeletedForSync = (Notebook notebook) async {
      queueNotebookDelete(
        notebook.id,
        driveFileId: notebook.driveFileId,
        drivePdfFileId: notebook.drivePdfFileId,
        deletedNotebook: notebook,
      );
    };
  }

  /// Khởi tạo phiên đăng nhập đã lưu, khôi phục mốc `lastSyncedAt`, theo dõi mạng và lịch đồng bộ tiết kiệm pin.
  Future<void> initialize() async {
    await _authService.loadSavedSession();
    try {
      final savedSyncIso = await _secureStorage.read(key: _kLastSyncedAt);
      if (savedSyncIso != null && savedSyncIso.isNotEmpty) {
        _lastSyncedAt = DateTime.tryParse(savedSyncIso);
      }
      final savedDeletes =
          await _secureStorage.read(key: _kPendingDeleteNotebookIds);
      if (savedDeletes != null && savedDeletes.isNotEmpty) {
        _pendingDeleteNotebookIds.addAll(
          savedDeletes.split('\n').where((s) => s.isNotEmpty),
        );
      }
    } catch (_) {}

    if (_authService.isSignedIn) {
      _statusMessage = _authService.isDemoMode
          ? 'Đang dùng Chế độ Demo ngoại tuyến'
          : 'Đã kết nối: ${_authService.currentUser!.email}';
      _addLog(_statusMessage);
    }

    if (_attachConnectivityListener) {
      try {
        final results = await _connectivity.checkConnectivity();
        _updateNetworkState(results);
        _connectivitySub = _connectivity.onConnectivityChanged.listen(
          _onConnectivityChanged,
        );
      } catch (_) {
        _isOnline = true;
        _isOnWifi = true;
      }
    }

    // Đưa các sổ tay đang chờ tải lên vào hàng đợi.
    final notebooks = _appState?.notebooks ?? const <Notebook>[];
    for (final nb in notebooks) {
      if (nb.syncStatus == SyncStatus.pendingUpload) {
        _pendingUploadIds.add(nb.id);
        _pendingSnapshots[nb.id] = nb;
      }
    }

    _rescheduleForegroundTimer();
    notifyListeners();

    await onAppResumed();
  }

  /// Gọi khi khởi động hoặc quay lại ứng dụng: nếu quá hạn `idleSyncDays` ngày (hoặc còn hàng đợi),
  /// thực hiện một lần đồng bộ bù nhẹ nhàng (tôn trọng `wifiOnlySync`).
  Future<void> onAppResumed() async {
    if (!_autoSyncEnabled || !isSignedIn || _isSyncing) return;
    if (!canAutoSyncOnCurrentNetwork) return;

    final hasPending = _hasPendingChanges();
    final isIdleStale = idleSyncDays > 0 &&
        (_lastSyncedAt == null ||
            DateTime.now().difference(_lastSyncedAt!).inDays >= idleSyncDays);

    if (hasPending || isIdleStale) {
      if (isIdleStale && !hasPending) {
        _addLog('Kiểm tra đồng bộ định kỳ sau $idleSyncDays ngày.');
      }
      unawaited(syncNow());
    }
  }

  bool _hasPendingChanges() {
    if (_pendingUploadIds.isNotEmpty || _pendingDeleteDriveIds.isNotEmpty) {
      return true;
    }
    final notebooks = _appState?.notebooks;
    if (notebooks == null) return false;
    return notebooks.any((n) => n.syncStatus == SyncStatus.pendingUpload);
  }

  void _updateNetworkState(List<ConnectivityResult> results) {
    _isOnline = results.isNotEmpty &&
        results.any((r) => r != ConnectivityResult.none);
    _isOnWifi = results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final prevOnline = _isOnline;
    final prevWifi = _isOnWifi;
    _updateNetworkState(results);
    if (_isOnline == prevOnline && _isOnWifi == prevWifi) return;

    if (_isOnline) {
      _addLog(
        _isOnWifi
            ? 'Đã kết nối Wi-Fi.'
            : 'Đã kết nối mạng di động${wifiOnlySync ? ' (tạm hoãn tự đồng bộ do bật Chỉ Wi-Fi)' : ''}.',
      );
      if (_autoSyncEnabled &&
          isSignedIn &&
          canAutoSyncOnCurrentNetwork &&
          _hasPendingChanges()) {
        unawaited(syncNow());
      }
    } else {
      _statusMessage = 'Đang ngoại tuyến — thay đổi sẽ được xếp hàng đồng bộ';
      _addLog(_statusMessage);
    }
    notifyListeners();
  }

  /// Bật/tắt chế độ tự động đồng bộ khi có mạng.
  void setAutoSyncEnabled(bool enabled) {
    if (_autoSyncEnabled == enabled) return;
    _autoSyncEnabled = enabled;
    _rescheduleForegroundTimer();
    _addLog(enabled ? 'Đã bật tự động đồng bộ.' : 'Đã tắt tự động đồng bộ.');
    notifyListeners();
    if (enabled &&
        isSignedIn &&
        canAutoSyncOnCurrentNetwork &&
        _hasPendingChanges()) {
      unawaited(syncNow());
    }
  }

  /// Cập nhật chu kỳ đồng bộ khi đang mở app (phút: 0, 5, 15, 45, 120).
  void setForegroundSyncMinutes(int minutes) {
    _fallbackForegroundSyncMinutes = minutes;
    _appState?.setForegroundSyncMinutes(minutes);
    _rescheduleForegroundTimer();
    _addLog(
      minutes == 0
          ? 'Chế độ đồng bộ khi mở app: Thủ công.'
          : 'Chu kỳ đồng bộ khi mở app: mỗi $minutes phút.',
    );
    notifyListeners();
  }

  /// Cập nhật chu kỳ nhắc đồng bộ dài hạn (ngày: 0, 1, 3, 5).
  void setIdleSyncDays(int days) {
    _fallbackIdleSyncDays = days;
    _appState?.setIdleSyncDays(days);
    _addLog(
      days == 0
          ? 'Đã tắt chu kỳ nhắc đồng bộ dài hạn.'
          : 'Chu kỳ nhắc đồng bộ dài hạn: mỗi $days ngày.',
    );
    notifyListeners();
  }

  /// Cập nhật tùy chọn chỉ đồng bộ qua Wi-Fi.
  void setWifiOnlySync(bool wifiOnly) {
    _fallbackWifiOnlySync = wifiOnly;
    _appState?.setWifiOnlySync(wifiOnly);
    _addLog(
      wifiOnly
          ? 'Đã bật: Chỉ đồng bộ qua Wi-Fi (tiết kiệm pin & data).'
          : 'Đã cho phép đồng bộ qua cả Wi-Fi và mạng di động.',
    );
    notifyListeners();
    if (!wifiOnly &&
        _autoSyncEnabled &&
        isSignedIn &&
        _isOnline &&
        _hasPendingChanges()) {
      unawaited(syncNow());
    }
  }

  /// Bật/tắt tự động xuất PDF khi đồng bộ Google Drive.
  void setAutoExportPdfOnSync(bool enabled) {
    _fallbackAutoExportPdfOnSync = enabled;
    _appState?.setAutoExportPdfOnSync(enabled);
    _addLog(
      enabled
          ? 'Đã bật tự động xuất PDF khi đồng bộ (bỏ qua sổ > $maxBackgroundPdfPages trang khi đồng bộ nền).'
          : 'Đã tắt tự động xuất PDF khi đồng bộ (chỉ sao lưu JSON & tài nguyên).',
    );
    notifyListeners();
  }

  void _rescheduleForegroundTimer() {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;

    if (!_autoSyncEnabled || foregroundSyncMinutes <= 0) {
      return;
    }

    _foregroundTimer = Timer.periodic(
      Duration(minutes: foregroundSyncMinutes),
      (_) => _runScheduledForegroundSync(),
    );
  }

  void _runScheduledForegroundSync() {
    if (!_autoSyncEnabled || !isSignedIn || _isSyncing) return;
    if (!canAutoSyncOnCurrentNetwork) return;
    // Chỉ chạy khi thực sự có sổ tay đang chờ tải lên để tiết kiệm pin tuyệt đối.
    if (!_hasPendingChanges()) return;
    unawaited(syncNow());
  }

  /// Cập nhật trạng thái mạng thủ công (hữu ích cho kiểm thử đơn vị).
  void setOnlineStatusForTesting(bool online, {bool? isWifi}) {
    _isOnline = online;
    if (isWifi != null) {
      _isOnWifi = isWifi;
    } else {
      _isOnWifi = online;
    }
    notifyListeners();
  }

  /// Đăng nhập Google OAuth 2.0 + PKCE (không cần GMS).
  Future<AuthUser> signInWithGoogle() async {
    try {
      _statusMessage = 'Đang mở trình duyệt đăng nhập Google...';
      notifyListeners();

      final user = await _authService.signIn();
      _driveService.resetSessionCache();
      _statusMessage = 'Đã đăng nhập: ${user.email}';
      _addLog('Đăng nhập Google thành công (${user.email}).');
      _rescheduleForegroundTimer();
      notifyListeners();

      if (_autoSyncEnabled && canAutoSyncOnCurrentNetwork) {
        unawaited(syncNow());
      }
      return user;
    } catch (e) {
      _statusMessage = e.toString();
      _addLog('Đăng nhập Google thất bại: $e', isError: true);
      notifyListeners();
      rethrow;
    }
  }

  /// Kích hoạt Chế độ Demo để thử nghiệm đồng bộ khi chưa cấu hình Client ID.
  Future<AuthUser> signInDemoMode() async {
    final user = await _authService.signInDemo();
    _driveService.resetSessionCache();
    _statusMessage = 'Đã bật Chế độ Demo (${user.email})';
    _addLog('Đã kích hoạt Chế độ Demo Google Drive.');
    _rescheduleForegroundTimer();
    notifyListeners();
    return user;
  }

  /// Đăng xuất tài khoản Google Drive.
  Future<void> signOut() async {
    _debounceTimer?.cancel();
    _foregroundTimer?.cancel();
    await _authService.signOut();
    _driveService.resetSessionCache();
    _statusMessage = 'Đã đăng xuất khỏi Google Drive';
    _addLog(_statusMessage);
    notifyListeners();
  }

  /// Xếp hàng tải lên sổ tay sau khi chỉnh sửa mà KHÔNG kích hoạt đồng bộ/tạo PDF tức thì
  /// khi người dùng đang viết tay (tránh ANR & tiết kiệm pin; đợi chu kỳ `foregroundSyncMinutes`).
  void queueNotebookUpload(Notebook notebook) {
    final wasAlreadyPending = _pendingUploadIds.contains(notebook.id);
    _pendingUploadIds.add(notebook.id);
    _pendingSnapshots[notebook.id] = notebook;

    if (!_autoSyncEnabled || !isSignedIn) {
      if (!wasAlreadyPending) notifyListeners();
      return;
    }

    if (!_isOnline && !isDemoMode) {
      _statusMessage =
          'Đang ngoại tuyến — đã xếp hàng ${_pendingUploadIds.length} sổ tay';
      if (!wasAlreadyPending) notifyListeners();
      return;
    }

    if (wifiOnlySync && !_isOnWifi && !isDemoMode) {
      _statusMessage =
          'Đang chờ Wi-Fi — đã xếp hàng ${_pendingUploadIds.length} sổ tay';
      if (!wasAlreadyPending) notifyListeners();
      return;
    }

    // Nếu người dùng chọn chu kỳ thủ công (0), chỉ xếp hàng chờ bấm "Đồng bộ ngay".
    if (foregroundSyncMinutes == 0) {
      if (!wasAlreadyPending) notifyListeners();
      return;
    }

    // Đảm bảo bộ đếm chu kỳ tiết kiệm pin (`foregroundSyncMinutes`) đang chạy,
    // tuyệt đối không gọi `syncNow()` / dựng PDF giữa lúc đang viết tay!
    if (_foregroundTimer == null) {
      _rescheduleForegroundTimer();
    }

    if (!wasAlreadyPending) {
      notifyListeners();
    }
  }

  /// Xếp hàng xóa tệp sổ tay (JSON, PDF và thư mục Assets) trên Google Drive nếu đã từng đồng bộ.
  void queueNotebookDelete(
    String notebookId, {
    String? driveFileId,
    String? drivePdfFileId,
    Notebook? deletedNotebook,
  }) {
    _pendingUploadIds.remove(notebookId);
    final removed = _pendingSnapshots.remove(notebookId);
    _pendingDeleteNotebookIds.add(notebookId);
    if (_isSyncing) {
      _pendingPostSyncCleanup = true;
    }
    unawaited(_persistPendingDeleteNotebookIds());

    final targetJsonId =
        driveFileId ?? deletedNotebook?.driveFileId ?? removed?.driveFileId;
    final targetPdfId =
        drivePdfFileId ?? deletedNotebook?.drivePdfFileId ?? removed?.drivePdfFileId;
    if (targetJsonId != null && targetJsonId.isNotEmpty) {
      _pendingDeleteDriveIds.add(targetJsonId);
    }
    if (targetPdfId != null && targetPdfId.isNotEmpty) {
      _pendingDeleteDriveIds.add(targetPdfId);
    }
    if (deletedNotebook != null) {
      final keys = _pendingDeleteLegacyAssetKeys.putIfAbsent(
        notebookId,
        () => <String>{},
      );
      for (final page in deletedNotebook.pages) {
        final pdfBg = page.pdfBackgroundPath;
        if (pdfBg != null && pdfBg.isNotEmpty) {
          keys.add(remoteAssetKeyForPath(pdfBg, notebookId: notebookId));
        }
        for (final img in page.imageElements) {
          if (img.filePath.isNotEmpty) {
            keys.add(remoteAssetKeyForPath(img.filePath, notebookId: notebookId));
          }
        }
      }
    }

    if (_autoSyncEnabled &&
        isSignedIn &&
        canAutoSyncOnCurrentNetwork &&
        foregroundSyncMinutes > 0) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounceDuration, () {
        if (canAutoSyncOnCurrentNetwork) {
          unawaited(syncNow());
        }
      });
    }
    notifyListeners();
  }

  /// Giải quyết xung đột giữa bản cục bộ và bản trên Google Drive theo `updatedAt`.
  ConflictResolutionResult resolveConflict({
    required Notebook local,
    required Notebook remote,
    DateTime? lastSyncedAt,
  }) {
    final diffMs =
        local.updatedAt.difference(remote.updatedAt).inMilliseconds.abs();
    if (diffMs < 1000) {
      return ConflictResolutionResult(
        winner: ConflictWinner.equal,
        resolvedNotebook: local.copyWith(
          driveFileId: remote.driveFileId ?? local.driveFileId,
          drivePdfFileId: remote.drivePdfFileId ?? local.drivePdfFileId,
          syncStatus: SyncStatus.synced,
        ),
      );
    }

    final localIsNewer = local.updatedAt.isAfter(remote.updatedAt);
    final bool alreadyConflictCopy =
        local.title.contains('(Bản sao xung đột)') ||
        remote.title.contains('(Bản sao xung đột)');
    // Chỉ tạo bản sao xung đột khi CÓ mốc `lastSyncedAt` đã biết, cả hai phía đều sửa
    // sau mốc đó ít nhất 5 giây VÀ nội dung/tên thực sự khác nhau (tránh tạo bản sao thừa sau sự cố văng app).
    final bothChangedSinceLastSync = !alreadyConflictCopy &&
        lastSyncedAt != null &&
        local.updatedAt.isAfter(lastSyncedAt.add(const Duration(seconds: 5))) &&
        remote.updatedAt
            .isAfter(lastSyncedAt.add(const Duration(seconds: 5))) &&
        local.updatedAt != remote.updatedAt &&
        _hasMeaningfulDifference(local, remote);

    if (localIsNewer) {
      Notebook? backup;
      if (bothChangedSinceLastSync) {
        backup = remote.copyWith(
          id: _uuid.v4(),
          title: '${remote.title} (Bản sao xung đột)',
          clearDriveFileId: true,
          clearDrivePdfFileId: true,
          syncStatus: SyncStatus.pendingUpload,
          isTrashed: false,
          clearTrashedAt: true,
          updatedAt: DateTime.now(),
        );
      }
      return ConflictResolutionResult(
        winner: ConflictWinner.local,
        resolvedNotebook: local.copyWith(
          driveFileId: remote.driveFileId ?? local.driveFileId,
          drivePdfFileId: remote.drivePdfFileId ?? local.drivePdfFileId,
        ),
        conflictBackupCopy: backup,
      );
    } else {
      Notebook? backup;
      if (bothChangedSinceLastSync) {
        backup = local.copyWith(
          id: _uuid.v4(),
          title: '${local.title} (Bản sao xung đột)',
          clearDriveFileId: true,
          clearDrivePdfFileId: true,
          syncStatus: SyncStatus.pendingUpload,
          isTrashed: false,
          clearTrashedAt: true,
          updatedAt: DateTime.now(),
        );
      }
      return ConflictResolutionResult(
        winner: ConflictWinner.remote,
        resolvedNotebook: remote.copyWith(
          driveFileId: remote.driveFileId ?? local.driveFileId,
          drivePdfFileId: remote.drivePdfFileId ?? local.drivePdfFileId,
          syncStatus: SyncStatus.synced,
        ),
        conflictBackupCopy: backup,
      );
    }
  }

  bool _hasMeaningfulDifference(Notebook a, Notebook b) {
    if (a.title != b.title || a.isTrashed != b.isTrashed) return true;
    if (a.pages.length != b.pages.length) return true;
    for (int i = 0; i < a.pages.length; i++) {
      final pa = a.pages[i];
      final pb = b.pages[i];
      if (pa.id != pb.id ||
          pa.strokes.length != pb.strokes.length ||
          pa.imageElements.length != pb.imageElements.length ||
          pa.textElements.length != pb.textElements.length ||
          pa.stickyNotes.length != pb.stickyNotes.length ||
          pa.pdfBackgroundPath != pb.pdfBackgroundPath) {
        return true;
      }
      if (pa.strokes.isNotEmpty && pa.strokes.last.id != pb.strokes.last.id) {
        return true;
      }
    }
    return false;
  }

  /// Đồng bộ hai chiều ngay lập tức giữa máy và Google Drive (`JSON/`, `PDF/`, `Assets/`).
  Future<void> syncNow({bool isManualSync = false}) async {
    if (_isSyncing) return;

    if (!isSignedIn) {
      _statusMessage = 'Vui lòng đăng nhập Google Drive trước khi đồng bộ.';
      notifyListeners();
      return;
    }

    if (!_isOnline && !isDemoMode) {
      _statusMessage =
          'Không có kết nối mạng. Đã lưu ${_pendingUploadIds.length} sổ tay chờ đồng bộ.';
      _addLog(_statusMessage);
      notifyListeners();
      return;
    }

    _isSyncing = true;
    _statusMessage = 'Đang đồng bộ với Google Drive...';
    notifyListeners();

    try {
      await _driveService.ensureAppFolder();
      await _driveService.ensureJsonFolder();
      if (autoExportPdfOnSync) {
        await _driveService.ensurePdfFolder();
      }
      Map<String, String> remoteAssets = <String, String>{};
      try {
        await _driveService.ensureAssetsFolder();
        remoteAssets = await _driveService.listRemoteAssetFiles();
      } catch (_) {}
      final remoteAssetNames = remoteAssets.keys.toSet();

      // 1. Xử lý các yêu cầu xóa tệp trên Drive
      for (final driveId in List<String>.from(_pendingDeleteDriveIds)) {
        try {
          await _driveService.deleteRemoteNotebook(driveId);
        } catch (_) {}
        _pendingDeleteDriveIds.remove(driveId);
        _addLog('Đã xóa tệp sao lưu cũ trên Drive ($driveId).');
      }

      // 2. Lấy danh sách siêu dữ liệu hiện có trong ChemNote_Backups/JSON/
      final remoteMetaList = await _driveService.listRemoteNotebooks();
      final remoteByNotebookId = <String, DriveNotebookMeta>{};
      for (final meta in remoteMetaList) {
        if (meta.notebookId != null && meta.notebookId!.isNotEmpty) {
          remoteByNotebookId[meta.notebookId!] = meta;
        }
      }

      // Xóa dứt điểm JSON + thư mục Assets con + tệp cũ ở gốc Assets/ của các ghi chú đã dọn thùng rác
      if (_pendingDeleteNotebookIds.isNotEmpty) {
        for (final nbId in List<String>.from(_pendingDeleteNotebookIds)) {
          final remoteMeta = remoteByNotebookId.remove(nbId);
          if (remoteMeta != null) {
            try {
              await _driveService.deleteRemoteNotebook(remoteMeta.driveFileId);
            } catch (_) {}
          }
          try {
            await _driveService.deleteNotebookAssetsFolder(nbId);
          } catch (_) {}
          final legacyKeys = _pendingDeleteLegacyAssetKeys.remove(nbId);
          if (legacyKeys != null) {
            for (final key in legacyKeys) {
              final legacyDriveId = remoteAssets[key];
              if (legacyDriveId != null) {
                try {
                  await _driveService.deleteRemoteNotebook(legacyDriveId);
                  remoteAssets.remove(key);
                  remoteAssetNames.remove(key);
                } catch (_) {}
              }
            }
          }
          _pendingDeleteNotebookIds.remove(nbId);
          _addLog(
            'Đã xóa hoàn toàn sao lưu Drive (JSON + PDF + Assets) của ghi chú đã dọn.',
          );
        }
        await _persistPendingDeleteNotebookIds();
      }

      // 3. Thu thập sổ tay cục bộ từ AppState hoặc hàng đợi snapshot
      final localNotebooks = _appState != null
          ? List<Notebook>.from(_appState!.notebooks)
          : _pendingSnapshots.values.toList();

      var uploadedCount = 0;
      var downloadedCount = 0;
      var conflictCopies = 0;

      for (final local in localNotebooks) {
        if (_pendingDeleteNotebookIds.contains(local.id)) continue;
        final remoteMeta = remoteByNotebookId.remove(local.id);
        final needsPdfBackfill = autoExportPdfOnSync &&
            local.drivePdfFileId == null &&
            (isManualSync || local.pages.length <= maxBackgroundPdfPages);
        final needsUpload = _pendingUploadIds.contains(local.id) ||
            local.syncStatus == SyncStatus.pendingUpload ||
            local.syncStatus == SyncStatus.localOnly ||
            local.driveFileId == null ||
            needsPdfBackfill;

        if (remoteMeta == null) {
          if (needsUpload) {
            await _uploadSingleNotebook(
              local,
              isManualSync: isManualSync,
              remoteAssetNames: remoteAssetNames,
            );
            uploadedCount++;
          }
          continue;
        }

        // Có cả bản cục bộ và bản trên Drive -> kiểm tra xung đột
        if (!needsUpload &&
            !remoteMeta.modifiedTime
                .isAfter(local.updatedAt.add(const Duration(seconds: 2)))) {
          continue;
        }

        final remoteNotebook =
            await _driveService.downloadNotebook(remoteMeta.driveFileId);
        final resolution = resolveConflict(
          local: local.copyWith(driveFileId: remoteMeta.driveFileId),
          remote: remoteNotebook,
          lastSyncedAt: _lastSyncedAt,
        );

        if (resolution.conflictBackupCopy != null && _appState != null) {
          await _appState!.updateNotebook(
            resolution.conflictBackupCopy!,
            markPendingSync: false,
          );
          await _uploadSingleNotebook(
            resolution.conflictBackupCopy!,
            isManualSync: isManualSync,
            remoteAssetNames: remoteAssetNames,
          );
          conflictCopies++;
          _addLog(
            'Phát hiện xung đột ở "${local.title}" — đã tạo bản sao dự phòng.',
          );
        }

        if (resolution.winner == ConflictWinner.local) {
          await _uploadSingleNotebook(
            resolution.resolvedNotebook,
            isManualSync: isManualSync,
            remoteAssetNames: remoteAssetNames,
          );
          uploadedCount++;
        } else if (resolution.winner == ConflictWinner.remote) {
          final hydrated = await _hydrateMissingAssets(
            resolution.resolvedNotebook,
            remoteAssets,
          );
          await _appState?.upsertNotebookFromSync(hydrated);
          _pendingUploadIds.remove(local.id);
          _pendingSnapshots.remove(local.id);
          downloadedCount++;
        } else {
          // Nếu bản cục bộ chưa có PDF trên Drive và được phép xuất PDF, tải bù một lần.
          if (needsPdfBackfill) {
            await _uploadSingleNotebook(
              resolution.resolvedNotebook,
              isManualSync: isManualSync,
              remoteAssetNames: remoteAssetNames,
            );
            uploadedCount++;
          } else {
            await _appState?.updateNotebookSyncStatus(
              local.id,
              SyncStatus.synced,
              driveFileId: remoteMeta.driveFileId,
              drivePdfFileId:
                  resolution.resolvedNotebook.drivePdfFileId ?? local.drivePdfFileId,
            );
            _pendingUploadIds.remove(local.id);
            _pendingSnapshots.remove(local.id);
          }
        }
      }

      // 4. Tải về các sổ tay mới chỉ tồn tại trên Google Drive (kèm tài nguyên ảnh/PDF nền)
      for (final meta in remoteByNotebookId.values) {
        if (meta.notebookId != null &&
            _pendingDeleteNotebookIds.contains(meta.notebookId)) {
          continue;
        }
        final remoteNotebook =
            await _driveService.downloadNotebook(meta.driveFileId);
        if (_pendingDeleteNotebookIds.contains(remoteNotebook.id)) {
          continue;
        }
        final hydrated = await _hydrateMissingAssets(
          remoteNotebook,
          remoteAssets,
        );
        await _appState?.upsertNotebookFromSync(hydrated);
        downloadedCount++;
      }

      await _setLastSyncedAt(DateTime.now());
      _statusMessage =
          'Đồng bộ xong: ↑$uploadedCount tải lên, ↓$downloadedCount tải về'
          '${conflictCopies > 0 ? ', $conflictCopies bản sao xung đột' : ''}';
      _addLog(_statusMessage);
    } catch (e) {
      _statusMessage = 'Lỗi đồng bộ: $e';
      _addLog(_statusMessage, isError: true);
    } finally {
      _isSyncing = false;
      notifyListeners();
      final bool hasPendingCleanup = _pendingPostSyncCleanup &&
          (_pendingDeleteNotebookIds.isNotEmpty ||
              _pendingDeleteDriveIds.isNotEmpty);
      if (hasPendingCleanup &&
          isSignedIn &&
          (_isOnline || isDemoMode) &&
          _followupDeleteDepth < 2) {
        _pendingPostSyncCleanup = false;
        _followupDeleteDepth++;
        unawaited(syncNow(isManualSync: true));
      } else {
        _pendingPostSyncCleanup = false;
        _followupDeleteDepth = 0;
      }
    }
  }

  Future<void> _uploadSingleNotebook(
    Notebook notebook, {
    required bool isManualSync,
    required Set<String> remoteAssetNames,
  }) async {
    if (_pendingDeleteNotebookIds.contains(notebook.id)) {
      _addLog('Đã hủy tải lên "${notebook.title}" vì ghi chú đã bị xóa.');
      return;
    }
    await _appState?.updateNotebookSyncStatus(notebook.id, SyncStatus.syncing);
    try {
      // 1. Đồng bộ tăng dần các ảnh & trang PDF nền còn thiếu vào ChemNote_Backups/Assets/
      await _uploadNotebookAssetsIfMissing(notebook, remoteAssetNames);
      if (_pendingDeleteNotebookIds.contains(notebook.id)) {
        _addLog('Đã dừng tải lên tài nguyên "${notebook.title}" do ghi chú đã bị xóa.');
        return;
      }

      // 2. Tạo & tải lên PDF vector vào ChemNote_Backups/PDF/ (có chốt bảo vệ nhiệt cho đồng bộ nền)
      String? drivePdfFileId = notebook.drivePdfFileId;
      final shouldExportPdf = autoExportPdfOnSync &&
          (isManualSync || notebook.pages.length <= maxBackgroundPdfPages);
      if (shouldExportPdf) {
        try {
          final pdfBytes =
              await _pdfExportService.buildNotebookPdfBytes(notebook);
          if (_pendingDeleteNotebookIds.contains(notebook.id)) {
            _addLog('Đã hủy tải lên PDF "${notebook.title}" vì ghi chú đã bị xóa.');
            return;
          }
          drivePdfFileId =
              await _driveService.uploadNotebookPdf(notebook, pdfBytes);
        } catch (pdfErr) {
          _addLog(
            'Cảnh báo: Chưa xuất được PDF cho "${notebook.title}" ($pdfErr); vẫn tiếp tục sao lưu JSON.',
            isError: true,
          );
        }
      } else if (autoExportPdfOnSync &&
          !isManualSync &&
          notebook.pages.length > maxBackgroundPdfPages) {
        _addLog(
          'Bỏ qua xuất PDF nền cho "${notebook.title}" (${notebook.pages.length} trang > $maxBackgroundPdfPages) để tránh nóng máy.',
        );
      }

      if (_pendingDeleteNotebookIds.contains(notebook.id)) {
        _addLog('Đã hủy tải lên JSON "${notebook.title}" vì ghi chú đã bị xóa.');
        return;
      }

      // 3. Tải lên tệp JSON đầy đủ (kèm drivePdfFileId mới nhất) vào ChemNote_Backups/JSON/
      final notebookWithPdfId = notebook.copyWith(
        drivePdfFileId: drivePdfFileId,
      );
      final driveFileId = await _driveService.uploadNotebook(notebookWithPdfId);

      await _appState?.updateNotebookSyncStatus(
        notebook.id,
        SyncStatus.synced,
        driveFileId: driveFileId,
        drivePdfFileId: drivePdfFileId,
      );
      _pendingUploadIds.remove(notebook.id);
      _pendingSnapshots.remove(notebook.id);
      await _setLastSyncedAt(DateTime.now());
    } catch (e) {
      if (!_pendingDeleteNotebookIds.contains(notebook.id)) {
        await _appState?.updateNotebookSyncStatus(notebook.id, SyncStatus.error);
      }
      rethrow;
    }
  }

  Future<void> _uploadNotebookAssetsIfMissing(
    Notebook notebook,
    Set<String> remoteAssetNames,
  ) async {
    if (_pendingDeleteNotebookIds.contains(notebook.id)) return;
    String? nbFolderId;
    Set<String> folderAssetNames = remoteAssetNames;
    try {
      nbFolderId = await _driveService.ensureNotebookAssetsFolder(notebook);
      if (_pendingDeleteNotebookIds.contains(notebook.id)) return;
      final nbAssets = await _driveService.listRemoteAssetFiles(
        parentFolderId: nbFolderId,
      );
      folderAssetNames = nbAssets.keys.toSet();
    } catch (_) {}

    for (final page in notebook.pages) {
      if (_pendingDeleteNotebookIds.contains(notebook.id)) return;
      final pdfBg = page.pdfBackgroundPath;
      if (pdfBg != null && pdfBg.isNotEmpty) {
        final remoteName = remoteAssetKeyForPath(pdfBg, notebookId: notebook.id);
        try {
          await _driveService.uploadAssetFileIfMissing(
            File(pdfBg),
            remoteName,
            folderAssetNames,
            parentFolderId: nbFolderId,
          );
        } catch (_) {}
      }
      for (final img in page.imageElements) {
        if (_pendingDeleteNotebookIds.contains(notebook.id)) return;
        if (img.filePath.isEmpty) continue;
        final name = remoteAssetKeyForPath(img.filePath, notebookId: notebook.id);
        try {
          await _driveService.uploadAssetFileIfMissing(
            File(img.filePath),
            name,
            folderAssetNames,
            parentFolderId: nbFolderId,
          );
        } catch (_) {}
      }
    }
  }

  Future<Notebook> _hydrateMissingAssets(
    Notebook notebook,
    Map<String, String> remoteAssets,
  ) async {
    Map<String, String> nbAssets = <String, String>{};
    try {
      final nbFolderId =
          await _driveService.findNotebookAssetsFolderId(notebook.id);
      if (nbFolderId != null && nbFolderId.isNotEmpty) {
        nbAssets = await _driveService.listRemoteAssetFiles(
          parentFolderId: nbFolderId,
        );
      }
    } catch (_) {}

    if (nbAssets.isEmpty && remoteAssets.isEmpty) return notebook;

    Directory? rootDir;
    Future<Directory> resolveRootDir() async {
      if (rootDir != null) return rootDir!;
      if (_appState != null) {
        rootDir = await _appState!.storage.getRootDirectory();
      } else {
        final docs = await getApplicationDocumentsDirectory();
        rootDir = Directory('${docs.path}${Platform.pathSeparator}chemnote');
      }
      return rootDir!;
    }

    var changed = false;
    final updatedPages = <NotePage>[];

    for (final page in notebook.pages) {
      var pageChanged = false;
      var pdfBgPath = page.pdfBackgroundPath;

      if (pdfBgPath != null &&
          pdfBgPath.isNotEmpty &&
          !await File(pdfBgPath).exists()) {
        final uniqueKey =
            remoteAssetKeyForPath(pdfBgPath, notebookId: notebook.id);
        final legacyName = _basename(pdfBgPath);
        final driveId = nbAssets[uniqueKey] ??
            nbAssets[legacyName] ??
            remoteAssets[uniqueKey] ??
            remoteAssets[legacyName];
        if (driveId != null) {
          try {
            final root = await resolveRootDir();
            final localDest =
                '${root.path}${Platform.pathSeparator}pdfs${Platform.pathSeparator}$uniqueKey';
            if (!await File(localDest).exists()) {
              await _driveService.downloadAssetFile(driveId, localDest);
            }
            pdfBgPath = localDest;
            pageChanged = true;
          } catch (_) {}
        }
      }

      var imagesChanged = false;
      final updatedImages = <ImageElement>[];
      for (final img in page.imageElements) {
        if (img.filePath.isNotEmpty && !await File(img.filePath).exists()) {
          final uniqueKey =
              remoteAssetKeyForPath(img.filePath, notebookId: notebook.id);
          final legacyName = _basename(img.filePath);
          final driveId = nbAssets[uniqueKey] ??
              nbAssets[legacyName] ??
              remoteAssets[uniqueKey] ??
              remoteAssets[legacyName];
          if (driveId != null) {
            try {
              final root = await resolveRootDir();
              final localDest =
                  '${root.path}${Platform.pathSeparator}images${Platform.pathSeparator}$uniqueKey';
              if (!await File(localDest).exists()) {
                await _driveService.downloadAssetFile(driveId, localDest);
              }
              updatedImages.add(img.copyWith(filePath: localDest));
              imagesChanged = true;
              continue;
            } catch (_) {}
          }
        }
        updatedImages.add(img);
      }

      if (pageChanged || imagesChanged) {
        changed = true;
        updatedPages.add(
          page.copyWith(
            pdfBackgroundPath: pdfBgPath,
            imageElements: imagesChanged ? updatedImages : page.imageElements,
          ),
        );
      } else {
        updatedPages.add(page);
      }
    }

    return changed ? notebook.copyWith(pages: updatedPages) : notebook;
  }

  /// Tạo khóa tệp tài nguyên duy nhất trên Google Drive `Assets/` để tránh
  /// trùng tên `page_1.png`, `page_94.png` giữa nhiều tài liệu PDF khác nhau.
  static String remoteAssetKeyForPath(
    String localPath, {
    required String notebookId,
  }) {
    final normalized = localPath.replaceAll('\\', '/');
    final parts = normalized.split('/').where((s) => s.isNotEmpty).toList();
    final fileName = parts.isNotEmpty ? parts.last : normalized;
    final pdfPagesIdx = parts.lastIndexOf('pdf_pages');
    if (pdfPagesIdx >= 0 && pdfPagesIdx + 2 < parts.length) {
      final batchId = parts[pdfPagesIdx + 1];
      if (batchId.isNotEmpty && !fileName.startsWith('${batchId}_')) {
        return '${batchId}_$fileName';
      }
      return fileName;
    }
    if (RegExp(r'^page_\d+\.').hasMatch(fileName) &&
        notebookId.isNotEmpty &&
        !fileName.startsWith('${notebookId}_')) {
      return '${notebookId}_$fileName';
    }
    return fileName;
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.substring(idx + 1) : normalized;
  }

  /// Khôi phục toàn bộ sổ tay từ thư mục `ChemNote_Backups/JSON/` (kèm ảnh/PDF nền từ `Assets/`).
  /// Trả về số lượng sổ tay đã khôi phục.
  Future<int> restoreFromDrive() async {
    if (_isSyncing) return 0;

    if (!isSignedIn) {
      _statusMessage = 'Vui lòng đăng nhập Google Drive để khôi phục.';
      notifyListeners();
      return 0;
    }

    if (!_isOnline && !isDemoMode) {
      _statusMessage = 'Cần kết nối Internet để khôi phục từ Google Drive.';
      _addLog(_statusMessage, isError: true);
      notifyListeners();
      return 0;
    }

    _isSyncing = true;
    _statusMessage = 'Đang khôi phục sổ tay & tài nguyên từ Google Drive...';
    notifyListeners();

    var restoredCount = 0;
    try {
      await _driveService.ensureAppFolder();
      await _driveService.ensureJsonFolder();
      Map<String, String> remoteAssets = <String, String>{};
      try {
        await _driveService.ensureAssetsFolder();
        remoteAssets = await _driveService.listRemoteAssetFiles();
      } catch (_) {}

      final remoteList = await _driveService.listRemoteNotebooks();

      for (final meta in remoteList) {
        if (meta.notebookId != null &&
            _pendingDeleteNotebookIds.contains(meta.notebookId)) {
          continue;
        }
        final remoteNotebook =
            await _driveService.downloadNotebook(meta.driveFileId);
        if (_pendingDeleteNotebookIds.contains(remoteNotebook.id)) {
          continue;
        }
        final hydrated = await _hydrateMissingAssets(
          remoteNotebook,
          remoteAssets,
        );
        await _appState?.upsertNotebookFromSync(hydrated);
        _pendingUploadIds.remove(hydrated.id);
        _pendingSnapshots.remove(hydrated.id);
        restoredCount++;
      }

      await _setLastSyncedAt(DateTime.now());
      _statusMessage = restoredCount > 0
          ? 'Đã khôi phục $restoredCount sổ tay từ Google Drive.'
          : 'Không tìm thấy bản sao lưu nào trên Google Drive.';
      _addLog(_statusMessage);
    } catch (e) {
      _statusMessage = 'Khôi phục thất bại: $e';
      _addLog(_statusMessage, isError: true);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }

    return restoredCount;
  }

  static String buildDriveFileViewUrl(String fileId) =>
      'https://drive.google.com/file/d/$fileId/view';

  /// Trả về link Google Drive của bản PDF sổ tay (tự tạo và tải lên PDF nếu chưa có).
  Future<String> getOrUploadNotebookPdfDriveLink(Notebook notebook) async {
    final latest = _appState?.getNotebookById(notebook.id) ?? notebook;
    final existingPdfId = latest.drivePdfFileId?.trim();
    if (existingPdfId != null && existingPdfId.isNotEmpty) {
      return buildDriveFileViewUrl(existingPdfId);
    }

    if (!isSignedIn) {
      throw StateError(
        'Vui lòng đăng nhập Google Drive trong mục Đồng bộ trước khi lấy link PDF.',
      );
    }
    if (!_isOnline && !isDemoMode) {
      throw StateError(
        'Không có kết nối mạng để tạo và tải PDF lên Google Drive.',
      );
    }

    await _driveService.ensureAppFolder();
    await _driveService.ensurePdfFolder();
    final pdfBytes = await _pdfExportService.buildNotebookPdfBytes(latest);
    final uploadedPdfId =
        await _driveService.uploadNotebookPdf(latest, pdfBytes);

    await _appState?.updateNotebookSyncStatus(
      latest.id,
      latest.syncStatus,
      driveFileId: latest.driveFileId,
      drivePdfFileId: uploadedPdfId,
    );
    _addLog('Đã tạo và tải PDF lên Google Drive cho "${latest.title}".');
    notifyListeners();
    return buildDriveFileViewUrl(uploadedPdfId);
  }

  Future<void> _setLastSyncedAt(DateTime time) async {
    _lastSyncedAt = time;
    try {
      await _secureStorage.write(
        key: _kLastSyncedAt,
        value: time.toIso8601String(),
      );
    } catch (_) {}
  }

  Future<void> _persistPendingDeleteNotebookIds() async {
    try {
      if (_pendingDeleteNotebookIds.isEmpty) {
        await _secureStorage.delete(key: _kPendingDeleteNotebookIds);
      } else {
        await _secureStorage.write(
          key: _kPendingDeleteNotebookIds,
          value: _pendingDeleteNotebookIds.join('\n'),
        );
      }
    } catch (_) {}
  }

  void _addLog(String message, {bool isError = false}) {
    _syncLogs.insert(
      0,
      SyncLogEntry(
        timestamp: DateTime.now(),
        message: message,
        isError: isError,
      ),
    );
    if (_syncLogs.length > 50) {
      _syncLogs.removeRange(50, _syncLogs.length);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _foregroundTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }
}
