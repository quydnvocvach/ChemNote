import 'dart:io';

import 'package:chemnote/core/models/notebook.dart';
import 'package:chemnote/core/providers/app_state.dart';
import 'package:chemnote/core/storage/local_storage_service.dart';
import 'package:chemnote/features/sync/google_auth_service.dart';
import 'package:chemnote/features/sync/google_drive_service.dart';
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

    test('remoteAssetKeyForPath prevents collisions between multiple PDF batches', () {
      final keyA = SyncManager.remoteAssetKeyForPath(
        '/data/user/0/com.chemnote.app/app_flutter/chemnote/pdf_pages/batch-A/page_1.png',
        notebookId: 'nb-a',
      );
      final keyB = SyncManager.remoteAssetKeyForPath(
        '/data/user/0/com.chemnote.app/app_flutter/chemnote/pdf_pages/batch-B/page_1.png',
        notebookId: 'nb-b',
      );
      expect(keyA, 'batch-A_page_1.png');
      expect(keyB, 'batch-B_page_1.png');
      expect(keyA, isNot(equals(keyB)));

      final alreadyPrefixed = SyncManager.remoteAssetKeyForPath(
        r'C:\chemnote\pdf_pages\batch-C\batch-C_page_94.png',
        notebookId: 'nb-c',
      );
      expect(alreadyPrefixed, 'batch-C_page_94.png');
    });

    test('resolveConflict skips false conflict copy when identical or already conflict backup', () {
      final lastSync = DateTime.utc(2026, 5, 1, 10, 0, 0);
      final localSame = _makeNotebook(
        id: 'nb-same',
        title: 'Hóa phân tích',
        updatedAt: DateTime.utc(2026, 5, 1, 10, 10, 0),
        driveFileId: 'drive-same',
      );
      final remoteSame = _makeNotebook(
        id: 'nb-same',
        title: 'Hóa phân tích',
        updatedAt: DateTime.utc(2026, 5, 1, 10, 20, 0),
        driveFileId: 'drive-same',
      );

      final resSame = manager.resolveConflict(
        local: localSame,
        remote: remoteSame,
        lastSyncedAt: lastSync,
      );
      expect(resSame.winner, ConflictWinner.remote);
      expect(resSame.conflictBackupCopy, isNull);

      final localBackup = _makeNotebook(
        id: 'nb-copy',
        title: 'Sổ tay (Bản sao xung đột)',
        updatedAt: DateTime.utc(2026, 5, 1, 10, 10, 0),
        driveFileId: 'drive-copy',
      );
      final remoteBackup = _makeNotebook(
        id: 'nb-copy',
        title: 'Sổ tay (Bản sao xung đột) v2',
        updatedAt: DateTime.utc(2026, 5, 1, 10, 20, 0),
        driveFileId: 'drive-copy',
      );
      final resBackup = manager.resolveConflict(
        local: localBackup,
        remote: remoteBackup,
        lastSyncedAt: lastSync,
      );
      expect(resBackup.conflictBackupCopy, isNull);
    });

    test('buildNotebookAssetFolderName sanitizes title and preserves unique suffix', () {
      final folderA = GoogleDriveService.buildNotebookAssetFolderName(
        'Giáo trình: Điện/Hóa <2026>?',
        'a1b2c3d4-1111-2222-3333-444455556666',
      );
      final folderB = GoogleDriveService.buildNotebookAssetFolderName(
        'Giáo trình: Điện/Hóa <2026>?',
        'z9y8x7w6-1111-2222-3333-444455556666',
      );
      expect(folderA.endsWith('_a1b2c3d4'), isTrue);
      expect(folderB.endsWith('_z9y8x7w6'), isTrue);
      expect(folderA, isNot(equals(folderB)));
      expect(folderA.contains(RegExp(r'[\\/:*?"<>|]')), isFalse);
    });

    test('queueNotebookDelete tracks notebookId and Drive IDs for permanent cleanup', () {
      final nb = Notebook(
        id: 'nb-trash-1',
        title: 'Sổ tay đã dọn',
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 5, 2),
        driveFileId: 'drive-json-1',
        drivePdfFileId: 'drive-pdf-1',
      );

      manager.queueNotebookDelete(
        nb.id,
        driveFileId: nb.driveFileId,
        drivePdfFileId: nb.drivePdfFileId,
        deletedNotebook: nb,
      );

      expect(manager.pendingDeleteNotebookIds, contains('nb-trash-1'));
      expect(manager.pendingDeleteDriveIds, contains('drive-json-1'));
      expect(manager.pendingDeleteDriveIds, contains('drive-pdf-1'));
    });

    test('buildDriveFileViewUrl formats canonical Google Drive viewer URL', () {
      expect(
        SyncManager.buildDriveFileViewUrl('file_xyz_123'),
        'https://drive.google.com/file/d/file_xyz_123/view',
      );
    });

    test('getOrUploadNotebookPdfDriveLink returns cached URL and uploads on demand in Demo mode', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final tempDir = Directory.systemTemp.createTempSync('chemnote_sync_pdf_link_');
      final appState = AppState(
        storage: LocalStorageService(baseDirectory: tempDir),
      );
      final demoManager = SyncManager(
        appState: appState,
        attachConnectivityListener: false,
        debounceDuration: const Duration(milliseconds: 20),
      );

      try {
        // 1. Cached drivePdfFileId returns immediately even before signing in
        final cachedNb = _makeNotebook(
          id: 'nb-cached-pdf',
          title: 'Cached PDF',
          updatedAt: DateTime.utc(2026, 6, 1),
        ).copyWith(drivePdfFileId: 'drive_pdf_999');

        final cachedUrl =
            await demoManager.getOrUploadNotebookPdfDriveLink(cachedNb);
        expect(
          cachedUrl,
          'https://drive.google.com/file/d/drive_pdf_999/view',
        );

        // 2. Without drivePdfFileId and signed out -> throws friendly StateError
        final uncachedNb = await appState.createNotebook(title: 'Need PDF Link');
        await expectLater(
          demoManager.getOrUploadNotebookPdfDriveLink(uncachedNb),
          throwsStateError,
        );

        // 3. In Demo mode -> builds & uploads PDF and persists drivePdfFileId
        await demoManager.authService.signInDemo();
        final uploadedUrl =
            await demoManager.getOrUploadNotebookPdfDriveLink(uncachedNb);
        expect(uploadedUrl, startsWith('https://drive.google.com/file/d/'));
        expect(uploadedUrl, endsWith('/view'));

        final updatedNb = appState.getNotebookById(uncachedNb.id)!;
        expect(updatedNb.drivePdfFileId, isNotNull);
        expect(updatedNb.drivePdfFileId, isNotEmpty);

        // 4. Sync then delete clears remote notebook & assets cleanly
        await demoManager.syncNow(isManualSync: true);
        await appState.deleteNotebook(uncachedNb.id);
        expect(demoManager.pendingDeleteNotebookIds, contains(uncachedNb.id));
        await demoManager.syncNow(isManualSync: true);
        expect(demoManager.pendingDeleteNotebookIds, isNot(contains(uncachedNb.id)));
      } finally {
        demoManager.dispose();
        appState.dispose();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
