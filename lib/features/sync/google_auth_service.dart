import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'google_oauth_config.dart';

/// Thông tin tài khoản Google đang đăng nhập (hoặc tài khoản Demo ngoại tuyến).
class AuthUser {
  const AuthUser({
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.isDemoMode = false,
  });

  final String email;
  final String displayName;
  final String? photoUrl;
  final bool isDemoMode;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'isDemoMode': isDemoMode,
    };
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Người dùng ChemNote',
      photoUrl: json['photoUrl'] as String?,
      isDemoMode: json['isDemoMode'] as bool? ?? false,
    );
  }
}

/// Ngoại lệ xác thực Google OAuth 2.0 không phụ thuộc GMS.
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message, {this.needsClientId = false});

  final String message;
  final bool needsClientId;

  @override
  String toString() => message;
}

/// Dịch vụ xác thực Google OAuth 2.0 + PKCE không cần Google Play Services (GMS).
/// Tương thích hoàn toàn với Android tiêu chuẩn và Huawei HarmonyOS 2/3/4.
class GoogleAuthService {
  GoogleAuthService({
    GoogleOAuthConfig? config,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
  })  : _storage = secureStorage ?? const FlutterSecureStorage(),
        _config = config ??
            GoogleOAuthConfig(
              secureStorage: secureStorage ?? const FlutterSecureStorage(),
            ),
        _httpClient = httpClient ?? http.Client();

  static const String _kAccessToken = 'chemnote_oauth_access_token';
  static const String _kRefreshToken = 'chemnote_oauth_refresh_token';
  static const String _kExpiresAt = 'chemnote_oauth_expires_at';
  static const String _kUserProfile = 'chemnote_oauth_user_profile';
  static const String _kDemoMode = 'chemnote_oauth_demo_mode';

  final GoogleOAuthConfig _config;
  final FlutterSecureStorage _storage;
  final http.Client _httpClient;

  AuthUser? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  GoogleOAuthConfig get config => _config;
  AuthUser? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get isDemoMode => _currentUser?.isDemoMode ?? false;

  /// Khôi phục phiên đăng nhập đã lưu từ Secure Storage khi khởi động ứng dụng.
  Future<AuthUser?> loadSavedSession() async {
    try {
      final userRaw = await _storage.read(key: _kUserProfile);
      if (userRaw == null || userRaw.isEmpty) {
        _currentUser = null;
        return null;
      }

      final userMap = jsonDecode(userRaw) as Map<String, dynamic>;
      _currentUser = AuthUser.fromJson(userMap);
      _accessToken = await _storage.read(key: _kAccessToken);
      _refreshToken = await _storage.read(key: _kRefreshToken);

      final expiryStr = await _storage.read(key: _kExpiresAt);
      if (expiryStr != null && expiryStr.isNotEmpty) {
        _expiresAt = DateTime.tryParse(expiryStr);
      }

      return _currentUser;
    } catch (_) {
      return _currentUser;
    }
  }

  /// Đăng nhập Google bằng OAuth 2.0 + PKCE thông qua trình duyệt hệ thống
  /// với Custom URI Scheme `com.chemnote.app:/oauth2redirect` (GMS-free cho Android & HarmonyOS).
  Future<AuthUser> signIn() async {
    final clientId = await _config.loadClientId();
    if (clientId.isEmpty) {
      throw const GoogleAuthException(
        'Chưa cấu hình Google OAuth Client ID. Vui lòng nhập Android Client ID trong cài đặt hoặc sử dụng Chế độ Demo.',
        needsClientId: true,
      );
    }

    final codeVerifier = generateCodeVerifier();
    final codeChallenge = computeCodeChallenge(codeVerifier);
    final state = generateCodeVerifier(length: 32);

    final authUri = _config.buildAuthorizationUri(
      clientId: clientId,
      codeChallenge: codeChallenge,
      state: state,
    );

    final String callbackUrl;
    try {
      callbackUrl = await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme: GoogleOAuthConfig.redirectScheme,
      );
    } catch (e) {
      throw GoogleAuthException(
        'Đăng nhập bị hủy hoặc không thể mở trình duyệt: $e',
      );
    }

