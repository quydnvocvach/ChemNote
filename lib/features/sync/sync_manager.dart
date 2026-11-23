import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/notebook.dart';
import '../../core/providers/app_state.dart';
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
/// Tự động lắng nghe kết nối mạng, gom nhóm (debounce) chỉnh sửa, xếp hàng tải lên khi mất mạng
/// và xử lý xung đột theo mốc `updatedAt` (ưu tiên bản mới hơn + giữ bản sao xung đột).
class SyncManager extends ChangeNotifier {
  SyncManager({
    AppState? appState,
    GoogleAuthService? authService,
    GoogleDriveService? driveService,
    Connectivity? connectivity,
    Uuid? uuid,
    this.debounceDuration = const Duration(seconds: 3),
    bool attachConnectivityListener = true,
  })  : _appState = appState,
        _authService = authService ?? GoogleAuthService(),
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
  final Connectivity _connectivity;
  final Uuid _uuid;
  final Duration debounceDuration;
  final bool _attachConnectivityListener;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _debounceTimer;

  bool _autoSyncEnabled = true;
  bool _isSyncing = false;
  bool _isOnline = true;
  DateTime? _lastSyncedAt;
  String _statusMessage = 'Chưa kết nối Google Drive';

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
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String get statusMessage => _statusMessage;
  List<SyncLogEntry> get syncLogs => List.unmodifiable(_syncLogs);
  Set<String> get pendingUploadIds => Set.unmodifiable(_pendingUploadIds);
  Set<String> get pendingDeleteDriveIds =>
      Set.unmodifiable(_pendingDeleteDriveIds);

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

  /// Khởi tạo phiên đăng nhập đã lưu và bắt đầu theo dõi trạng thái mạng.
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
        _isOnline = _hasConnection(results);
        _connectivitySub = _connectivity.onConnectivityChanged.listen(
          _onConnectivityChanged,
        );
      } catch (_) {
        _isOnline = true;
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

    notifyListeners();

    if (_autoSyncEnabled && isSignedIn && _isOnline && _pendingUploadIds.isNotEmpty) {
      unawaited(syncNow());
    }
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final nowOnline = _hasConnection(results);
    if (nowOnline == _isOnline) return;
    _isOnline = nowOnline;

    if (_isOnline) {
      _addLog('Đã kết nối lại Internet.');
      if (_autoSyncEnabled &&
          isSignedIn &&
          (_pendingUploadIds.isNotEmpty || _pendingDeleteDriveIds.isNotEmpty)) {
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
    _addLog(enabled ? 'Đã bật tự động đồng bộ.' : 'Đã tắt tự động đồng bộ.');
    notifyListeners();
    if (enabled && isSignedIn && _isOnline && _pendingUploadIds.isNotEmpty) {
      unawaited(syncNow());
    }
  }

  /// Cập nhật trạng thái mạng thủ công (hữu ích cho kiểm thử đơn vị).
  void setOnlineStatusForTesting(bool online) {
    _isOnline = online;
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
      notifyListeners();

      if (_autoSyncEnabled && _isOnline) {
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
    notifyListeners();
    return user;
  }

  /// Đăng xuất tài khoản Google Drive.
  Future<void> signOut() async {
    _debounceTimer?.cancel();
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

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      unawaited(syncNow());
    });
    notifyListeners();
  }

  /// Xếp hàng xóa tệp sổ tay trên Google Drive nếu đã từng đồng bộ.
  void queueNotebookDelete(String notebookId, {String? driveFileId}) {
    _pendingUploadIds.remove(notebookId);
    final removed = _pendingSnapshots.remove(notebookId);
    final targetDriveId = driveFileId ?? removed?.driveFileId;
    if (targetDriveId != null && targetDriveId.isNotEmpty) {
      _pendingDeleteDriveIds.add(targetDriveId);
    }

    if (_autoSyncEnabled && isSignedIn && (_isOnline || isDemoMode)) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounceDuration, () {
        unawaited(syncNow());
      });
    }
    notifyListeners();
  }

  /// Giải quyết xung đột giữa bản cục bộ và bản trên Google Drive theo `updatedAt`.
  /// - Nếu bản cục bộ mới hơn -> chọn cục bộ.
  /// - Nếu bản Drive mới hơn -> chọn Drive.
  /// - Nếu CẢ HAI cùng sửa sau `lastSyncedAt` (hoặc đều có thay đổi khác mốc thời gian đáng kể),
  ///   tạo thêm một bản sao dự phòng cho bản thua để không bao giờ mất bài ghi chép.
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
          syncStatus: SyncStatus.synced,
        ),
        conflictBackupCopy: backup,
      );
    }
  }

  /// Đồng bộ hai chiều ngay lập tức giữa máy và Google Drive.
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
    _statusMessage = 'Đang đồng bộ với Google Drive...';
    notifyListeners();

    try {
      await _driveService.ensureAppFolder();

      // 1. Xử lý các yêu cầu xóa tệp trên Drive
      for (final driveId in List<String>.from(_pendingDeleteDriveIds)) {
        await _driveService.deleteRemoteNotebook(driveId);
        _pendingDeleteDriveIds.remove(driveId);
        _addLog('Đã xóa tệp sao lưu cũ trên Drive ($driveId).');
      }

      // 2. Lấy danh sách siêu dữ liệu hiện có trên Google Drive
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
            local.driveFileId == null;

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
          await _appState?.updateNotebookSyncStatus(
            local.id,
            SyncStatus.synced,
            driveFileId: remoteMeta.driveFileId,
          );
          _pendingUploadIds.remove(local.id);
          _pendingSnapshots.remove(local.id);
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
          'Đồng bộ xong: ↑$uploadedCount tải lên, ↓$downloadedCount tải về'
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
      final driveFileId = await _driveService.uploadNotebook(notebook);
      await _appState?.updateNotebookSyncStatus(
        notebook.id,
        SyncStatus.synced,
        driveFileId: driveFileId,
      );
      _pendingUploadIds.remove(notebook.id);
      _pendingSnapshots.remove(notebook.id);
    } catch (e) {
      await _appState?.updateNotebookSyncStatus(notebook.id, SyncStatus.error);
      rethrow;
    }
  }

  /// Khôi phục toàn bộ sổ tay từ thư mục `ChemNote_Backups` trên Google Drive về máy.
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
    _connectivitySub?.cancel();
    super.dispose();
  }
}
