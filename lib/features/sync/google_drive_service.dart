import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/models/notebook.dart';
import 'google_auth_service.dart';

/// Siêu dữ liệu của một tệp sổ tay `.chemnote.json` lưu trên Google Drive.
class DriveNotebookMeta {
  const DriveNotebookMeta({
    required this.driveFileId,
    required this.name,
    required this.modifiedTime,
    this.notebookId,
    this.sizeBytes,
  });

  final String driveFileId;
  final String name;
  final DateTime modifiedTime;
  final String? notebookId;
  final int? sizeBytes;

  factory DriveNotebookMeta.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    final appProps = json['appProperties'] as Map<String, dynamic>?;
    final rawNotebookId = appProps?['notebookId'] as String?;
    String? derivedId;
    if (name.endsWith('.chemnote.json')) {
      final stem = name.substring(0, name.length - '.chemnote.json'.length);
      derivedId = stem;
    }

    return DriveNotebookMeta(
      driveFileId: json['id'] as String,
      name: name,
      modifiedTime: json['modifiedTime'] != null
          ? DateTime.tryParse(json['modifiedTime'] as String) ?? DateTime.now()
          : DateTime.now(),
      notebookId: rawNotebookId ?? derivedId,
      sizeBytes: json['size'] != null ? int.tryParse('${json['size']}') : null,
    );
  }
}

/// Ngoại lệ khi gọi Google Drive REST API v3.
class GoogleDriveException implements Exception {
  const GoogleDriveException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Khách hàng Google Drive REST API v3 thuần `http` (không cần Google Play Services / GMS).
/// Tổ chức sao lưu theo 2 thư mục con trong `ChemNote_Backups`:
/// - `ChemNote_Backups/JSON/`: tệp `.chemnote.json` đầy đủ để đồng bộ & chỉnh sửa.
/// - `ChemNote_Backups/PDF/`: tệp PDF vector nhẹ đặt tên bắt đầu bằng tiêu đề sổ tay.
class GoogleDriveService {
  GoogleDriveService({
    required GoogleAuthService authService,
    http.Client? httpClient,
  })  : _authService = authService,
        _httpClient = httpClient ?? http.Client();

  static const String appFolderName = 'ChemNote_Backups';
  static const String jsonFolderName = 'JSON';
  static const String pdfFolderName = 'PDF';
  static const String _driveFilesBase =
      'https://www.googleapis.com/drive/v3/files';
  static const String _driveUploadBase =
      'https://www.googleapis.com/upload/drive/v3/files';
  static const String _folderMimeType = 'application/vnd.google-apps.folder';

  final GoogleAuthService _authService;
  final http.Client _httpClient;

  String? _cachedFolderId;
  String? _cachedJsonFolderId;
  String? _cachedPdfFolderId;

  // Kho lưu trữ mô phỏng trong bộ nhớ khi hoạt động ở Chế độ Demo.
  final Map<String, Notebook> _demoRemoteStore = <String, Notebook>{};
  final Map<String, Uint8List> _demoRemotePdfStore = <String, Uint8List>{};

  /// Làm sạch tên sổ tay cho Google Drive (giữ nguyên tiếng Việt có dấu, loại ký tự cấm).
  static String _sanitizeDriveTitle(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Sổ tay ChemNote' : cleaned;
  }

  static String _shortId(String id) {
    final compact = id.replaceAll('-', '');
    return compact.length <= 8 ? compact : compact.substring(0, 8);
  }

  /// Tên tệp JSON trong `ChemNote_Backups/JSON/`: `<SafeTitle>_<shortId>.chemnote.json`.
  static String formatJsonFileName(Notebook notebook) {
    final safeTitle = _sanitizeDriveTitle(notebook.title).replaceAll(' ', '_');
    return '${safeTitle}_${_shortId(notebook.id)}.chemnote.json';
  }

  /// Tên tệp PDF trong `ChemNote_Backups/PDF/`: luôn bắt đầu bằng tên ghi chú `<Ten_Ghi_Chu> [<shortId>].pdf`.
  static String formatPdfFileName(Notebook notebook) {
    final safeTitle = _sanitizeDriveTitle(notebook.title);
    return '$safeTitle [${_shortId(notebook.id)}].pdf';
  }

