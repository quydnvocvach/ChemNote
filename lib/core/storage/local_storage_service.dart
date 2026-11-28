import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/drawing_elements.dart';
import '../models/folder.dart';
import '../models/notebook.dart';

String _serializeNotebookToJson(Notebook notebook) =>
    jsonEncode(notebook.toJson());

Notebook? _decodeNotebookFromJsonString(String raw) {
  try {
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return Notebook.fromJson(decoded);
    }
  } catch (_) {
    // Bỏ qua tệp bị hỏng để không ảnh hưởng toàn bộ thư viện.
  }
  return null;
}

class LocalStorageService {
  final Directory? _overrideBaseDir;
  final Uuid _uuid;
  final Map<String, Future<void>> _notebookWriteChains = {};
  final Map<String, Notebook> _latestPendingNotebookWrites = {};
  final Map<String, Future<void>> _sidecarWriteChains = {};
  int _tmpWriteSeq = 0;

  LocalStorageService({
    Directory? baseDirectory,
    Uuid? uuid,
  })  : _overrideBaseDir = baseDirectory,
        _uuid = uuid ?? const Uuid();

  Future<void> _enqueueSidecarWrite(
    String key,
    Future<void> Function() action,
  ) {
    final prev = _sidecarWriteChains[key] ?? Future<void>.value();
    late final Future<void> next;
    next = prev.catchError((_) {}).then((_) => action()).whenComplete(() {
      if (identical(_sidecarWriteChains[key], next)) {
        _sidecarWriteChains.remove(key);
      }
    });
    _sidecarWriteChains[key] = next;
    return next;
  }

  Future<void> flushSidecarWrites() async {
    while (_sidecarWriteChains.isNotEmpty) {
      await Future.wait(
        _sidecarWriteChains.values.toList(),
        eagerError: false,
      );
    }
  }

