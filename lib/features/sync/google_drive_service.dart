import 'dart:convert';

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
    final derivedId = name.endsWith('.chemnote.json')
        ? name.substring(0, name.length - '.chemnote.json'.length)
        : null;

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
/// Lưu trữ mỗi sổ tay dưới dạng `<notebookId>.chemnote.json` trong thư mục `ChemNote_Backups`.
class GoogleDriveService {
  GoogleDriveService({
    required GoogleAuthService authService,
    http.Client? httpClient,
  })  : _authService = authService,
        _httpClient = httpClient ?? http.Client();

  static const String appFolderName = 'ChemNote_Backups';
  static const String _driveFilesBase =
      'https://www.googleapis.com/drive/v3/files';
  static const String _driveUploadBase =
      'https://www.googleapis.com/upload/drive/v3/files';
  static const String _folderMimeType = 'application/vnd.google-apps.folder';

  final GoogleAuthService _authService;
  final http.Client _httpClient;

  String? _cachedFolderId;

  // Kho lưu trữ mô phỏng trong bộ nhớ khi hoạt động ở Chế độ Demo.
  final Map<String, Notebook> _demoRemoteStore = <String, Notebook>{};

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

  /// Tìm hoặc tạo thư mục `ChemNote_Backups` trên Google Drive.
  Future<String> ensureAppFolder() async {
    if (_authService.isDemoMode) {
      _cachedFolderId = 'demo_folder_chemnote_backups';
      return _cachedFolderId!;
    }

    if (_cachedFolderId != null && _cachedFolderId!.isNotEmpty) {
      return _cachedFolderId!;
    }

    final headers = await _authHeaders();
    final query =
        "name = '$appFolderName' and mimeType = '$_folderMimeType' and trashed = false";
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
        'Không thể tìm thư mục sao lưu trên Drive (${searchRes.statusCode}).',
        statusCode: searchRes.statusCode,
      );
    }

    final searchData = jsonDecode(searchRes.body) as Map<String, dynamic>;
    final files = searchData['files'] as List<dynamic>? ?? const [];
    if (files.isNotEmpty) {
      final first = files.first as Map<String, dynamic>;
      _cachedFolderId = first['id'] as String;
      return _cachedFolderId!;
    }

    // Tạo thư mục mới nếu chưa tồn tại
    final createRes = await _httpClient.post(
      Uri.parse(_driveFilesBase),
      headers: await _authHeaders(
        extra: const <String, String>{'Content-Type': 'application/json'},
      ),
      body: jsonEncode(<String, dynamic>{
        'name': appFolderName,
        'mimeType': _folderMimeType,
      }),
    );

    if (createRes.statusCode < 200 || createRes.statusCode >= 300) {
      throw GoogleDriveException(
        'Không thể tạo thư mục $appFolderName trên Drive (${createRes.statusCode}).',
        statusCode: createRes.statusCode,
      );
    }

    final created = jsonDecode(createRes.body) as Map<String, dynamic>;
    _cachedFolderId = created['id'] as String;
    return _cachedFolderId!;
  }

  /// Liệt kê tất cả tệp `.chemnote.json` trong thư mục `ChemNote_Backups`.
  Future<List<DriveNotebookMeta>> listRemoteNotebooks() async {
    if (_authService.isDemoMode) {
      return _demoRemoteStore.entries.map((entry) {
        final nb = entry.value;
        return DriveNotebookMeta(
          driveFileId: entry.key,
          name: '${nb.id}.chemnote.json',
          modifiedTime: nb.updatedAt,
          notebookId: nb.id,
        );
      }).toList()
        ..sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    }

    final folderId = await ensureAppFolder();
    final headers = await _authHeaders();
    final query =
        "'$folderId' in parents and trashed = false and name contains '.chemnote.json'";

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
    return files
        .map((e) => DriveNotebookMeta.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Tải lên hoặc cập nhật một sổ tay dạng `.chemnote.json` bằng multipart upload.
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

    final folderId = await ensureAppFolder();
    final fileName = '${notebook.id}.chemnote.json';
    final existingFileId = notebook.driveFileId;

    final metadata = <String, dynamic>{
      'name': fileName,
      'mimeType': 'application/json',
      'appProperties': <String, String>{
        'notebookId': notebook.id,
        'title': notebook.title,
      },
      if (existingFileId == null || existingFileId.isEmpty)
        'parents': <String>[folderId],
    };

    final payloadJson = jsonEncode(
      notebook.copyWith(syncStatus: SyncStatus.synced).toJson(),
    );

    final boundary = 'chemnote_boundary_${DateTime.now().millisecondsSinceEpoch}';
    final bodyBuffer = StringBuffer()
      ..write('--$boundary\r\n')
      ..write('Content-Type: application/json; charset=UTF-8\r\n\r\n')
      ..write(jsonEncode(metadata))
      ..write('\r\n--$boundary\r\n')
      ..write('Content-Type: application/json; charset=UTF-8\r\n\r\n')
      ..write(payloadJson)
      ..write('\r\n--$boundary--\r\n');

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
        body: utf8.encode(bodyBuffer.toString()),
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
        body: utf8.encode(bodyBuffer.toString()),
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleDriveException(
        'Tải lên sổ tay "${notebook.title}" thất bại (${response.statusCode}).',
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

  /// Xóa tệp sổ tay trên Google Drive theo `driveFileId`.
  Future<void> deleteRemoteNotebook(String driveFileId) async {
    if (_authService.isDemoMode) {
      _demoRemoteStore.remove(driveFileId);
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
  }
}