  Future<Map<String, String>> _authHeaders({
    Map<String, String>? extra,
  }) async {
    final token = await _authService.getValidAccessToken();
    if (token == null || token.isEmpty) {
      throw const GoogleDriveException(
        'Phiên đăng nhập Google đã hết hạn. Vui lòng đăng nhập lại.',
        statusCode: 401,
      );
    }
    return <String, String>{
      'Authorization': 'Bearer $token',
      if (extra != null) ...extra,
    };
  }

  /// Tìm hoặc tạo thư mục gốc `ChemNote_Backups` trên Google Drive.
  Future<String> ensureAppFolder() async {
    if (_authService.isDemoMode) {
      _cachedFolderId = 'demo_folder_chemnote_backups';
      return _cachedFolderId!;
    }

    if (_cachedFolderId != null && _cachedFolderId!.isNotEmpty) {
      return _cachedFolderId!;
    }

    _cachedFolderId = await _ensureFolder(name: appFolderName);
    return _cachedFolderId!;
  }

  /// Tìm hoặc tạo thư mục con `ChemNote_Backups/JSON`.
  Future<String> ensureJsonFolder() async {
    if (_authService.isDemoMode) {
      _cachedJsonFolderId = 'demo_folder_chemnote_json';
      return _cachedJsonFolderId!;
    }
    if (_cachedJsonFolderId != null && _cachedJsonFolderId!.isNotEmpty) {
      return _cachedJsonFolderId!;
    }
    final rootId = await ensureAppFolder();
    _cachedJsonFolderId =
        await _ensureFolder(name: jsonFolderName, parentId: rootId);
    return _cachedJsonFolderId!;
  }

  /// Tìm hoặc tạo thư mục con `ChemNote_Backups/PDF`.
  Future<String> ensurePdfFolder() async {
    if (_authService.isDemoMode) {
      _cachedPdfFolderId = 'demo_folder_chemnote_pdf';
      return _cachedPdfFolderId!;
    }
    if (_cachedPdfFolderId != null && _cachedPdfFolderId!.isNotEmpty) {
      return _cachedPdfFolderId!;
    }
    final rootId = await ensureAppFolder();
    _cachedPdfFolderId =
        await _ensureFolder(name: pdfFolderName, parentId: rootId);
    return _cachedPdfFolderId!;
  }

  Future<String> _ensureFolder({
    required String name,
    String? parentId,
  }) async {
    final headers = await _authHeaders();
    final parentClause = parentId != null ? " and '$parentId' in parents" : '';
    final query =
        "name = '$name' and mimeType = '$_folderMimeType' and trashed = false$parentClause";
    final searchUri = Uri.parse(_driveFilesBase).replace(
      queryParameters: <String, String>{
        'q': query,
        'spaces': 'drive',
        'fields': 'files(id, name)',
        'pageSize': '5',
      },
    );

    final searchRes = await _httpClient.get(searchUri, headers: headers);
    if (searchRes.statusCode < 200 || searchRes.statusCode >= 300) {
      throw GoogleDriveException(
        'Không thể tìm thư mục "$name" trên Drive (${searchRes.statusCode}).',
        statusCode: searchRes.statusCode,
      );
    }

    final searchData = jsonDecode(searchRes.body) as Map<String, dynamic>;
    final files = searchData['files'] as List<dynamic>? ?? const [];
    if (files.isNotEmpty) {
      final first = files.first as Map<String, dynamic>;
      return first['id'] as String;
    }

    final createBody = <String, dynamic>{
      'name': name,
      'mimeType': _folderMimeType,
      if (parentId != null) 'parents': <String>[parentId],
    };
    final createRes = await _httpClient.post(
      Uri.parse(_driveFilesBase),
      headers: await _authHeaders(
        extra: const <String, String>{'Content-Type': 'application/json'},
      ),
      body: jsonEncode(createBody),
    );

    if (createRes.statusCode < 200 || createRes.statusCode >= 300) {
      throw GoogleDriveException(
        'Không thể tạo thư mục "$name" trên Drive (${createRes.statusCode}).',
        statusCode: createRes.statusCode,
      );
    }

    final created = jsonDecode(createRes.body) as Map<String, dynamic>;
    return created['id'] as String;
  }

