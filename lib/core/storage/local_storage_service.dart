import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/drawing_elements.dart';
import '../models/folder.dart';
import '../models/notebook.dart';

class LocalStorageService {
  final Directory? _overrideBaseDir;
  final Uuid _uuid;

  LocalStorageService({
    Directory? baseDirectory,
    Uuid? uuid,
  })  : _overrideBaseDir = baseDirectory,
        _uuid = uuid ?? const Uuid();

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

  Future<void> saveFolders(List<Folder> folders) async {
    final file = await _getFoldersFile();
    final encoded = jsonEncode(folders.map((f) => f.toJson()).toList());
    await file.writeAsString(encoded, flush: true);
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

  Future<void> saveFavoritePens(List<PenPreset> pens) async {
    try {
      final file = await _getFavoritePensFile();
      final encoded = jsonEncode(pens.map((p) => p.toJson()).toList());
      await file.writeAsString(encoded, flush: true);
    } catch (_) {
      // Bỏ qua an toàn nếu chạy trên môi trường không có quyền ghi tệp.
    }
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

  Future<void> saveCustomStickers(List<String> stickerPaths) async {
    try {
      final file = await _getCustomStickersFile();
      await file.writeAsString(jsonEncode(stickerPaths), flush: true);
    } catch (_) {
      // Bỏ qua an toàn nếu chạy trên môi trường không có quyền ghi tệp.
    }
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

  Future<void> saveCustomCovers(List<String> coverPaths) async {
    try {
      final file = await _getCustomCoversFile();
      await file.writeAsString(jsonEncode(coverPaths), flush: true);
    } catch (_) {
      // Bỏ qua an toàn nếu chạy trên môi trường không có quyền ghi tệp.
    }
  }

  Future<List<Notebook>> loadNotebooks() async {
    try {
      final dir = await _getSubdirectory('notebooks');
      final entities = await dir.list().toList();
      final notebooks = <Notebook>[];
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final raw = await entity.readAsString();
            if (raw.trim().isEmpty) continue;
            final decoded = jsonDecode(raw) as Map<String, dynamic>;
            notebooks.add(Notebook.fromJson(decoded));
          } catch (_) {
            // Bỏ qua tệp bị hỏng để không ảnh hưởng toàn bộ thư viện.
          }
        }
      }
      notebooks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return notebooks;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNotebook(Notebook notebook) async {
    final file = await _getNotebookFile(notebook.id);
    final encoded = jsonEncode(notebook.toJson());
    await file.writeAsString(encoded, flush: true);
  }

  Future<void> saveNotebooks(List<Notebook> notebooks) async {
    for (final notebook in notebooks) {
      await saveNotebook(notebook);
    }
  }

  Future<void> deleteNotebookFile(String notebookId) async {
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
}