    final returnedUri = Uri.parse(callbackUrl);
    final error = returnedUri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      throw GoogleAuthException('Google từ chối cấp quyền: $error');
    }

    final returnedState = returnedUri.queryParameters['state'];
    if (returnedState != state) {
      throw const GoogleAuthException(
        'Xác thực không hợp lệ (tham số state không khớp). Vui lòng thử lại.',
      );
    }

    final authCode = returnedUri.queryParameters['code'];
    if (authCode == null || authCode.isEmpty) {
      throw const GoogleAuthException('Không nhận được mã ủy quyền từ Google.');
    }

    // Đổi authorization code lấy access_token và refresh_token (PKCE, không cần client_secret)
    final tokenResponse = await _httpClient.post(
      Uri.parse(GoogleOAuthConfig.tokenEndpoint),
      headers: const <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'client_id': clientId,
        'code': authCode,
        'code_verifier': codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': GoogleOAuthConfig.redirectUri,
      },
    );

    if (tokenResponse.statusCode < 200 || tokenResponse.statusCode >= 300) {
      throw GoogleAuthException(
        'Không thể đổi mã xác thực (${tokenResponse.statusCode}): ${tokenResponse.body}',
      );
    }

    final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    final accessToken = tokenData['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const GoogleAuthException('Phản hồi Google không chứa access_token.');
    }

    final refreshToken = tokenData['refresh_token'] as String?;
    final expiresIn = (tokenData['expires_in'] as num?)?.toInt() ?? 3600;
    final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));

    final user = await _fetchUserInfo(accessToken);

    _accessToken = accessToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
    }
    _expiresAt = expiresAt;
    _currentUser = user;

    await _persistSession();
    return user;
  }

  /// Đăng nhập nhanh ở Chế độ Demo (mô phỏng Google Drive cục bộ khi chưa có Client ID).
  Future<AuthUser> signInDemo() async {
    const demoUser = AuthUser(
      email: 'sinhvien.hoahoc@chemnote.demo',
      displayName: 'Sinh viên Hóa học (Demo)',
      photoUrl: null,
      isDemoMode: true,
    );

    _currentUser = demoUser;
    _accessToken = 'demo_access_token';
    _refreshToken = 'demo_refresh_token';
    _expiresAt = DateTime.now().add(const Duration(days: 365));

    await _persistSession();
    return demoUser;
  }

  /// Đăng xuất, thu hồi token với Google (nếu không phải Demo) và xóa dữ liệu lưu cục bộ.
  Future<void> signOut() async {
    final tokenToRevoke = _refreshToken ?? _accessToken;
    final wasDemo = isDemoMode;

    if (!wasDemo && tokenToRevoke != null && tokenToRevoke.isNotEmpty) {
      try {
        await _httpClient.post(
          Uri.parse(GoogleOAuthConfig.revocationEndpoint),
          headers: const <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: <String, String>{'token': tokenToRevoke},
        );
      } catch (_) {
        // Không chặn đăng xuất khi thiết bị đang ngoại tuyến.
      }
    }

    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;

    try {
      await _storage.delete(key: _kAccessToken);
      await _storage.delete(key: _kRefreshToken);
      await _storage.delete(key: _kExpiresAt);
      await _storage.delete(key: _kUserProfile);
      await _storage.delete(key: _kDemoMode);
    } catch (_) {}
  }

  /// Trả về access token còn hiệu lực; tự động làm mới bằng refresh_token nếu sắp hết hạn.
  Future<String?> getValidAccessToken() async {
    if (_currentUser == null) {
      await loadSavedSession();
    }
    if (_currentUser == null) {
      return null;
    }
    if (_currentUser!.isDemoMode) {
      return 'demo_access_token';
    }

    final now = DateTime.now();
    if (_accessToken != null &&
        _accessToken!.isNotEmpty &&
        _expiresAt != null &&
        _expiresAt!.isAfter(now.add(const Duration(minutes: 2)))) {
      return _accessToken;
    }

    return _refreshAccessToken();
  }

  Future<String?> _refreshAccessToken() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    final clientId = await _config.loadClientId();
    if (clientId.isEmpty) {
      return null;
    }

    try {
      final response = await _httpClient.post(
        Uri.parse(GoogleOAuthConfig.tokenEndpoint),
        headers: const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: <String, String>{
          'client_id': clientId,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final newAccessToken = data['access_token'] as String?;
      if (newAccessToken == null || newAccessToken.isEmpty) {
        return null;
      }

      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      _accessToken = newAccessToken;
      _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      await _persistSession();
      return _accessToken;
    } catch (_) {
      return null;
    }
  }

  Future<AuthUser> _fetchUserInfo(String accessToken) async {
    try {
      final response = await _httpClient.get(
        Uri.parse(GoogleOAuthConfig.userInfoEndpoint),
        headers: <String, String>{
          'Authorization': 'Bearer $accessToken',
        },
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return AuthUser(
          email: data['email'] as String? ?? 'google-user@gmail.com',
          displayName: data['name'] as String? ??
              data['email'] as String? ??
              'Người dùng Google',
          photoUrl: data['picture'] as String?,
          isDemoMode: false,
        );
      }
    } catch (_) {}

    return const AuthUser(
      email: 'google-user@gmail.com',
      displayName: 'Người dùng Google',
      isDemoMode: false,
    );
  }

  Future<void> _persistSession() async {
    try {
      if (_currentUser != null) {
        await _storage.write(
          key: _kUserProfile,
          value: jsonEncode(_currentUser!.toJson()),
        );
        await _storage.write(
          key: _kDemoMode,
          value: _currentUser!.isDemoMode ? 'true' : 'false',
        );
      }
      if (_accessToken != null) {
        await _storage.write(key: _kAccessToken, value: _accessToken);
      }
      if (_refreshToken != null) {
        await _storage.write(key: _kRefreshToken, value: _refreshToken);
      }
      if (_expiresAt != null) {
        await _storage.write(
          key: _kExpiresAt,
          value: _expiresAt!.toIso8601String(),
        );
      }
    } catch (_) {}
  }

  /// Tạo chuỗi PKCE `code_verifier` ngẫu nhiên an toàn (RFC 7636).
  static String generateCodeVerifier({int length = 64}) {
    const charset =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rng = math.Random.secure();
    return List<String>.generate(
      length,
      (_) => charset[rng.nextInt(charset.length)],
    ).join();
  }

  /// Tính `code_challenge = BASE64URL-ENCODE(SHA256(ASCII(code_verifier)))` không padding.
  static String computeCodeChallenge(String codeVerifier) {
    final digest = _sha256Bytes(ascii.encode(codeVerifier));
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  /// Cài đặt SHA-256 thuần Dart (không cần thêm gói `crypto` ngoài).
  static Uint8List _sha256Bytes(List<int> input) {
    final primes = _firstPrimes(64);
    final h = List<int>.generate(8, (i) {
      final root = math.sqrt(primes[i]);
      return ((root - root.floor()) * 4294967296.0).floor() & 0xFFFFFFFF;
    });
    final k = List<int>.generate(64, (i) {
      final root = math.pow(primes[i], 1 / 3).toDouble();
      return ((root - root.floor()) * 4294967296.0).floor() & 0xFFFFFFFF;
    });

    final bitLength = input.length * 8;
    final padded = BytesBuilder(copy: false)
      ..add(input)
      ..addByte(0x80);
    while ((padded.length % 64) != 56) {
      padded.addByte(0x00);
    }
    final lenBytes = ByteData(8)..setUint64(0, bitLength, Endian.big);
    padded.add(lenBytes.buffer.asUint8List());

    final data = padded.toBytes();
    final w = Uint32List(64);

    int rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xFFFFFFFF;

    for (var offset = 0; offset < data.length; offset += 64) {
      final view = ByteData.sublistView(data, offset, offset + 64);
      for (var i = 0; i < 16; i++) {
        w[i] = view.getUint32(i * 4, Endian.big);
      }
      for (var i = 16; i < 64; i++) {
        final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
      }

      var a = h[0];
      var b = h[1];
      var c = h[2];
      var d = h[3];
      var e = h[4];
      var f = h[5];
      var g = h[6];
      var hh = h[7];

      for (var i = 0; i < 64; i++) {
        final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
        final temp1 = (hh + s1 + ch + k[i] + w[i]) & 0xFFFFFFFF;
        final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xFFFFFFFF;

        hh = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xFFFFFFFF;
      }

      h[0] = (h[0] + a) & 0xFFFFFFFF;
      h[1] = (h[1] + b) & 0xFFFFFFFF;
      h[2] = (h[2] + c) & 0xFFFFFFFF;
      h[3] = (h[3] + d) & 0xFFFFFFFF;
      h[4] = (h[4] + e) & 0xFFFFFFFF;
      h[5] = (h[5] + f) & 0xFFFFFFFF;
      h[6] = (h[6] + g) & 0xFFFFFFFF;
      h[7] = (h[7] + hh) & 0xFFFFFFFF;
    }

    final result = ByteData(32);
    for (var i = 0; i < 8; i++) {
      result.setUint32(i * 4, h[i], Endian.big);
    }
    return result.buffer.asUint8List();
  }

  static List<int> _firstPrimes(int count) {
    final primes = <int>[];
    var candidate = 2;
    while (primes.length < count) {
      var isPrime = true;
      for (final p in primes) {
        if (p * p > candidate) break;
        if (candidate % p == 0) {
          isPrime = false;
          break;
        }
      }
      if (isPrime) primes.add(candidate);
      candidate++;
    }
    return primes;
  }
}