  /// Liệt kê tất cả tệp `.chemnote.json` trong `ChemNote_Backups/JSON/`
  /// (và tương thích ngược với các tệp cũ nằm trực tiếp trong `ChemNote_Backups/`).
  Future<List<DriveNotebookMeta>> listRemoteNotebooks() async {
    if (_authService.isDemoMode) {
      return _demoRemoteStore.entries.map((entry) {
        final nb = entry.value;
        return DriveNotebookMeta(
          driveFileId: entry.key,
          name: formatJsonFileName(nb),
          modifiedTime: nb.updatedAt,
          notebookId: nb.id,
        );
      }).toList()
        ..sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    }

    final rootId = await ensureAppFolder();
    final jsonFolderId = await ensureJsonFolder();
    final headers = await _authHeaders();
    final query =
        "('$jsonFolderId' in parents or '$rootId' in parents) and trashed = false and name contains '.chemnote.json'";

    final uri = Uri.parse(_driveFilesBase).replace(
      queryParameters: <String, String>{
        'q': query,
        'spaces': 'drive',
        'fields': 'files(id, name, modifiedTime, size, appProperties)',
        'orderBy': 'modifiedTime desc',
        'pageSize': '200',
      },
    );

    final response = await _httpClient.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(
        'Không thể tải danh sách sổ tay trên Drive (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files = data['files'] as List<dynamic>? ?? const [];
    final seenNotebookIds = <String>{};
    final result = <DriveNotebookMeta>[];
    for (final raw in files) {
      final meta = DriveNotebookMeta.fromJson(raw as Map<String, dynamic>);
      final key = meta.notebookId ?? meta.driveFileId;
      if (seenNotebookIds.add(key)) {
        result.add(meta);
      }
    }
    return result;
  }

  /// Tải lên hoặc cập nhật sổ tay dạng `.chemnote.json` vào `ChemNote_Backups/JSON/`.
  /// Trả về `driveFileId` trên Google Drive.
  Future<String> uploadNotebook(Notebook notebook) async {
    if (_authService.isDemoMode) {
      final fileId = notebook.driveFileId ?? 'demo_drive_${notebook.id}';
      _demoRemoteStore[fileId] = notebook.copyWith(
        driveFileId: fileId,
        syncStatus: SyncStatus.synced,
      );
      return fileId;
    }

    final jsonFolderId = await ensureJsonFolder();
    final fileName = formatJsonFileName(notebook);
    final existingFileId = notebook.driveFileId;

    final metadata = <String, dynamic>{
      'name': fileName,
      'mimeType': 'application/json',
      'appProperties': <String, String>{
        'notebookId': notebook.id,
        'title': notebook.title,
      },
      if (existingFileId == null || existingFileId.isEmpty)
        'parents': <String>[jsonFolderId],
    };

    final payloadJson = jsonEncode(
      notebook.copyWith(syncStatus: SyncStatus.synced).toJson(),
    );

    return _multipartUploadBytes(
      metadata: metadata,
      contentBytes: Uint8List.fromList(utf8.encode(payloadJson)),
      contentMimeType: 'application/json; charset=UTF-8',
      existingFileId: existingFileId,
      errorLabel: 'sổ tay JSON "${notebook.title}"',
    );
  }

  /// Tải lên hoặc cập nhật bản PDF vector nhẹ vào `ChemNote_Backups/PDF/`
  /// với tên bắt đầu bằng tiêu đề sổ tay (`<Ten_Ghi_Chu> [<shortId>].pdf`).
  /// Trả về `drivePdfFileId` trên Google Drive.
  Future<String> uploadNotebookPdf(
    Notebook notebook,
    Uint8List pdfBytes,
  ) async {
    if (_authService.isDemoMode) {
      final pdfId = notebook.drivePdfFileId ?? 'demo_pdf_${notebook.id}';
      _demoRemotePdfStore[pdfId] = pdfBytes;
      return pdfId;
    }

    final pdfFolderId = await ensurePdfFolder();
    final fileName = formatPdfFileName(notebook);
    final existingPdfId = notebook.drivePdfFileId;

    final metadata = <String, dynamic>{
      'name': fileName,
      'mimeType': 'application/pdf',
      'appProperties': <String, String>{
        'notebookId': notebook.id,
        'title': notebook.title,
        'kind': 'pdf_vector',
      },
      if (existingPdfId == null || existingPdfId.isEmpty)
        'parents': <String>[pdfFolderId],
    };

    return _multipartUploadBytes(
      metadata: metadata,
      contentBytes: pdfBytes,
      contentMimeType: 'application/pdf',
      existingFileId: existingPdfId,
      errorLabel: 'tệp PDF "${notebook.title}"',
    );
  }

  Future<String> _multipartUploadBytes({
    required Map<String, dynamic> metadata,
    required Uint8List contentBytes,
    required String contentMimeType,
    required String? existingFileId,
    required String errorLabel,
  }) async {
    final boundary = 'chemnote_boundary_${DateTime.now().millisecondsSinceEpoch}';
    final bodyBuilder = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'))
      ..add(utf8.encode(jsonEncode(metadata)))
      ..add(utf8.encode('\r\n--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: $contentMimeType\r\n\r\n'))
      ..add(contentBytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));

    final headers = await _authHeaders(
      extra: <String, String>{
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
    );

    final http.Response response;
    if (existingFileId != null && existingFileId.isNotEmpty) {
      final updateUri = Uri.parse('$_driveUploadBase/$existingFileId').replace(
        queryParameters: const <String, String>{
          'uploadType': 'multipart',
          'fields': 'id, name, modifiedTime',
        },
      );
      response = await _httpClient.patch(
        updateUri,
        headers: headers,
        body: bodyBuilder.toBytes(),
      );
    } else {
      final createUri = Uri.parse(_driveUploadBase).replace(
        queryParameters: const <String, String>{
          'uploadType': 'multipart',
          'fields': 'id, name, modifiedTime',
        },
      );
      response = await _httpClient.post(
        createUri,
        headers: headers,
        body: bodyBuilder.toBytes(),
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(
        'Tải lên $errorLabel thất bại (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final driveId = result['id'] as String?;
    if (driveId == null || driveId.isEmpty) {
      throw const GoogleDriveException(
        'Google Drive không trả về mã tệp sau khi tải lên.',
      );
    }
    return driveId;
  }

  /// Tải xuống và phân tích JSON của một sổ tay từ Google Drive theo `driveFileId`.
  Future<Notebook> downloadNotebook(String driveFileId) async {
    if (_authService.isDemoMode) {
      final nb = _demoRemoteStore[driveFileId];
      if (nb == null) {
        throw const GoogleDriveException(
          'Không tìm thấy sổ tay trong bộ nhớ Demo.',
          statusCode: 404,
        );
      }
      return nb;
    }

    final uri = Uri.parse('$_driveFilesBase/$driveFileId').replace(
      queryParameters: const <String, String>{'alt': 'media'},
    );
    final response = await _httpClient.get(uri, headers: await _authHeaders());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(
        'Không thể tải xuống sổ tay từ Drive (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    final jsonMap =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return Notebook.fromJson(jsonMap).copyWith(
      driveFileId: driveFileId,
      syncStatus: SyncStatus.synced,
    );
  }

  /// Xóa tệp sổ tay (JSON hoặc PDF) trên Google Drive theo `driveFileId`.
  Future<void> deleteRemoteNotebook(String driveFileId) async {
    if (_authService.isDemoMode) {
      _demoRemoteStore.remove(driveFileId);
      _demoRemotePdfStore.remove(driveFileId);
      return;
    }

    final uri = Uri.parse('$_driveFilesBase/$driveFileId');
    final response =
        await _httpClient.delete(uri, headers: await _authHeaders());
    if (response.statusCode != 204 &&
        response.statusCode != 200 &&
        response.statusCode != 404) {
      throw GoogleDriveException(
        'Không thể xóa tệp trên Google Drive (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  /// Xóa cache thư mục (gọi khi người dùng đăng xuất hoặc đổi tài khoản).
  void resetSessionCache() {
    _cachedFolderId = null;
    _cachedJsonFolderId = null;
    _cachedPdfFolderId = null;
  }
}