  Future<void> _atomicWriteString(
    File target,
    String content, {
    bool flush = true,
  }) async {
    final parent = target.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final tmp = File(
      '${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}.${++_tmpWriteSeq}',
    );
    try {
      await tmp.writeAsString(content, flush: flush);
      await tmp.rename(target.path);
    } catch (_) {
      try {
        await target.writeAsString(content, flush: flush);
      } finally {
        try {
          if (await tmp.exists()) {
            await tmp.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<Directory> getRootDirectory() async {
    final base = _overrideBaseDir ?? await getApplicationDocumentsDirectory();
    final root = Directory('${base.path}${Platform.pathSeparator}chemnote');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> _getSubdirectory(String name) async {
    final root = await getRootDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _getFoldersFile() async {
    final root = await getRootDirectory();
    return File('${root.path}${Platform.pathSeparator}folders.json');
  }

  Future<File> _getFavoritePensFile() async {
    final root = await getRootDirectory();
    return File('${root.path}${Platform.pathSeparator}favorite_pens.json');
  }

  Future<File> _getCustomStickersFile() async {
    final root = await getRootDirectory();
    return File('${root.path}${Platform.pathSeparator}custom_stickers.json');
  }

  Future<File> _getCustomCoversFile() async {
    final root = await getRootDirectory();
    return File('${root.path}${Platform.pathSeparator}custom_covers.json');
  }

  Future<File> _getRandomCoversFile() async {
    final root = await getRootDirectory();
    return File('${root.path}${Platform.pathSeparator}random_covers.json');
  }

  Future<File> _getPdfExportDirFile() async {
    final root = await getRootDirectory();
    return File('${root.path}${Platform.pathSeparator}pdf_export_dir.txt');
  }

  Future<File> _getImportDirFile() async {
    final root = await getRootDirectory();
    return File('${root.path}${Platform.pathSeparator}import_dir.txt');
  }

  Future<File> _getPenPrefsFile() async {
    final root = await getRootDirectory();
    return File('${root.path}${Platform.pathSeparator}pen_prefs.json');
  }

  Future<File> _getNotebookFile(String notebookId) async {
    final dir = await _getSubdirectory('notebooks');
    return File('${dir.path}${Platform.pathSeparator}$notebookId.json');
  }

  Future<List<Folder>> loadFolders() async {
    try {
      final file = await _getFoldersFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => Folder.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveFolders(List<Folder> folders) {
    return _enqueueSidecarWrite('folders', () async {
      final file = await _getFoldersFile();
      final encoded = jsonEncode(folders.map((f) => f.toJson()).toList());
      await _atomicWriteString(file, encoded, flush: true);
    });
  }

  Future<List<PenPreset>> loadFavoritePens() async {
    try {
      final file = await _getFavoritePensFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => PenPreset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveFavoritePens(List<PenPreset> pens) {
    return _enqueueSidecarWrite('favorite_pens', () async {
      try {
        final file = await _getFavoritePensFile();
        final encoded = jsonEncode(pens.map((p) => p.toJson()).toList());
        await _atomicWriteString(file, encoded, flush: true);
      } catch (_) {
        // Bỏ qua an toàn nếu chạy trên môi trường không có quyền ghi tệp.
      }
    });
  }

  Future<List<String>> loadCustomStickers() async {
    try {
      final file = await _getCustomStickersFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCustomStickers(List<String> stickerPaths) {
    return _enqueueSidecarWrite('custom_stickers', () async {
      try {
        final file = await _getCustomStickersFile();
        await _atomicWriteString(file, jsonEncode(stickerPaths), flush: true);
      } catch (_) {
        // Bỏ qua an toàn nếu chạy trên môi trường không có quyền ghi tệp.
      }
    });
  }

  Future<List<String>> loadCustomCovers() async {
    try {
      final file = await _getCustomCoversFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCustomCovers(List<String> coverPaths) {
    return _enqueueSidecarWrite('custom_covers', () async {
      try {
        final file = await _getCustomCoversFile();
        await _atomicWriteString(file, jsonEncode(coverPaths), flush: true);
      } catch (_) {
        // Bỏ qua an toàn nếu chạy trên môi trường không có quyền ghi tệp.
      }
    });
  }

  Future<List<String>> loadRandomCovers() async {
    try {
      final file = await _getRandomCoversFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRandomCovers(List<String> coverPaths) {
    return _enqueueSidecarWrite('random_covers', () async {
      try {
        final file = await _getRandomCoversFile();
        await _atomicWriteString(file, jsonEncode(coverPaths), flush: true);
      } catch (_) {
        // Bỏ qua an toàn nếu chạy trên môi trường không có quyền ghi tệp.
      }
    });
  }

  Future<String?> loadPdfExportDirectory() async {
    try {
      final file = await _getPdfExportDirFile();
      if (!await file.exists()) return null;
      final raw = (await file.readAsString()).trim();
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  Future<void> savePdfExportDirectory(String? directory) async {
    try {
      final file = await _getPdfExportDirFile();
      if (directory == null || directory.trim().isEmpty) {
        if (await file.exists()) await file.delete();
      } else {
        await _atomicWriteString(file, directory.trim(), flush: true);
      }
    } catch (_) {
      // Bỏ qua an toàn nếu chạy trên môi trường không có quyền ghi tệp.
    }
  }

  Future<String?> loadImportDirectory() async {
    try {
      final file = await _getImportDirFile();
      if (!await file.exists()) return null;
      final raw = (await file.readAsString()).trim();
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveImportDirectory(String? directory) async {
    try {
      final file = await _getImportDirFile();
      if (directory == null || directory.trim().isEmpty) {
        if (await file.exists()) await file.delete();
      } else {
        await _atomicWriteString(file, directory.trim(), flush: true);
      }
    } catch (_) {
      // Bỏ qua an toàn nếu chạy trên môi trường không có quyền ghi tệp.
    }
  }

  Future<Map<String, dynamic>> loadPenPrefs() async {
    try {
      final file = await _getPenPrefsFile();
      if (!await file.exists()) return const {};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> savePenPrefs(Map<String, dynamic> prefs) {
    return _enqueueSidecarWrite('pen_prefs', () async {
      try {
        final file = await _getPenPrefsFile();
        await _atomicWriteString(file, jsonEncode(prefs), flush: true);
      } catch (_) {
        // Bỏ qua an toàn nếu chạy trên môi trường không có quyền ghi tệp.
      }
    });
  }

  Future<List<Notebook>> loadNotebooks() async {
    try {
      final dir = await _getSubdirectory('notebooks');
      final entities = await dir.list().toList();
      final files = entities
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      final notebooks = <Notebook>[];
      const int batchSize = 6;
      for (int i = 0; i < files.length; i += batchSize) {
        final end =
            (i + batchSize < files.length) ? i + batchSize : files.length;
        final batch = files.sublist(i, end);
        final decodedBatch = await Future.wait(
          batch.map((file) async {
            try {
              final raw = await file.readAsString();
              if (raw.trim().isEmpty) return null;
              if (raw.length > 48 * 1024) {
                return await compute(_decodeNotebookFromJsonString, raw);
              }
              return _decodeNotebookFromJsonString(raw);
            } catch (_) {
              return null;
            }
          }),
        );
        for (final nb in decodedBatch) {
          if (nb != null) notebooks.add(nb);
        }
      }
      notebooks.sort((a, b) {
        final cmp = b.effectiveOpenedAt.compareTo(a.effectiveOpenedAt);
        if (cmp != 0) return cmp;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return notebooks;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNotebook(Notebook notebook) {
    _latestPendingNotebookWrites[notebook.id] = notebook;
    final prev = _notebookWriteChains[notebook.id] ?? Future<void>.value();
    final Future<void> next = prev.catchError((_) {}).then((_) async {
      final latest = _latestPendingNotebookWrites.remove(notebook.id);
      if (latest == null) return;
      final file = await _getNotebookFile(latest.id);
      final encoded = await compute(_serializeNotebookToJson, latest);
      await _atomicWriteString(file, encoded, flush: false);
    });
    late final Future<void> tracked;
    tracked = next.whenComplete(() {
      if (identical(_notebookWriteChains[notebook.id], tracked)) {
        _notebookWriteChains.remove(notebook.id);
      }
    });
    _notebookWriteChains[notebook.id] = tracked;
    return tracked;
  }

  Future<void> saveNotebooks(List<Notebook> notebooks) async {
    for (final notebook in notebooks) {
      await saveNotebook(notebook);
    }
  }

  Future<void> deleteNotebookFile(String notebookId) async {
    _latestPendingNotebookWrites.remove(notebookId);
    final inflight = _notebookWriteChains[notebookId];
    if (inflight != null) {
      try {
        await inflight;
      } catch (_) {}
    }
    final file = await _getNotebookFile(notebookId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Lưu tệp ảnh hoặc PDF được nhập vào thư mục ứng dụng để dùng offline ổn định.
  Future<String> saveImportedFile(
    File sourceFile, {
    String subfolder = 'assets',
  }) async {
    final dir = await _getSubdirectory(subfolder);
    final originalName = sourceFile.uri.pathSegments.isNotEmpty
        ? sourceFile.uri.pathSegments.last
        : 'file';
    final sanitized = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final targetPath =
        '${dir.path}${Platform.pathSeparator}${_uuid.v4()}_$sanitized';
    final copied = await sourceFile.copy(targetPath);
    return copied.path;
  }

  /// Lưu dữ liệu nhị phân (ảnh chụp, trang PDF xuất) vào thư mục ứng dụng.
  Future<String> saveAssetBytes(
    Uint8List bytes,
    String fileName, {
    String subfolder = 'assets',
  }) async {
    final dir = await _getSubdirectory(subfolder);
    final sanitized = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final targetPath =
        '${dir.path}${Platform.pathSeparator}${_uuid.v4()}_$sanitized';
    final file = File(targetPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Directory> getExportDirectory() => _getSubdirectory('exports');

  /// Dọn dẹp các tệp tài nguyên mồ côi trong `images`, `pdfs`, `audio`, `attachments`
  /// không còn được tham chiếu bởi bất kỳ sổ tay nào (giữ nguyên toàn bộ sổ trong Thùng rác).
  Future<int> cleanupOrphanAssets(
    List<Notebook> allNotebooks, {
    List<String> customStickers = const [],
    List<String> customCovers = const [],
  }) async {
    try {
      final referenced = <String>{};
      void addPath(String? raw) {
        if (raw == null || raw.trim().isEmpty) return;
        referenced.add(File(raw).absolute.path);
      }

      for (final path in customStickers) {
        addPath(path);
      }
      for (final path in customCovers) {
        addPath(path);
      }
      for (final notebook in allNotebooks) {
        addPath(notebook.customCoverImagePath);
        for (final page in notebook.pages) {
          if (page.pdfBackgroundPath != null &&
              page.pdfBackgroundPath!.trim().isNotEmpty) {
            addPath(page.pdfBackgroundPath);
            addPath('${page.pdfBackgroundPath}.thumb.png');
          }
          for (final img in page.imageElements) {
            addPath(img.filePath);
          }
          for (final att in page.attachmentElements) {
            addPath(att.filePath);
          }
          for (final rec in page.audioRecordings) {
            addPath(rec.filePath);
          }
        }
      }

      final root = await getRootDirectory();
      const subfolders = [
        'images',
        'pdfs',
        'pdf_pages',
        'docx_media',
        'audio',
        'attachments',
      ];
      int deletedCount = 0;
      for (final sub in subfolders) {
        final dir = Directory('${root.path}${Platform.pathSeparator}$sub');
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final absPath = entity.absolute.path;
            if (!referenced.contains(absPath)) {
              try {
                await entity.delete();
                deletedCount++;
              } catch (_) {}
            }
          }
        }
      }
      return deletedCount;
    } catch (_) {
      return 0;
    }
  }
}
