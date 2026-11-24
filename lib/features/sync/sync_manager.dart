import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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
    Connectivity? connectivity,
    Uuid? uuid,
    this.debounceDuration = const Duration(seconds: 3),
    bool attachConnectivityListener = true,
  })  : _appState = appState,
        _authService = authService ?? GoogleAuthService(),
        _pdfExportService = pdfExportService ?? PdfExportService(),
        _connectivity = connectivity ?? Connectivity(),
        _uuid = uuid ?? const Uuid(),
        _attachConnectivityListener = attachConnectivityListener {
    _driveService =
        driveService ?? GoogleDriveService(authService: _authService);
    if (_appState != null) {
      attachAppState(_appState!);
    }
  }

  AppState? _appState;
  final GoogleAuthService _authService;
  late final GoogleDriveService _driveService;
  final PdfExportService _pdfExportService;
  final Connectivity _connectivity;
  final Uuid _uuid;
  final Duration debounceDuration;
  final bool _attachConnectivityListener;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _debounceTimer;
  Timer? _foregroundTimer;

  bool _autoSyncEnabled = true;
  bool _isSyncing = false;
  bool _isOnline = true;
  bool _isOnWifi = true;
  DateTime? _lastSyncedAt;
  String _statusMessage = 'Chưa kết nối Google Drive';

  // Giá trị dự phòng khi chạy độc lập không gắn AppState (ví dụ trong unit test).
  int _fallbackForegroundSyncMinutes = 15;
  int _fallbackIdleSyncDays = 1;
  bool _fallbackWifiOnlySync = true;

  final Set<String> _pendingUploadIds = <String>{};
  final Map<String, Notebook> _pendingSnapshots = <String, Notebook>{};
  final Set<String> _pendingDeleteDriveIds = <String>{};
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

  /// Chu kỳ đồng bộ khi đang mở app (phút): `0` (thủ công), `5`, `15`, `45`, `120`.
  int get foregroundSyncMinutes =>
      _appState?.foregroundSyncMinutes ?? _fallbackForegroundSyncMinutes;

  /// Chu kỳ nhắc đồng bộ dài hạn khi quay lại app (ngày): `0` (tắt), `1`, `3`, `5`.
  int get idleSyncDays => _appState?.idleSyncDays ?? _fallbackIdleSyncDays;

  /// Chỉ tự động đồng bộ qua Wi-Fi để tiết kiệm pin & dữ liệu di động.
  bool get wifiOnlySync => _appState?.wifiOnlySync ?? _fallbackWifiOnlySync;

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
  }

  /// Khởi tạo phiên đăng nhập đã lưu, bắt đầu theo dõi mạng và lịch đồng bộ tiết kiệm pin.
  Future<void> initialize() async {
    await _authService.loadSavedSession();
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

  /// Xếp hàng tải lên sổ tay sau khi chỉnh sửa, có gom nhóm (debounce).
  void queueNotebookUpload(Notebook notebook) {
    _pendingUploadIds.add(notebook.id);
    _pendingSnapshots[notebook.id] = notebook;

    if (!_autoSyncEnabled || !isSignedIn) {
      notifyListeners();
      return;
    }

    if (!_isOnline && !isDemoMode) {
      _statusMessage =
          'Đang ngoại tuyến — đã xếp hàng ${_pendingUploadIds.length} sổ tay';
      notifyListeners();
      return;
    }

    if (wifiOnlySync && !_isOnWifi && !isDemoMode) {
      _statusMessage =
          'Đang chờ Wi-Fi — đã xếp hàng ${_pendingUploadIds.length} sổ tay';
      notifyListeners();
      return;
    }

    // Nếu người dùng chọn chu kỳ thủ công (0), không tự động kích hoạt ngay sau khi sửa.
    if (foregroundSyncMinutes == 0) {
      notifyListeners();
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      if (canAutoSyncOnCurrentNetwork) {
        unawaited(syncNow());
      }
    });
    notifyListeners();
  }

  /// Xếp hàng xóa tệp sổ tay (cả JSON và PDF) trên Google Drive nếu đã từng đồng bộ.
  void queueNotebookDelete(
    String notebookId, {
    String? driveFileId,
    String? drivePdfFileId,
  }) {
    _pendingUploadIds.remove(notebookId);
    final removed = _pendingSnapshots.remove(notebookId);
    final targetJsonId = driveFileId ?? removed?.driveFileId;
    final targetPdfId = drivePdfFileId ?? removed?.drivePdfFileId;
    if (targetJsonId != null && targetJsonId.isNotEmpty) {
      _pendingDeleteDriveIds.add(targetJsonId);
    }
    if (targetPdfId != null && targetPdfId.isNotEmpty) {
      _pendingDeleteDriveIds.add(targetPdfId);
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
    final bothChangedSinceLastSync = lastSyncedAt != null
        ? (local.updatedAt.isAfter(lastSyncedAt) &&
            remote.updatedAt.isAfter(lastSyncedAt))
        : (local.syncStatus == SyncStatus.pendingUpload &&
            local.driveFileId != null);

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

  /// Đồng bộ hai chiều ngay lập tức giữa máy và Google Drive (`JSON/` + `PDF/`).
  Future<void> syncNow() async {
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
    _statusMessage = 'Đang đồng bộ JSON & PDF với Google Drive...';
    notifyListeners();

    try {
      await _driveService.ensureAppFolder();
      await _driveService.ensureJsonFolder();
      await _driveService.ensurePdfFolder();

      // 1. Xử lý các yêu cầu xóa tệp trên Drive
      for (final driveId in List<String>.from(_pendingDeleteDriveIds)) {
        await _driveService.deleteRemoteNotebook(driveId);
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

      // 3. Thu thập sổ tay cục bộ từ AppState hoặc hàng đợi snapshot
      final localNotebooks = _appState != null
          ? List<Notebook>.from(_appState!.notebooks)
          : _pendingSnapshots.values.toList();

      var uploadedCount = 0;
      var downloadedCount = 0;
      var conflictCopies = 0;

      for (final local in localNotebooks) {
        final remoteMeta = remoteByNotebookId.remove(local.id);
        final needsUpload = _pendingUploadIds.contains(local.id) ||
            local.syncStatus == SyncStatus.pendingUpload ||
            local.syncStatus == SyncStatus.localOnly ||
            local.driveFileId == null ||
            local.drivePdfFileId == null;

        if (remoteMeta == null) {
          if (needsUpload) {
            await _uploadSingleNotebook(local);
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
          await _uploadSingleNotebook(resolution.conflictBackupCopy!);
          conflictCopies++;
          _addLog(
            'Phát hiện xung đột ở "${local.title}" — đã tạo bản sao dự phòng.',
          );
        }

        if (resolution.winner == ConflictWinner.local) {
          await _uploadSingleNotebook(resolution.resolvedNotebook);
          uploadedCount++;
        } else if (resolution.winner == ConflictWinner.remote) {
          await _appState?.upsertNotebookFromSync(resolution.resolvedNotebook);
          _pendingUploadIds.remove(local.id);
          _pendingSnapshots.remove(local.id);
          downloadedCount++;
        } else {
          // Nếu bản cục bộ chưa có PDF trên Drive, tải bù PDF vector một lần.
          if (local.drivePdfFileId == null) {
            await _uploadSingleNotebook(resolution.resolvedNotebook);
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

      // 4. Tải về các sổ tay mới chỉ tồn tại trên Google Drive
      for (final meta in remoteByNotebookId.values) {
        final remoteNotebook =
            await _driveService.downloadNotebook(meta.driveFileId);
        await _appState?.upsertNotebookFromSync(remoteNotebook);
        downloadedCount++;
      }

      _lastSyncedAt = DateTime.now();
      _statusMessage =
          'Đồng bộ xong: ↑$uploadedCount tải lên (JSON + PDF), ↓$downloadedCount tải về'
          '${conflictCopies > 0 ? ', $conflictCopies bản sao xung đột' : ''}';
      _addLog(_statusMessage);
    } catch (e) {
      _statusMessage = 'Lỗi đồng bộ: $e';
      _addLog(_statusMessage, isError: true);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _uploadSingleNotebook(Notebook notebook) async {
    await _appState?.updateNotebookSyncStatus(notebook.id, SyncStatus.syncing);
    try {
      // 1. Tạo & tải lên PDF vector gọn nhẹ vào ChemNote_Backups/PDF/
      String? drivePdfFileId = notebook.drivePdfFileId;
      try {
        final pdfBytes =
            await _pdfExportService.buildNotebookPdfBytes(notebook);
        drivePdfFileId =
            await _driveService.uploadNotebookPdf(notebook, pdfBytes);
      } catch (pdfErr) {
        _addLog(
          'Cảnh báo: Chưa xuất được PDF cho "${notebook.title}" ($pdfErr); vẫn tiếp tục sao lưu JSON.',
          isError: true,
        );
      }

      // 2. Tải lên tệp JSON đầy đủ (kèm drivePdfFileId mới nhất) vào ChemNote_Backups/JSON/
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
    } catch (e) {
      await _appState?.updateNotebookSyncStatus(notebook.id, SyncStatus.error);
      rethrow;
    }
  }

  /// Khôi phục toàn bộ sổ tay từ thư mục `ChemNote_Backups/JSON/` trên Google Drive về máy.
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
    _statusMessage = 'Đang khôi phục sổ tay từ Google Drive...';
    notifyListeners();

    var restoredCount = 0;
    try {
      await _driveService.ensureAppFolder();
      await _driveService.ensureJsonFolder();
      final remoteList = await _driveService.listRemoteNotebooks();

      for (final meta in remoteList) {
        final remoteNotebook =
            await _driveService.downloadNotebook(meta.driveFileId);
        await _appState?.upsertNotebookFromSync(remoteNotebook);
        _pendingUploadIds.remove(remoteNotebook.id);
        _pendingSnapshots.remove(remoteNotebook.id);
        restoredCount++;
      }

      _lastSyncedAt = DateTime.now();
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
