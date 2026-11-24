import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cấu hình OAuth 2.0 + PKCE cho Google Drive (không phụ thuộc Google Play Services / GMS).
/// Hoạt động trên cả Android tiêu chuẩn và Huawei HarmonyOS 2/3/4 thông qua trình duyệt hệ thống.
class GoogleOAuthConfig {
  GoogleOAuthConfig({FlutterSecureStorage? secureStorage})
      : _storage = secureStorage ?? const FlutterSecureStorage();

  /// Custom URI scheme đã khai báo trong AndroidManifest.xml.
  static const String redirectScheme = 'com.chemnote.app';

  /// Redirect URI chuẩn cho Native Android/HarmonyOS OAuth 2.0 client.
  static const String redirectUri = 'com.chemnote.app:/oauth2redirect';

  /// Quyền truy cập chỉ các tệp do ChemNote tạo trên Google Drive (an toàn & riêng tư).
  static const String driveFileScope =
      'https://www.googleapis.com/auth/drive.file';

  /// Danh sách scope đầy đủ để lấy thông tin hồ sơ cơ bản và đồng bộ Drive.
  static const List<String> scopes = <String>[
    driveFileScope,
    'openid',
    'email',
    'profile',
  ];

  /// Các endpoint chính thức của Google OAuth 2.0.
  static const String authorizationEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const String tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String revocationEndpoint =
      'https://oauth2.googleapis.com/revoke';
  static const String userInfoEndpoint =
      'https://www.googleapis.com/oauth2/v3/userinfo';

  /// Key lưu Client ID và Client Secret tùy chỉnh do người dùng cấu hình.
  static const String _clientIdStorageKey = 'chemnote_google_oauth_client_id';
  static const String _clientSecretStorageKey =
      'chemnote_google_oauth_client_secret';

  /// Giá trị mặc định (trống -> ứng dụng sẽ gợi ý nhập Client ID hoặc dùng Chế độ Demo).
  static const String defaultClientId = '';
  static const String defaultClientSecret = '';

  final FlutterSecureStorage _storage;

  /// Đọc OAuth Client ID hiện đang cấu hình (ưu tiên giá trị đã lưu trong Secure Storage).
  Future<String> loadClientId() async {
    try {
      final stored = await _storage.read(key: _clientIdStorageKey);
      if (stored != null && stored.trim().isNotEmpty) {
        return stored.trim();
      }
    } catch (_) {
      // Bỏ qua lỗi đọc storage trên môi trường test không có plugin platform.
    }
    return defaultClientId;
  }

  /// Lưu OAuth Client ID của người dùng (dạng `xxxx.apps.googleusercontent.com`).
  Future<void> saveClientId(String clientId) async {
    final trimmed = clientId.trim();
    if (trimmed.isEmpty) {
      await clearClientId();
      return;
    }
    await _storage.write(key: _clientIdStorageKey, value: trimmed);
  }

  /// Xóa OAuth Client ID đã lưu để quay về mặc định / Chế độ Demo.
  Future<void> clearClientId() async {
    try {
      await _storage.delete(key: _clientIdStorageKey);
    } catch (_) {}
  }

  /// Đọc OAuth Client Secret (dùng cho loại Google Cloud Console `Desktop app`).
  Future<String> loadClientSecret() async {
    try {
      final stored = await _storage.read(key: _clientSecretStorageKey);
      if (stored != null && stored.trim().isNotEmpty) {
        return stored.trim();
      }
    } catch (_) {
      // Bỏ qua lỗi đọc storage trên môi trường test không có plugin platform.
    }
    return defaultClientSecret;
  }

  /// Lưu OAuth Client Secret (dạng `GOCSPX-...`).
  Future<void> saveClientSecret(String clientSecret) async {
    final trimmed = clientSecret.trim();
    if (trimmed.isEmpty) {
      await clearClientSecret();
      return;
    }
    await _storage.write(key: _clientSecretStorageKey, value: trimmed);
  }

  /// Xóa OAuth Client Secret đã lưu.
  Future<void> clearClientSecret() async {
    try {
      await _storage.delete(key: _clientSecretStorageKey);
    } catch (_) {}
  }

  /// Kiểm tra xem người dùng đã cấu hình Google OAuth Client ID hợp lệ hay chưa.
  Future<bool> hasConfiguredClientId() async {
    final id = await loadClientId();
    return id.isNotEmpty;
  }

  /// Tạo URL ủy quyền OAuth 2.0 với PKCE (S256) và access_type=offline để lấy refresh_token.
  /// Hỗ trợ `redirectUriOverride` cho RFC 8252 Loopback IP Redirect (`http://127.0.0.1:<port>/oauth2redirect`).
  Uri buildAuthorizationUri({
    required String clientId,
    required String codeChallenge,
    required String state,
    String? redirectUriOverride,
  }) {
    return Uri.parse(authorizationEndpoint).replace(
      queryParameters: <String, String>{
        'client_id': clientId,
        'redirect_uri': redirectUriOverride ?? redirectUri,
        'response_type': 'code',
        'scope': scopes.join(' '),
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
      },
    );
  }
}
