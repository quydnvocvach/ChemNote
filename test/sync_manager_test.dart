import 'package:chemnote/core/models/notebook.dart';
import 'package:chemnote/features/sync/google_auth_service.dart';
import 'package:chemnote/features/sync/sync_manager.dart';
import 'package:flutter_test/flutter_test.dart';

Notebook _makeNotebook({
  required String id,
  required String title,
  required DateTime updatedAt,
  SyncStatus syncStatus = SyncStatus.localOnly,
  String? driveFileId,
}) {
  return Notebook(
    id: id,
    title: title,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: updatedAt,
    syncStatus: syncStatus,
    driveFileId: driveFileId,
  );
}

void main() {
  group('SyncManager Conflict Resolution', () {
    late SyncManager manager;

    setUp(() {
      manager = SyncManager(
        attachConnectivityListener: false,
        debounceDuration: const Duration(milliseconds: 50),
      );
    });

    tearDown(() {
      manager.dispose();
    });

    test('returns equal when local and remote timestamps are within 1 second', () {
      final t = DateTime.utc(2026, 5, 1, 10, 0, 0);
      final local = _makeNotebook(
        id: 'nb-1',
        title: 'Hóa Hữu Cơ',
        updatedAt: t,
      );
      final remote = _makeNotebook(
        id: 'nb-1',
        title: 'Hóa Hữu Cơ',
        updatedAt: t.add(const Duration(milliseconds: 500)),
        driveFileId: 'drive-1',
      );

      final result = manager.resolveConflict(local: local, remote: remote);
      expect(result.winner, ConflictWinner.equal);
      expect(result.conflictBackupCopy, isNull);
      expect(result.resolvedNotebook.driveFileId, 'drive-1');
      expect(result.resolvedNotebook.syncStatus, SyncStatus.synced);
    });

    test('selects local when local is newer without dual-edit conflict', () {
      final lastSync = DateTime.utc(2026, 5, 1, 10, 0, 0);
      final remote = _makeNotebook(
        id: 'nb-1',
        title: 'Hóa Vô Cơ',
        updatedAt: DateTime.utc(2026, 5, 1, 9, 55, 0),
        driveFileId: 'drive-1',
      );
      final local = _makeNotebook(
        id: 'nb-1',
        title: 'Hóa Vô Cơ (Sửa)',
        updatedAt: DateTime.utc(2026, 5, 1, 10, 5, 0),
        syncStatus: SyncStatus.pendingUpload,
        driveFileId: 'drive-1',
      );

      final result = manager.resolveConflict(
        local: local,
        remote: remote,
        lastSyncedAt: lastSync,
      );

      expect(result.winner, ConflictWinner.local);
      expect(result.resolvedNotebook.title, 'Hóa Vô Cơ (Sửa)');
      expect(result.conflictBackupCopy, isNull);
    });

    test('selects remote when remote is newer without dual-edit conflict', () {
      final lastSync = DateTime.utc(2026, 5, 1, 10, 0, 0);
      final local = _makeNotebook(
        id: 'nb-1',
        title: 'Hóa Lý',
        updatedAt: DateTime.utc(2026, 5, 1, 9, 30, 0),
        syncStatus: SyncStatus.synced,
        driveFileId: 'drive-1',
      );
      final remote = _makeNotebook(
        id: 'nb-1',
        title: 'Hóa Lý (Trên máy khác)',
        updatedAt: DateTime.utc(2026, 5, 1, 10, 15, 0),
        driveFileId: 'drive-1',
      );

      final result = manager.resolveConflict(
        local: local,
        remote: remote,
        lastSyncedAt: lastSync,
      );

      expect(result.winner, ConflictWinner.remote);
      expect(result.resolvedNotebook.title, 'Hóa Lý (Trên máy khác)');
      expect(result.resolvedNotebook.syncStatus, SyncStatus.synced);
      expect(result.conflictBackupCopy, isNull);
    });

    test('creates conflict backup copy when both local and remote changed after lastSyncedAt', () {
      final lastSync = DateTime.utc(2026, 5, 1, 10, 0, 0);
      final local = _makeNotebook(
        id: 'nb-1',
        title: 'Bài giảng Phổ IR - Máy A',
        updatedAt: DateTime.utc(2026, 5, 1, 10, 20, 0),
        syncStatus: SyncStatus.pendingUpload,
        driveFileId: 'drive-1',
      );
      final remote = _makeNotebook(
        id: 'nb-1',
        title: 'Bài giảng Phổ IR - Máy B',
        updatedAt: DateTime.utc(2026, 5, 1, 10, 10, 0),
        driveFileId: 'drive-1',
      );

      final result = manager.resolveConflict(
        local: local,
        remote: remote,
        lastSyncedAt: lastSync,
      );

      expect(result.winner, ConflictWinner.local);
      expect(result.resolvedNotebook.title, 'Bài giảng Phổ IR - Máy A');
      expect(result.conflictBackupCopy, isNotNull);
      expect(result.conflictBackupCopy!.id, isNot(local.id));
      expect(result.conflictBackupCopy!.title, contains('Bản sao xung đột'));
      expect(result.conflictBackupCopy!.driveFileId, isNull);
      expect(result.conflictBackupCopy!.syncStatus, SyncStatus.pendingUpload);
    });
  });

  group('SyncManager Offline Queue & PKCE Helpers', () {
    late SyncManager manager;

    setUp(() {
      manager = SyncManager(
        attachConnectivityListener: false,
        debounceDuration: const Duration(milliseconds: 50),
      );
    });

    tearDown(() {
      manager.dispose();
    });

    test('queues uploads while offline and removes them on delete', () {
      manager.setOnlineStatusForTesting(false);
      final nb = _makeNotebook(
        id: 'nb-offline-1',
        title: 'Ghi chú ngoại tuyến',
        updatedAt: DateTime.utc(2026, 5, 2),
        driveFileId: 'drive-offline-1',
      );

      manager.queueNotebookUpload(nb);
      expect(manager.pendingUploadIds, contains('nb-offline-1'));

      manager.queueNotebookDelete('nb-offline-1');
      expect(manager.pendingUploadIds, isNot(contains('nb-offline-1')));
      expect(manager.pendingDeleteDriveIds, contains('drive-offline-1'));
    });

    test('toggles autoSyncEnabled cleanly', () {
      expect(manager.autoSyncEnabled, isTrue);
      manager.setAutoSyncEnabled(false);
      expect(manager.autoSyncEnabled, isFalse);
      manager.setAutoSyncEnabled(true);
      expect(manager.autoSyncEnabled, isTrue);
    });

    test('PKCE code verifier and S256 challenge follow RFC 7636 format', () {
      final verifier = GoogleAuthService.generateCodeVerifier();
      expect(verifier.length, greaterThanOrEqualTo(43));
      expect(verifier.length, lessThanOrEqualTo(128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(verifier), isTrue);

      final challenge = GoogleAuthService.computeCodeChallenge(verifier);
      expect(challenge.length, 43); // Base64url(SHA-256) without '=' padding
      expect(challenge.contains('='), isFalse);
      expect(challenge.contains('+'), isFalse);
      expect(challenge.contains('/'), isFalse);
    });
  });
}
